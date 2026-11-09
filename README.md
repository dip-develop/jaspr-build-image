# jaspr-build-image

## What this is

One public package on the GitHub Container Registry:
`ghcr.io/dip-develop/jaspr-build-image`. It holds two pinned toolchain base
images that Jaspr sites build `FROM`: the Dart flavour is multi-arch
(`linux/amd64` and `linux/arm64`), the Flutter flavour is `linux/amd64` only.

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

| Tag | Base | Contents | Architectures | Planned consumers |
|---|---|---|---|---|
| `dart-3.13.4-jaspr-0.23.5-tailwind-4.3.0` | `dart:3.13.4` | Dart SDK 3.13.4, `jaspr_cli` 0.23.5, Tailwind CSS CLI 4.3.0 | `linux/amd64`, `linux/arm64` | `dipdev-website`, `alteri-one` |
| `flutter-3.44.9-jaspr-0.23.5-tailwind-4.3.0` | `dart:3.12.2` + Flutter 3.44.9 from the official archive | Flutter SDK 3.44.9 (ships Dart 3.12.2), `jaspr_cli` 0.23.5, Tailwind CSS CLI 4.3.0 | `linux/amd64` | `Gewerber/gewerber-website`, `EVEFrontier-Club/frontend` |

**No consumer has been migrated yet.** The consumer column is planned work
tracked in issue #2, one PR per repo: `dipdev-website` still builds from its own
`build-base/`, and `alteri-one` has no Dockerfile at all. Nothing in this repo
depends on that migration.

The two flavours cannot be merged. `build_modules` 5.x caps the Dart SDK at
`<3.13.0`, so a Flutter-based Jaspr site cannot run Dart 3.13.4 and must stay on
the Flutter line; a Dart-only site has no use for the Flutter SDK, which would
add gigabytes to every build for nothing.

They also differ in architecture. The Dart tag is published for `linux/amd64`
and `linux/arm64`; the Flutter tag is `linux/amd64` only, because Flutter
publishes no `linux-arm64` archive. Neither tag name encodes the architecture,
so the tag strings stay exactly as they are.

### Why the Flutter tag is amd64-only

Flutter publishes no Linux archive for arm64: its Linux release manifest lists
749 releases and not one `arm*` artifact, and `releases_linux_arm64.json`
answers 404. An arm64 variant of this image would be an arm64 OS carrying an x64
SDK whose `dart` needs `/lib64/ld-linux-x86-64.so.2`, which the arm64 base does
not contain — a guaranteed failing `RUN`. The job therefore publishes
`linux/amd64` alone: nothing is emulated and nothing pretends to be arm64. The
Dart tag stays native on both architectures.

### Where the Flutter SDK comes from

The Flutter flavour starts `FROM dart:3.12.2` — exactly the Dart SDK that
Flutter 3.44.9 bundles — and then installs Flutter 3.44.9 from Google's own
release archive, verified against a pinned sha256 (`scripts/install-flutter.sh`).
`PATH` puts `/opt/flutter/bin` first, so `dart` and `flutter` in the image are
the same SDK pair.

It is **not** built on a third-party registry image. The mirror this repo
originally targeted, `ghcr.io/cirruslabs/flutter`, stopped at `3.44.0`:
`manifests/3.44.9` answers `MANIFEST_UNKNOWN`, so a `FROM` there would fail at
the first instruction. The operator's decision was provenance by digest over a
stale tag — Google's release manifest plus a sha256 is a pin, a mirror that lags
is not.

## Using it

```dockerfile
FROM ghcr.io/dip-develop/jaspr-build-image:dart-3.13.4-jaspr-0.23.5-tailwind-4.3.0 AS build
```

`jaspr_cli` is already activated as `jaspr`, and `tailwindcss` is on `PATH` at
`/usr/local/bin/tailwindcss` — a consumer must not install either itself.

## Bumping a pin

Every pin is part of the tag, so a bump changes the tag and cache-busts the
build automatically. Change all of these together, then run the check:

1. The `const` block in `tool/check_image_build.dart` — the only place a pin is
   *chosen*: `dartPin`, `flutterPin`, `flutterDartPin` (the Dart SDK the Flutter
   release bundles), `jasprCliPin`, `tailwindPin`, and for a Tailwind release
   also `tailwindX64AssetId`, `tailwindArm64AssetId`, `tailwindX64Sha256` and
   `tailwindArm64Sha256`; for a Flutter release also `flutterArchiveSha256`.
   The two tag strings are derived from these.
2. The workflow `env:` block in `.github/workflows/build-image.yml`
   (`JASPR_CLI_VERSION`, `TW_VERSION`, `FLUTTER_VERSION`) and the two literal
   `tags:` lines in that file.
3. The two `# image:` comments (first line of `docker/dart.Dockerfile` and
   `docker/flutter.Dockerfile`) and the two `FROM` lines — the Dart flavour's
   `dart:<dartPin>`, the Flutter flavour's `dart:<flutterDartPin>`.
4. The version table in `scripts/install-tailwind.sh`. A new Tailwind version
   needs a new `case` branch with fresh asset ids and digests for both
   architectures; editing the existing branch would ship a binary that does not
   match its own sha256.
5. For a Flutter bump, the version table in `scripts/install-flutter.sh` — add
   a new `case` branch with the new archive path and the sha256 from the release
   manifest. If the bundled Dart moves, `flutterDartPin` in the `const` block and
   the Flutter `FROM` line move with it.
6. `.github/workflows/ci.yml`'s `sdk:` line, which must stay equal to
   `dartPin`, and `pubspec.yaml`'s `environment: sdk:` constraint, which must
   still admit the pinned Dart.
7. `dart run tool/check_image_build.dart` from the repo root — it fails and
   names the file that still disagrees.
8. The consumer `FROM` lines in the sites listed in the table above, as part of
   the migration in issue #2.

## The pin check

```bash
dart run tool/check_image_build.dart
```

Run it from the repo root. It is pin hygiene, not a release gate: it reports
drift and exits non-zero so CI shows it, with nothing measured against a
threshold.

The single-source rule, from the checker's doc comment:

> **The `const` block in `tool/check_image_build.dart` is the only place a pin
> is *chosen*.** Every copy of a pin that the checker owns is asserted
> byte-for-byte: the Dockerfile `# image:` comment, the `FROM` line, the
> workflow `env:` block, the workflow `tags:` line, the installer version
> tables and the `ci.yml` `sdk:` line. `README.md` also spells the pins out, but
> it is documentation, not an assertion target.

It also asserts the structure that makes those copies safe: the two Dockerfiles
are byte-identical from their `# ---- end of flavour-specific setup ----` marker
down (a file-vs-file equality, so deleting the same line from both tails would
pass — a known, accepted limit, since the per-pin assertions are what catch a
pin); `build-image.yml` has exactly the jobs `dart-image` and `flutter-image` in
that order, each publishing its own expected platforms
(`linux/amd64,linux/arm64` for the Dart tag, `linux/amd64` for the Flutter tag),
building its own `file:`, with `push: true`, `provenance: false`, its own GHCR
login and its own build args; its `permissions:` block grants only
`contents: read` and `packages: write`; its only secret is `GITHUB_TOKEN`; it
publishes only on `push: main`; and `ci.yml` stays read-only with one job that
triggers on `pull_request`.

## Operator steps

1. Merge the PR. The merge itself triggers the publish: `build-image.yml` runs
   on `push: main`, filtered to `docker/**`, `scripts/**` and the workflow file.
2. Watch the run finish on the Actions tab or with
   `gh run list --workflow build-image.yml`.
3. Set the package visibility to **PUBLIC**: Settings → Packages →
   `jaspr-build-image` → Change visibility. Both cross-org consumers will pull
   anonymously, so a private package breaks them.
4. Verify each tag against its own expected platforms, **anonymously**:

   ```bash
   docker logout ghcr.io
   docker buildx imagetools inspect ghcr.io/dip-develop/jaspr-build-image:<tag>
   ```

   the Dart tag must show `linux/amd64` **and** `linux/arm64`, the Flutter tag
   `linux/amd64` only (a second platform on it would be a lie). Logging out
   first is the point: `imagetools inspect` uses the caller's stored
   credentials, so it succeeds on a package that is still private and the check
   would prove nothing. The credential-free equivalent is the anonymous-token
   probe —
   `curl -fsSL "https://ghcr.io/token?scope=repository:dip-develop/jaspr-build-image:pull"`
   only issues a token for a public package, and the manifest request made with
   it is what a consumer does.
5. If the Tailwind fetch 504s, retry with `workflow_dispatch`
   (`gh workflow run build-image.yml`) — **but only if nothing was pushed**. The
   two jobs are independent: `dart-image` can finish and publish its tag while
   `flutter-image` fails, so a re-run after a partial success rewrites a tag that
   already exists rather than starting from an empty package.

## Known risk

`api.github.com` content endpoints (the asset API this repo downloads from) also
return 504 intermittently, so even the one-time download can fail. The fallback
is to vendor the two ~119 MB binaries in this repo and `COPY` plus
`sha256sum -c` them instead of curling. That is a deliberate owner decision
(repo bloat), not a drive-by change — do not add vendored binaries without it.

All three pinned downloads were verified against the real bytes on 2026-11-08:
the two Tailwind binaries, and the Flutter 3.44.9 Linux archive (streamed
through `sha256sum` and compared with the official release manifest), so the pins
themselves are known-good; a failure at build time is the network, not the data.

Flutter publishes **no `linux/arm64` Linux archive**; the consequence for this
repo's tags is spelled out in [Why the Flutter tag is amd64-only](#why-the-flutter-tag-is-amd64-only).

## Layout

- `docker/` — the two Dockerfiles; flavour-specific above their
  `# ---- end of flavour-specific setup ----` marker, byte-identical from it down
  by design.
- `scripts/` — `install-tailwind.sh` and `install-flutter.sh`, the only holders
  of the Tailwind asset ids and digests and of the Flutter archive path and
  digest.
- `tool/` — `check_image_build.dart`, the pin checker.
- `.github/workflows/` — `build-image.yml` publishes; `ci.yml` runs the checker
  read-only.
