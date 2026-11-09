# AGENTS.md — `jaspr-build-image`

## What this repo is

The pin authority for two public GHCR toolchain base images,
`ghcr.io/dip-develop/jaspr-build-image`: a Dart flavour and a Flutter flavour,
each carrying `jaspr_cli` plus the Tailwind CSS v4 CLI. The Dart tag is
multi-arch (`linux/amd64` and `linux/arm64`); the Flutter tag is `linux/amd64`
only. Their consumers are **planned**, not current: no site has been migrated
yet — that is issue #2, one PR per repo.

It publishes to nobody's host. There is no deploy step, no environment, no
server and no running artifact anywhere: the only output is a package on GHCR,
and the only job a workflow here may have is building and pushing it.

## Branches

Single-branch repo: `main` is the integration line, there is no `develop`.
`chore/*`, `fix/*` and `docs/*` branch off `main`; open the PR with
`gh pr create --base main`. Use a merge commit, never squash. The operator
merges, tags and deletes branches. Never push directly to `main`.

## Before every PR

From the repo root:

```bash
dart analyze tool/
dart format tool/
dart run tool/check_image_build.dart
```

## The two flavours are not mergeable

`build_modules` 5.x caps the Dart SDK at `<3.13.0`. Flutter-based Jaspr sites
therefore cannot run Dart 3.13.4 and stay on the Flutter line (which ships Dart
3.12.2); a Dart-only site does not need the Flutter SDK. Merging the flavours
would break every Flutter consumer. Changing that needs an owner decision, not a
refactor.

They also differ in architecture: the Dart tag is published for
`linux/amd64,linux/arm64`, the Flutter tag for `linux/amd64` only. Flutter
publishes no linux-arm64 archive, so an arm64 variant would be an arm64 OS
carrying an x64 SDK whose `dart` needs `/lib64/ld-linux-x86-64.so.2`, which that
base lacks — a guaranteed failing `RUN`. Nothing is emulated and no manifest
pretends otherwise. No tag name encodes architecture, so both tags stay as they
are.

## Permissions are the contract

`.github/workflows/build-image.yml` gets `contents: read` + `packages: write`
and nothing else. It must never gain `pull_request`, `environment:`, deploy
secrets, or an SSH/scp step. `.github/workflows/ci.yml` stays read-only with no
`secrets.` reference at all.

`tool/check_image_build.dart` fails CI when the pins drift. It asserts, and
these lists are closed:

- the `FROM` lines, the `# image:` comments, the workflow `env:`/`tags:` copies,
  both installer version tables (each architecture's asset id and digest parsed
  from its own branch; the Flutter archive's host and digest) and `ci.yml`'s
  `sdk:` line, all byte-for-byte against the `const` block (`README.md` also
  spells the pins out, but it is documentation, not an assertion target);
- the two Dockerfiles are byte-identical from their
  `# ---- end of flavour-specific setup ----` marker down (a file-vs-file
  equality, so deleting the same line from both tails passes — a known limit);
- `build-image.yml`'s job keys are exactly `dart-image` then `flutter-image`,
  each with its expected platforms (`linux/amd64,linux/arm64` for dart,
  `linux/amd64` for flutter), its own `file:`, `push: true`,
  `provenance: false`, its own GHCR login, its own build args and its own cache
  scope; `FLUTTER_VERSION` appears only in the flutter job;
- its publish trigger is exactly `on.push.branches: [main]`;
- its `permissions:` block grants only `contents: read` and `packages: write`,
  and `GITHUB_TOKEN` is its only secret;
- `ci.yml` has exactly one job, triggers on `pull_request`, and holds no write
  scope (`write-all` included) and no secret.

Do not weaken the checker to make a red run green — fix the workflow or the file
it names.

## English

Comments, docs and commit messages are in English.

## No cron or other recurring job

Nothing here runs on a schedule. Publishing happens on merge to `main` and on
manual `workflow_dispatch` only.
