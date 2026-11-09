# image: ghcr.io/dip-develop/jaspr-build-image:flutter-3.44.9-jaspr-0.23.5-tailwind-4.3.0
#
# Pinned Jaspr toolchain: Flutter SDK + jaspr_cli + the standalone Tailwind CSS
# v4 CLI. Consumer sites build FROM this so their build stage never touches the
# 504-prone release-download endpoint.
#
# This image is amd64 only: Flutter publishes no linux-arm64 archive, so an
# arm64 variant would be an arm64 OS carrying an x64 SDK that cannot execute.
#
# Two flavours exist for a real dependency reason: `build_modules` 5.x caps the
# Dart SDK at <3.13.0, so Flutter-based Jaspr sites cannot run Dart 3.13.4, while
# a Dart-only site does not need (or want) the Flutter SDK. Do not merge them.
# This Flutter 3.44.9 line ships Dart 3.12.2, which satisfies that same ceiling.
#
# The Flutter SDK is installed from Google's official release archive with a
# pinned sha256 (scripts/install-flutter.sh), on top of the official Dart image
# at exactly the Dart version Flutter 3.44.9 bundles. It is NOT taken from a
# third-party registry image: the `ghcr.io/cirruslabs/flutter` mirror stops at
# 3.44.0, so `flutter:3.44.9` never existed there, and a mirror that lags is not
# a pin.
#
# Every pin is part of this tag. Bump the tag and the pins together, then run
# `dart run tool/check_image_build.dart`.
FROM dart:3.12.2

# Flavour-specific setup: everything above the marker may differ between the
# two Dockerfiles; everything from the marker down must stay byte-identical.
#
# /opt/flutter/bin comes first so `dart` and `flutter` are the same SDK pair: the
# Dart bundled in the Flutter SDK shadows the identical SDK the `dart:3.12.2`
# base carries at /usr/lib/dart/bin.
ENV PATH="/opt/flutter/bin:/root/.pub-cache/bin:${PATH}"
# No usage reporting from a build.
ENV FLUTTER_SUPPRESS_ANALYTICS=true

ARG FLUTTER_VERSION

COPY scripts/install-flutter.sh /usr/local/bin/install-flutter.sh
RUN bash /usr/local/bin/install-flutter.sh "${FLUTTER_VERSION}"

# ---- end of flavour-specific setup ----

# Deliberately no defaults: a bare `docker build` must fail rather than silently
# produce an unpinned toolchain (the exact drift this repo removes elsewhere).
ARG JASPR_CLI_VERSION
ARG TW_VERSION
ARG TARGETARCH

RUN dart pub global activate jaspr_cli "${JASPR_CLI_VERSION}"

COPY scripts/install-tailwind.sh /usr/local/bin/install-tailwind.sh
RUN bash /usr/local/bin/install-tailwind.sh "${TW_VERSION}" "${TARGETARCH}"

RUN test -x /root/.pub-cache/bin/jaspr && tailwindcss --help >/dev/null

LABEL org.opencontainers.image.title="jaspr-build-image" \
      org.opencontainers.image.description="Pinned Jaspr toolchain: Dart or Flutter SDK + jaspr_cli + Tailwind CSS CLI v4"
