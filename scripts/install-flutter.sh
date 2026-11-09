#!/usr/bin/env bash
# Installs the pinned Flutter SDK from Google's official release archive.
#
# This file is the ONLY place the Flutter archive path and its digest live, so a
# Flutter bump has exactly one table to edit for the download; the Dockerfile
# and the workflow carry the version, and tool/check_image_build.dart asserts
# that those copies still agree with this one.
#
# Why the official archive instead of a registry image: this image used to start
# FROM `ghcr.io/cirruslabs/flutter`, but that mirror stops at 3.44.0 —
# `manifests/3.44.9` answers MANIFEST_UNKNOWN — and this image's whole point is
# that every input is pinned by digest. A third-party tag that lags behind is
# not a pin; Google's release manifest plus the sha256 below is.
#
# The digest is the contract: a truncated or substituted tarball fails loudly
# here instead of producing a silently different toolchain. The value comes from
# https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
# (the `stable` entry whose `version` matches), and was re-verified on
# 2026-11-08 by streaming the published tarball through sha256sum.
#
# Note on architecture: Flutter publishes no linux/arm64 archive — the Linux
# release manifest has a single, x64 entry, and `releases_linux_arm64.json` is a
# 404 — so the image built from this script is published `linux/amd64` only. An
# arm64 variant would be an arm64 OS carrying this x64 SDK, and `dart` would
# need `/lib64/ld-linux-x86-64.so.2`, which that base does not have. That is an
# upstream Flutter limitation for Linux, not a choice made here.
#
# Usage: install-flutter.sh <version>
set -eu

version="${1:?usage: install-flutter.sh <version>}"

# Version -> archive path inside the release bucket and its sha256. Bumping
# Flutter means adding a case branch here AND bumping the tag comment, the
# `# image:` line, the workflow `env:`/`tags:` copies and (if the bundled Dart
# moves) `flutterDartPin` in tool/check_image_build.dart; the checker fails if
# those disagree.
case "${version}" in
  3.44.9)
    archive=stable/linux/flutter_linux_3.44.9-stable.tar.xz
    sha=a9120fa4a01048bdef438ddc3a2d4b7389662ea98a95db86eeaf10382bc4efcb
    ;;
  *)
    echo "install-flutter: no pins for Flutter ${version}" >&2
    exit 1
    ;;
esac

# xz-utils is the only Flutter Linux prerequisite this build needs and the
# official `dart:` image lacks; git, curl, unzip, tar and ca-certificates are
# already in it (checked against the image's own layer contents, not assumed).
# Other Flutter prerequisites are absent too (`zip`, `libglu1-mesa`), but a web
# build never invokes them, so they stay out of the image.
for tool in curl git tar sha256sum; do
  command -v "${tool}" >/dev/null || {
    echo "install-flutter: ${tool} is missing from this base image" >&2
    exit 1
  }
done

apt-get update
apt-get install -y --no-install-recommends xz-utils
rm -rf /var/lib/apt/lists/*

command -v xz >/dev/null || {
  echo "install-flutter: xz is still missing after installing xz-utils" >&2
  exit 1
}

tarball=/tmp/flutter.tar.xz
# --retry-all-errors retries a mid-body reset (curl exit 18), which plain
# --retry does not; the sha256 check below still fails hard on any bad body, so
# a retry cannot hide a real break.
curl -fsSL --retry 3 --retry-delay 5 --retry-all-errors \
  "https://storage.googleapis.com/flutter_infra_release/releases/${archive}" \
  -o "${tarball}"
echo "${sha}  ${tarball}" | sha256sum -c -

# The archive unpacks as `flutter/`, so it lands at /opt/flutter.
tar -xJf "${tarball}" -C /opt
rm -f "${tarball}"

# The archive's git metadata belongs to the upstream uid and the image runs as
# root: `flutter` runs `git rev-parse HEAD` on every invocation and refuses to
# start when git rejects the repository as unsafe.
git config --global --add safe.directory '*'

# No usage reporting from a build. The update check has no persistent config
# key (it is the per-invocation `--no-version-check` flag, and Flutter skips it
# on a detected CI/bot run), so the smoke check below disables it explicitly
# rather than pretending the image can turn it off globally.
export FLUTTER_SUPPRESS_ANALYTICS=true

# Smoke check: the archive may report its version as "unknown", so only a
# non-zero exit counts as a failure. `dart` must resolve to the SDK Flutter
# bundles, which is why PATH puts /opt/flutter/bin first.
flutter --no-version-check --version >/dev/null
dart --version >/dev/null

test -x /opt/flutter/bin/flutter
