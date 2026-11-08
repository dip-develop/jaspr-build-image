# jaspr-build-image

## What this is

One public package on the GitHub Container Registry:
`ghcr.io/dip-develop/jaspr-build-image`. It holds two multi-arch toolchain base
images (`linux/amd64` and `linux/arm64`) that Jaspr sites build `FROM`.

Nothing is deployed from this repository. It publishes a toolchain image and
nothing else — no site, no server, no host.

## Why it exists

GitHub's release-download endpoint
(`github.com/<org>/<repo>/releases/download/...`) returns HTTP 504 from GitHub's
own edge — observed in region `fra`, negative-cached across all release assets.
Every consumer's `docker build` curled the Tailwind standalone CLI from that
endpoint and failed; rebuilding did not help while the negative cache lived.

The download now happens once, at image-build time, into a cached GHCR layer,
and the body is verified against a pinned sha256 before it is installed.

## The two tags

| Tag | Base | Contents | Consumers |
|---|---|---|---|
| `dart-3.13.4-jaspr-0.23.5-tailwind-4.3.0` | `dart:3.13.4` | Dart SDK 3.13.4, `jaspr_cli` 0.23.5, Tailwind CSS CLI 4.3.0 | `dipdev-website`, `alteri-one` |
| `flutter-3.44.9-jaspr-0.23.5-tailwind-4.3.0` | `ghcr.io/cirruslabs/flutter:3.44.9` | Flutter SDK 3.44.9 (ships Dart 3.12.2), `jaspr_cli` 0.23.5, Tailwind CSS CLI 4.3.0 | `Gewerber/gewerber-website`, `EVEFrontier-Club/frontend` |

The two flavours cannot be merged. `build_modules` 5.x caps the Dart SDK at
`<3.13.0`, so a Flutter-based Jaspr site cannot run Dart 3.13.4 and must stay on
the Flutter line; a Dart-only site has no use for the Flutter SDK, which would
add gigabytes to every build for nothing.

## Using it

```dockerfile
FROM ghcr.io/dip-develop/jaspr-build-image:dart-3.13.4-jaspr-0.23.5-tailwind-4.3.0 AS build
```

`jaspr_cli` is already activated as `jaspr`, and `tailwindcss` is on `PATH` at
`/usr/local/bin/tailwindcss` — a consumer must not install either itself.

## Bumping a pin

Every pin is part of the tag, so a bump changes the tag and cache-busts the
build automatically. Change all of these together, then run the check:

1. The `const` block in `tool/check_image_build.dart`: `dartPin`, `flutterPin`,
   `jasprCliPin`, `tailwindPin`, and for a new Tailwind release also
   `tailwindX64AssetId`, `tailwindArm64AssetId`, `tailwindX64Sha256` and
   `tailwindArm64Sha256`. The two tag strings are derived from these.
2. The workflow `env:` block in `.github/workflows/build-image.yml`
   (`JASPR_CLI_VERSION`, `TW_VERSION`) and the two literal `tags:` lines in that
   file.
3. The two `# image:` comments (first line of `docker/dart.Dockerfile` and
   `docker/flutter.Dockerfile`) and the two `FROM` lines.
4. The version table in `scripts/install-tailwind.sh`. A new Tailwind version
   needs a new `case` branch with fresh asset ids and digests for both
   architectures; editing the existing branch would ship a binary that does not
   match its own sha256.
5. `dart run tool/check_image_build.dart` from the repo root — it fails and
   names the file that still disagrees.
6. The consumer `FROM` lines in the sites listed in the table above.

## The pin check

```bash
dart run tool/check_image_build.dart
```

Run it from the repo root. It is pin hygiene, not a release gate: it reports
drift and exits non-zero so CI shows it, with nothing measured against a
threshold.

The single-copy rule, from the checker's doc comment:

> **A pin value may appear in exactly two places**: this `const` block, and the
> one file that consumes it. Every other file is forbidden from holding it.

## Operator steps

1. Merge the PR. The merge itself triggers the publish: `build-image.yml` runs
   on `push: main`, filtered to `docker/**`, `scripts/**` and the workflow file.
2. Watch the run finish on the Actions tab or with
   `gh run list --workflow build-image.yml`.
3. Set the package visibility to **PUBLIC**: Settings → Packages →
   `jaspr-build-image` → Change visibility. Both cross-org consumers pull
   anonymously, so a private package breaks them.
4. Verify both platforms on both tags:
   `docker buildx imagetools inspect ghcr.io/dip-develop/jaspr-build-image:<tag>`
   must show `linux/amd64` and `linux/arm64`.
5. If the Tailwind fetch 504s, retry with `workflow_dispatch`
   (`gh workflow run build-image.yml`). Nothing was published, so a re-run is
   safe.

## Known risk

`api.github.com` content endpoints (the asset API this repo downloads from) also
return 504 intermittently, so even the one-time download can fail. The fallback
is to vendor the two ~119 MB binaries in this repo and `COPY` plus
`sha256sum -c` them instead of curling. That is a deliberate owner decision
(repo bloat), not a drive-by change — do not add vendored binaries without it.

Both digests were verified against the real binaries on 2026-11-08, so the pins
themselves are known-good; a failure at build time is the network, not the data.

## Layout

- `docker/` — the two Dockerfiles; identical below their `FROM` line by design.
- `scripts/` — `install-tailwind.sh`, the only holder of Tailwind asset ids and
  digests.
- `tool/` — `check_image_build.dart`, the pin checker.
- `.github/workflows/` — `build-image.yml` publishes; `ci.yml` runs the checker
  read-only.
