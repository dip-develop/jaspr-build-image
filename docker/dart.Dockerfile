# image: ghcr.io/dip-develop/jaspr-build-image:dart-3.13.4-jaspr-0.23.5-tailwind-4.3.0
#
# Pinned Jaspr toolchain: Dart SDK + jaspr_cli + the standalone Tailwind CSS v4
# CLI, multi-arch (linux/amd64 + linux/arm64). Consumer sites build FROM this so
# their build stage never touches the 504-prone release-download endpoint.
#
# Two flavours exist for a real dependency reason: `build_modules` 5.x caps the
# Dart SDK at <3.13.0, so Flutter-based Jaspr sites cannot run Dart 3.13.4, while
# a Dart-only site does not need (or want) the Flutter SDK. Do not merge them.
#
# Every pin is part of this tag. Bump the tag and the pins together, then run
# `dart run tool/check_image_build.dart`.
FROM dart:3.13.4

# Deliberately no defaults: a bare `docker build` must fail rather than silently
# produce an unpinned toolchain (the exact drift this repo removes elsewhere).
ARG JASPR_CLI_VERSION
ARG TW_VERSION
ARG TARGETARCH

RUN dart pub global activate jaspr_cli "${JASPR_CLI_VERSION}"
# The official dart image already exposes the pub cache bin dir; setting it here
# keeps both flavours byte-identical and makes `jaspr build` work in each.
ENV PATH="/root/.pub-cache/bin:${PATH}"

COPY scripts/install-tailwind.sh /usr/local/bin/install-tailwind.sh
RUN bash /usr/local/bin/install-tailwind.sh "${TW_VERSION}" "${TARGETARCH}"

RUN test -x /root/.pub-cache/bin/jaspr && tailwindcss --help >/dev/null

LABEL org.opencontainers.image.title="jaspr-build-image" \
      org.opencontainers.image.description="Pinned Jaspr toolchain: Dart or Flutter SDK + jaspr_cli + Tailwind CSS CLI v4 (multi-arch)"
