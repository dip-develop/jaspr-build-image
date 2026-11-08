#!/usr/bin/env bash
# Installs the pinned Tailwind CSS standalone CLI.
#
# This file is the ONLY place the Tailwind version, asset ids and digests live,
# and both image flavours (dart, flutter) call this same script, so the two
# toolchains cannot drift.
#
# Why the asset API instead of /releases/download/: GitHub's release-download
# endpoint negative-caches a 504 from its edge for ALL release assets, which is
# why every consumer's `docker build` failed. The asset API is the working path,
# and the sha256 below is the contract: a truncated or substituted body fails
# loudly here instead of producing a silently different CSS binary.
#
# Usage: install-tailwind.sh <version> <targetarch>
set -eu

version="${1:?usage: install-tailwind.sh <version> <targetarch>}"
targetarch="${2:?usage: install-tailwind.sh <version> <targetarch>}"

# Version -> per-architecture asset id and sha256. Bumping Tailwind means adding a
# case branch here AND bumping the tag in docker/*.Dockerfile and the workflow;
# tool/check_image_build.dart fails the build if those disagree.
case "${version}" in
  4.3.0)
    case "${targetarch}" in
      arm64)
        asset=415534366
        sha=8f48dcb72be3b351c10563c5329b4638ba8516820dc3b3a1609625a166e87cbd
        ;;
      amd64)
        asset=415534359
        sha=73f0e5459054e5cfaa8ab6f3b940f3fbe0f13cc7fd83bc24e7c655033c203400
        ;;
      *)
        echo "install-tailwind: unsupported TARGETARCH '${targetarch}'" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "install-tailwind: no pins for Tailwind ${version}" >&2
    exit 1
    ;;
esac

command -v curl >/dev/null || {
  echo "install-tailwind: curl is missing from this base image" >&2
  exit 1
}

# --retry covers the intermittent 5xx behind issue #250; the sha256 check below
# still fails hard on a truncated body, so a retry cannot hide a real break.
curl -fsSL --retry 2 --retry-delay 5 \
  -H "Accept: application/octet-stream" \
  "https://api.github.com/repos/tailwindlabs/tailwindcss/releases/assets/${asset}" \
  -o /tmp/tailwindcss
echo "${sha}  /tmp/tailwindcss" | sha256sum -c -
install -m 0755 /tmp/tailwindcss /usr/local/bin/tailwindcss
rm -f /tmp/tailwindcss
tailwindcss --help >/dev/null
