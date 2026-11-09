/// Pin hygiene for the two published Jaspr toolchain images. The published
/// image, the Dockerfiles that build it and the installers that feed them must
/// agree on every pin before a tag goes to GHCR.
///
/// **The `const` block below is the only place a pin is *chosen*.** Every copy
/// of a pin that this checker owns is asserted byte-for-byte. Those copies are:
///
/// - the `# image:` comment at the top of each Dockerfile (the derived tag);
/// - the `FROM` line of each Dockerfile — `dart:<dartPin>` for the Dart flavour,
///   `dart:<flutterDartPin>` for the Flutter flavour, whose Flutter archive is
///   pinned by sha256 in `scripts/install-flutter.sh` (a `FROM` cannot be an
///   `ARG` without losing readability and `docker manifest` tooling);
/// - the workflow `env:` block (`JASPR_CLI_VERSION`, `TW_VERSION`,
///   `FLUTTER_VERSION`) and the two literal `tags:` lines;
/// - the version table in `scripts/install-tailwind.sh`, including the per-
///   architecture asset ids and digests, and the archive table in
///   `scripts/install-flutter.sh`;
/// - the `sdk:` line of `.github/workflows/ci.yml`.
///
/// `README.md` also spells every pin out, but it is documentation, not an
/// assertion target: it is written for humans and may hold the full tags in
/// prose without this file checking them.
///
/// The two flavours exist for a real dependency reason and must stay separate
/// images, so the strongest structural check here is that everything from the
/// `# ---- end of flavour-specific setup ----` marker down is byte-identical in
/// both Dockerfiles: the shared tail cannot drift apart. Only the region above
/// the marker is flavour-specific.
///
/// The workflow is checked per job, not per file: platforms, tags, the
/// `file:`, `push:`, `provenance:` and login fields, the cache scope and the
/// build args all live inside a job segment, so a change to one job cannot be
/// masked by the other job's copy of the same line. `platforms:` is read from
/// the `docker/build-push-action` step block alone — other steps take that
/// input too (the documented `docker/setup-qemu-action` one), and that is
/// emulation setup, not a publish platform. The expected platforms are
/// per flavour, because the Flutter flavour publishes `linux/amd64` only: Flutter
/// ships no `linux-arm64` archive, so an arm64 variant would be an arm64 base
/// carrying an x64 SDK. The job set, the publish trigger, the `permissions:`
/// block and the `secrets.` allowlist are closed lists: a new job, a widened
/// trigger, a new permission or a second secret fails.
///
/// Pin hygiene, not a release gate: it reports drift and exits non-zero so CI
/// shows it; nothing is measured against a threshold.
///
/// Run with: `dart run tool/check_image_build.dart`
import 'dart:io';

const String dartPin = '3.13.4';
const String flutterPin = '3.44.9';

/// The Dart SDK that Flutter 3.44.9 bundles. The Flutter flavour starts FROM
/// the official Dart image at exactly this version, so the `dart` it exposes
/// and the one inside the Flutter SDK are the same SDK pair.
const String flutterDartPin = '3.12.2';
const String jasprCliPin = '0.23.5';
const String tailwindPin = '4.3.0';

const String tailwindX64AssetId = '415534359';
const String tailwindArm64AssetId = '415534366';
const String tailwindX64Sha256 =
    '73f0e5459054e5cfaa8ab6f3b940f3fbe0f13cc7fd83bc24e7c655033c203400';
const String tailwindArm64Sha256 =
    '8f48dcb72be3b351c10563c5329b4638ba8516820dc3b3a1609625a166e87cbd';

/// The `stable` Linux entry for [flutterPin] in
/// `flutter_infra_release/releases/releases_linux.json`.
const String flutterArchive =
    'stable/linux/flutter_linux_$flutterPin-stable.tar.xz';
const String flutterArchiveSha256 =
    'a9120fa4a01048bdef438ddc3a2d4b7389662ea98a95db86eeaf10382bc4efcb';

const String imageRepo = 'ghcr.io/dip-develop/jaspr-build-image';
const String dartTag = 'dart-$dartPin-jaspr-$jasprCliPin-tailwind-$tailwindPin';
const String flutterTag =
    'flutter-$flutterPin-jaspr-$jasprCliPin-tailwind-$tailwindPin';
const String dartImage = '$imageRepo:$dartTag';
const String flutterImage = '$imageRepo:$flutterTag';

const String dartDockerfilePath = 'docker/dart.Dockerfile';
const String flutterDockerfilePath = 'docker/flutter.Dockerfile';
const String tailwindInstallerPath = 'scripts/install-tailwind.sh';
const String flutterInstallerPath = 'scripts/install-flutter.sh';
const String buildWorkflowPath = '.github/workflows/build-image.yml';
const String ciWorkflowPath = '.github/workflows/ci.yml';

/// Everything from this line down must be byte-identical in both Dockerfiles.
/// Above it is flavour-specific setup and is deliberately not compared.
const String flavourMarker = '# ---- end of flavour-specific setup ----';

/// The build args both Dockerfiles declare bare, so a `docker build` without
/// `--build-arg` fails rather than shipping an unpinned toolchain.
const List<String> _bareArgs = <String>[
  'ARG JASPR_CLI_VERSION',
  'ARG TW_VERSION',
  'ARG TARGETARCH',
];

/// Build args only the flavour that consumes them may declare.
const Map<String, List<String>> _flavourBareArgs = <String, List<String>>{
  flutterDockerfilePath: <String>['ARG FLUTTER_VERSION'],
};

/// The exact jobs `build-image.yml` may have, in order.
const List<String> _buildJobs = <String>['dart-image', 'flutter-image'];

/// The platforms each job must publish. The Dart flavour is multi-arch; the
/// Flutter flavour is amd64 only, because Flutter publishes no `linux-arm64`
/// archive: an arm64 variant would be an arm64 base carrying an x64 SDK whose
/// `dart` needs `/lib64/ld-linux-x86-64.so.2`, which that base does not have.
/// No tag name encodes the architecture, so both tags stay as they are.
const Map<String, String> _expectedPlatforms = <String, String>{
  'dart-image': 'linux/amd64,linux/arm64',
  'flutter-image': 'linux/amd64',
};

/// The Dockerfile each job must build. A swap publishes the Dart toolchain under
/// the Flutter tag (or the reverse) with a green check.
const Map<String, String> _expectedDockerfile = <String, String>{
  'dart-image': dartDockerfilePath,
  'flutter-image': flutterDockerfilePath,
};

/// Build args every job must pass, from the workflow `env:` block.
const List<String> _sharedBuildArgs = <String>[
  'JASPR_CLI_VERSION',
  'TW_VERSION',
];

/// Build args only the named job may pass.
const Map<String, List<String>> _jobBuildArgs = <String, List<String>>{
  'flutter-image': <String>['FLUTTER_VERSION'],
};

/// The only permissions `build-image.yml` may grant.
const Map<String, String> _allowedPermissions = <String, String>{
  'contents': 'read',
  'packages': 'write',
};

/// The only secret `build-image.yml` may use.
const String _onlySecret = 'GITHUB_TOKEN';

/// Ways a build workflow turns into a deploy workflow. None may appear.
const List<String> _deployTokens = <String>[
  'pull_request',
  'environment:',
  'appleboy',
  'scp',
  ':latest',
  'secrets.VPS',
  'secrets.SSH',
];

void main() {
  const files = <String>[
    dartDockerfilePath,
    flutterDockerfilePath,
    tailwindInstallerPath,
    flutterInstallerPath,
    buildWorkflowPath,
    ciWorkflowPath,
  ];
  final missing = <String>[
    for (final path in files)
      if (!File(path).existsSync()) path,
  ];
  if (missing.isNotEmpty) {
    _fail(<String>[
      for (final path in missing)
        '$path: missing — this check cannot assert its pins without the file',
    ]);
  }

  final findings = <String>[];
  final dartDockerfile = File(dartDockerfilePath).readAsStringSync();
  final flutterDockerfile = File(flutterDockerfilePath).readAsStringSync();
  final tailwindInstaller = File(tailwindInstallerPath).readAsStringSync();
  final flutterInstaller = File(flutterInstallerPath).readAsStringSync();
  final buildWorkflow = File(buildWorkflowPath).readAsStringSync();
  final ciWorkflow = File(ciWorkflowPath).readAsStringSync();

  // ── Dockerfiles ───────────────────────────────────────────────────────────

  // Each SDK version lives in exactly one FROM line.
  _expectOnce(
    findings,
    dartDockerfilePath,
    dartDockerfile,
    'FROM dart:$dartPin',
    change: 'pin the Dart SDK there, not in an ARG',
  );
  _expectOnce(
    findings,
    flutterDockerfilePath,
    flutterDockerfile,
    'FROM dart:$flutterDartPin',
    change: 'start the Flutter flavour FROM the Dart SDK it bundles',
  );

  // The derived tag name lives exactly once per Dockerfile, as a comment.
  _expectOnce(
    findings,
    dartDockerfilePath,
    dartDockerfile,
    '# image: $dartImage',
    change: 'keep exactly one `# image: $dartImage` line at the top',
  );
  _expectOnce(
    findings,
    flutterDockerfilePath,
    flutterDockerfile,
    '# image: $flutterImage',
    change: 'keep exactly one `# image: $flutterImage` line at the top',
  );

  // A copy-paste swap between the flavours is the mistake this catches. Match
  // the derived tags, not the bare `dart-` / `flutter-` prefixes: a comment
  // such as `# see dart-lang/setup-dart` is not a tag.
  final dartTagPattern = RegExp(r'dart-\d+-jaspr-');
  final flutterTagPattern = RegExp(r'flutter-\d+-jaspr-');
  if (dartDockerfile.contains(flutterTag) ||
      flutterTagPattern.hasMatch(dartDockerfile)) {
    findings.add(
      '$dartDockerfilePath: mentions `$flutterTag` — this is the Dart flavour; '
      'that tag belongs to $flutterDockerfilePath',
    );
  }
  if (flutterDockerfile.contains(dartTag) ||
      dartTagPattern.hasMatch(flutterDockerfile)) {
    findings.add(
      '$flutterDockerfilePath: mentions `$dartTag` — this is the Flutter '
      'flavour; that tag belongs to $dartDockerfilePath',
    );
  }

  // The Flutter SDK must not come from a third-party registry image. The prose
  // explaining why is welcome; a `FROM` pointing there is not.
  if (RegExp(
    r'^FROM\s+\S*cirruslabs',
    multiLine: true,
  ).hasMatch(flutterDockerfile)) {
    findings.add(
      '$flutterDockerfilePath: starts FROM a `cirruslabs` image — the Flutter '
      'SDK is installed from the official archive by $flutterInstallerPath, '
      'because that mirror stops at 3.44.0',
    );
  }

  // Build args must be bare: `ARG X=1.2.3` would silently override CI.
  final dockerfiles = <String, String>{
    dartDockerfilePath: dartDockerfile,
    flutterDockerfilePath: flutterDockerfile,
  };
  for (final entry in dockerfiles.entries) {
    for (final arg in _bareArgs) {
      if (!RegExp('^$arg\$', multiLine: true).hasMatch(entry.value)) {
        findings.add(
          '${entry.key}: `$arg` is missing or carries a default — declare it '
          'bare so the workflow build args are the only source of the pin',
        );
      }
    }
  }
  for (final entry in _flavourBareArgs.entries) {
    for (final arg in entry.value) {
      if (!RegExp(
        '^$arg\$',
        multiLine: true,
      ).hasMatch(dockerfiles[entry.key]!)) {
        findings.add(
          '${entry.key}: `$arg` is missing or carries a default — declare it '
          'bare so the workflow build args are the only source of the pin',
        );
      }
    }
    // The other flavour must not declare it: nothing passes that arg there, so
    // it would be a pin-shaped hole in a Dockerfile that cannot consume it.
    for (final other in dockerfiles.keys) {
      if (other == entry.key) {
        continue;
      }
      for (final arg in entry.value) {
        if (RegExp('^$arg\$', multiLine: true).hasMatch(dockerfiles[other]!)) {
          findings.add(
            '$other: declares `$arg` — only ${entry.key} consumes it; nothing '
            'passes that build arg to the other flavour',
          );
        }
      }
    }
  }

  // Shared-tail equality: everything from the flavour marker down is identical.
  // This is a file-vs-file equality with a known, accepted limit: deleting the
  // same line from both tails keeps them equal and passes. It catches drift
  // between the two flavours; the per-pin assertions above are what catch a pin.
  final dartTail = _sharedTail(dartDockerfile);
  final flutterTail = _sharedTail(flutterDockerfile);
  if (dartTail == null) {
    findings.add(
      '$dartDockerfilePath: no `$flavourMarker` line — without it the two '
      'Dockerfiles have no agreed boundary to keep identical',
    );
  }
  if (flutterTail == null) {
    findings.add(
      '$flutterDockerfilePath: no `$flavourMarker` line — without it the two '
      'Dockerfiles have no agreed boundary to keep identical',
    );
  }
  if (dartTail != null && flutterTail != null && dartTail != flutterTail) {
    findings.add(
      '$dartDockerfilePath and $flutterDockerfilePath: the shared tail has '
      'diverged at line ${_firstDifferingLine(dartTail, flutterTail)} counting '
      'from the `$flavourMarker` marker — everything from that line down must '
      'stay byte-identical; only the region above it is flavour-specific',
    );
  }

  // ── Installers ────────────────────────────────────────────────────────────

  // Tailwind: the version table is the only holder of the asset ids and
  // digests. Parse each architecture branch, so a pair swapped between arm64
  // and amd64 is caught instead of passing a whole-file `contains`.
  _expectOnce(
    findings,
    tailwindInstallerPath,
    tailwindInstaller,
    '$tailwindPin)',
    change: 'add a `$tailwindPin)` branch to the version table',
  );
  final archPins = <String, ({String? asset, String? sha})>{
    'arm64': _archPins(tailwindInstaller, 'arm64'),
    'amd64': _archPins(tailwindInstaller, 'amd64'),
  };
  for (final expected in <String, ({String asset, String sha, String arch})>{
    'arm64': (
      asset: tailwindArm64AssetId,
      sha: tailwindArm64Sha256,
      arch: 'arm64',
    ),
    'amd64': (asset: tailwindX64AssetId, sha: tailwindX64Sha256, arch: 'amd64'),
  }.entries) {
    final parsed = archPins[expected.key]!;
    if (parsed.asset != expected.value.asset) {
      findings.add(
        '$tailwindInstallerPath: the `${expected.key})` branch downloads asset '
        '`${parsed.asset ?? 'none'}` — Tailwind $tailwindPin for '
        '${expected.value.arch} is `${expected.value.asset}`',
      );
    }
    if (parsed.sha != expected.value.sha) {
      findings.add(
        '$tailwindInstallerPath: the `${expected.key})` branch checks '
        '`${parsed.sha ?? 'no digest'}` — Tailwind $tailwindPin for '
        '${expected.value.arch} is `${expected.value.sha}`',
      );
    }
  }
  _expectPresent(
    findings,
    tailwindInstallerPath,
    tailwindInstaller,
    <String>['sha256sum -c', 'install -m 0755', 'tailwindcss --help'],
    change:
        'keep the download verified and install it in $tailwindInstallerPath',
  );

  // Flutter: the official archive table is the only place the archive path and
  // its digest live.
  _expectOnce(
    findings,
    flutterInstallerPath,
    flutterInstaller,
    '$flutterPin)',
    change: 'add a `$flutterPin)` branch to the version table',
  );
  _expectPresent(findings, flutterInstallerPath, flutterInstaller, <String>[
    'archive=$flutterArchive',
    'sha=$flutterArchiveSha256',
    'sha256sum -c',
    // The full apt line, not the bare package name: `xz-utils` also appears in
    // this file's comments, so a `contains` on the name passed after the
    // install line was deleted.
    'apt-get install -y --no-install-recommends xz-utils',
    "git config --global --add safe.directory '*'",
    'dart --version',
    // All provenance rests on this host: Google's own release bucket. Any other
    // URL would download a body whose sha256 pin no longer proves the origin.
    r'"https://storage.googleapis.com/flutter_infra_release/releases/${archive}"',
  ], change: 'keep it in the Flutter installer');
  _expectMatch(
    findings,
    flutterInstallerPath,
    flutterInstaller,
    RegExp(r'^flutter --no-version-check --version ', multiLine: true),
    change:
        'the smoke check must pass `--no-version-check`, or it performs a real '
        'update check during the image build',
  );

  // ── build-image.yml ───────────────────────────────────────────────────────

  final jobs = _jobs(buildWorkflow);
  final jobNames = jobs.keys.toList();
  if (jobNames.length != _buildJobs.length ||
      !_sameOrder(jobNames, _buildJobs)) {
    findings.add(
      '$buildWorkflowPath: the job keys are [${jobNames.join(', ')}] — this '
      'workflow may have exactly [${_buildJobs.join(', ')}], in that order, and '
      'no other job',
    );
  }

  for (final job in _buildJobs) {
    final segment = jobs[job];
    if (segment == null) {
      continue;
    }
    final label = 'the `$job:` job';

    // Platforms are asserted as a whole line, not a substring: `linux/amd64` is
    // a prefix of `linux/amd64,linux/arm64`, so `contains` would accept the
    // two-platform line where the one-platform line is expected. The scan is
    // scoped to the `docker/build-push-action` step: other steps take a
    // `platforms:` input too (`docker/setup-qemu-action` documents
    // `platforms: arm64`), and that is emulation setup, not what this job
    // publishes.
    final publishStep = _buildPushStep(segment);
    final platforms = publishStep == null
        ? const <String>[]
        : RegExp(r'^\s*platforms:[ \t]*(.*)$', multiLine: true)
              .allMatches(publishStep)
              .map((match) => match.group(1)!.trim())
              .toList();
    final expectedPlatforms = _expectedPlatforms[job]!;
    if (publishStep == null) {
      findings.add(
        '$buildWorkflowPath: $label has no `docker/build-push-action` step — '
        'its `platforms:` line must read `$expectedPlatforms` inside that step',
      );
    } else if (platforms.length != 1 || platforms.single != expectedPlatforms) {
      findings.add(
        '$buildWorkflowPath: $label publishes [${platforms.join(' | ')}] — its '
        '`platforms:` line must read `$expectedPlatforms`',
      );
    }

    // The publish-critical fields, each as its own line inside this job so the
    // sibling job's copy cannot satisfy it.
    final dockerfile = _expectedDockerfile[job]!;
    _expectJobLine(
      findings,
      label,
      segment,
      'file: $dockerfile',
      change: 'this job would build the wrong flavour',
    );
    _expectJobLine(
      findings,
      label,
      segment,
      'push: true',
      change: 'the run would go green with nothing published',
    );
    _expectJobLine(
      findings,
      label,
      segment,
      'provenance: false',
      change:
          'the OCI index gains attestation manifests and the platform check '
          'stops being unambiguous',
    );
    for (final field in <String>[
      'registry: ghcr.io',
      'username: \${{ github.actor }}',
      'password: \${{ secrets.$_onlySecret }}',
    ]) {
      _expectJobLine(
        findings,
        label,
        segment,
        field,
        change: 'the GHCR login is missing from this job',
      );
    }

    // Build args, per job: the shared pair from the `env:` block in both jobs,
    // `FLUTTER_VERSION` only where a Flutter SDK is installed.
    for (final name in _sharedBuildArgs) {
      _expectJobLine(
        findings,
        label,
        segment,
        '$name=\${{ env.$name }}',
        change:
            'the build arg must be passed from the `env:` block in both jobs',
      );
    }
    for (final entry in _jobBuildArgs.entries) {
      for (final name in entry.value) {
        if (entry.key == job) {
          _expectJobLine(
            findings,
            label,
            segment,
            '$name=\${{ env.$name }}',
            change: 'the build arg must be passed from the `env:` block',
          );
        } else if (segment.contains(name)) {
          findings.add(
            '$buildWorkflowPath: $label passes `$name` — only the '
            '`${entry.key}:` job may, and nothing installs that toolchain here',
          );
        }
      }
    }

    for (final other in _expectedDockerfile.values) {
      if (other != dockerfile && segment.contains(other)) {
        findings.add(
          '$buildWorkflowPath: $label mentions `$other` — a `file:` swap '
          'publishes the other flavour under this job\'s tag',
        );
      }
    }

    if (!segment.contains('cache-from: type=gha,scope=${_cacheScope(job)}')) {
      findings.add(
        '$buildWorkflowPath: $label does not read the '
        '`${_cacheScope(job)}` cache scope — two jobs sharing one scope fight '
        'over the same index and the 10 GB cap',
      );
    }
    if (!segment.contains(
      'cache-to: type=gha,mode=max,scope=${_cacheScope(job)}',
    )) {
      findings.add(
        '$buildWorkflowPath: $label does not write the '
        '`${_cacheScope(job)}` cache scope — see `cache-from` above',
      );
    }
  }

  final dartJob = jobs['dart-image'];
  final flutterJob = jobs['flutter-image'];
  if (dartJob != null) {
    if (!dartJob.contains(dartImage)) {
      findings.add(
        '$buildWorkflowPath: the `dart-image:` job does not tag `$dartImage` — '
        'put that tag on its `tags:` line',
      );
    }
    if (dartJob.contains(flutterTag) || flutterTagPattern.hasMatch(dartJob)) {
      findings.add(
        '$buildWorkflowPath: the `dart-image:` job mentions `flutter-` — the '
        'two tags are swapped between the jobs',
      );
    }
  }
  if (flutterJob != null) {
    if (!flutterJob.contains(flutterImage)) {
      findings.add(
        '$buildWorkflowPath: the `flutter-image:` job does not tag '
        '`$flutterImage` — put that tag on its `tags:` line',
      );
    }
    if (flutterJob.contains(dartTag) || dartTagPattern.hasMatch(flutterJob)) {
      findings.add(
        '$buildWorkflowPath: the `flutter-image:` job mentions `dart-` — the '
        'two tags are swapped between the jobs',
      );
    }
  }

  // The publish trigger is closed: only `main` may publish these tags. A glob
  // here would let any branch write the public tags.
  final branchLines = RegExp(
    r'^\s*branches:[ \t]*(.*)$',
    multiLine: true,
  ).allMatches(buildWorkflow).map((match) => match.group(1)!.trim()).toList();
  if (branchLines.length != 1 || branchLines.single != '[main]') {
    findings.add(
      '$buildWorkflowPath: the `on.push` branches are '
      '[${branchLines.join(' | ')}] — it must be exactly `branches: [main]`, '
      'or any other branch could publish the public tags',
    );
  }

  _expectPresent(findings, buildWorkflowPath, buildWorkflow, <String>[
    'JASPR_CLI_VERSION: $jasprCliPin',
    'TW_VERSION: $tailwindPin',
    'FLUTTER_VERSION: $flutterPin',
  ], change: 'keep it in $buildWorkflowPath at the level named above');

  // Closed secret allowlist: exactly one secret, no more, no less.
  final secretNames = RegExp(r'secrets\.([A-Za-z_][A-Za-z0-9_]*)')
      .allMatches(buildWorkflow)
      .map((match) => match.group(1)!)
      .toList();
  if (secretNames.isEmpty) {
    findings.add(
      '$buildWorkflowPath: no `secrets.` reference at all — the GHCR login '
      'cannot work, so the push would fail instead of the check',
    );
  }
  for (final name in secretNames.toSet()) {
    if (name != _onlySecret) {
      findings.add(
        '$buildWorkflowPath: uses `secrets.$name` — the only secret this '
        'workflow may read is `$_onlySecret`, a token scoped to the run',
      );
    }
  }

  // Closed permission allowlist: a new scope (id-token, attestations, …) fails.
  final permissions = _block(buildWorkflow, 'permissions');
  if (permissions == null) {
    findings.add(
      '$buildWorkflowPath: no `permissions:` block — the workflow would run '
      'with the repository default scopes',
    );
  } else if (permissions.length != _allowedPermissions.length ||
      _allowedPermissions.entries.any((e) => permissions[e.key] != e.value)) {
    final rendered = permissions.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    findings.add(
      '$buildWorkflowPath: `permissions:` grants [$rendered] — only '
      '[contents: read, packages: write] is allowed',
    );
  }

  for (final token in _deployTokens) {
    if (buildWorkflow.contains(token)) {
      findings.add(
        '$buildWorkflowPath: contains `$token` — this workflow publishes a '
        'public package and must never be able to reach a host',
      );
    }
  }

  // ── ci.yml ────────────────────────────────────────────────────────────────

  if (!ciWorkflow.contains('dart run tool/check_image_build.dart')) {
    findings.add(
      '$ciWorkflowPath: does not run `dart run tool/check_image_build.dart` — '
      'the pins would go unchecked on every PR',
    );
  }
  if (!ciWorkflow.contains('sdk: $dartPin')) {
    findings.add(
      '$ciWorkflowPath: does not pin `sdk: $dartPin` — the checker would run '
      'on a different Dart SDK than the one it pins',
    );
  }
  if (!RegExp(r'^\s+pull_request:', multiLine: true).hasMatch(ciWorkflow)) {
    findings.add(
      '$ciWorkflowPath: has no `pull_request:` trigger — the pins would only '
      'be checked after the merge that publishes them',
    );
  }
  final ciJobs = _jobs(ciWorkflow);
  if (ciJobs.length != 1) {
    findings.add(
      '$ciWorkflowPath: has ${ciJobs.length} jobs [${ciJobs.keys.join(', ')}] — '
      'CI is read-only and runs exactly one job, the pin check',
    );
  }
  for (final token in <String>[
    'packages: write',
    'contents: write',
    'write-all',
    'secrets.',
  ]) {
    if (ciWorkflow.contains(token)) {
      findings.add(
        '$ciWorkflowPath: contains `$token` — CI must stay read-only with no '
        'credentials',
      );
    }
  }

  if (findings.isNotEmpty) {
    _fail(findings);
  }
  final dartPlatforms = _expectedPlatforms['dart-image']!;
  final flutterPlatforms = _expectedPlatforms['flutter-image']!;
  stdout.writeln(
    'check_image_build: OK — $dartDockerfilePath, $flutterDockerfilePath, '
    '$buildWorkflowPath and the two installers agree on Dart $dartPin / Flutter '
    '$flutterPin (Dart $flutterDartPin bundled), jaspr_cli $jasprCliPin and '
    'Tailwind $tailwindPin; the Flutter SDK comes from the sha256-pinned archive '
    '$flutterArchive; tags $dartTag ($dartPlatforms) and '
    '$flutterTag ($flutterPlatforms).',
  );
}

/// The named top-level mapping block of a workflow, as key → value. Null when
/// the block is absent. Used for closed lists such as `permissions:`.
Map<String, String>? _block(String workflow, String name) {
  final header = RegExp(
    '^$name:[ \t]*\$',
    multiLine: true,
  ).firstMatch(workflow);
  if (header == null) {
    return null;
  }
  final block = <String, String>{};
  final lines = workflow.substring(header.end).split('\n');
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) {
      continue;
    }
    if (!line.startsWith('  ') || line.startsWith('   ')) {
      break;
    }
    final match = RegExp(r'^  ([A-Za-z0-9_-]+):\s*(\S+)\s*$').firstMatch(line);
    if (match == null) {
      break;
    }
    block[match.group(1)!] = match.group(2)!;
  }
  return block;
}

/// The `jobs:` block of a workflow as ordered job name → its segment text, so a
/// per-job assertion cannot be satisfied by a sibling job's line.
Map<String, String> _jobs(String workflow) {
  final header = RegExp(r'^jobs:[ \t]*$', multiLine: true).firstMatch(workflow);
  if (header == null) {
    return <String, String>{};
  }
  final body = workflow.substring(header.end);
  final headers = RegExp(
    r'^  ([A-Za-z0-9][A-Za-z0-9_-]*):[ \t]*$',
    multiLine: true,
  ).allMatches(body).toList();
  final jobs = <String, String>{};
  for (var i = 0; i < headers.length; i++) {
    final start = headers[i].start;
    final end = i + 1 < headers.length ? headers[i + 1].start : body.length;
    jobs[headers[i].group(1)!] = body.substring(start, end);
  }
  return jobs;
}

/// The asset id and sha256 of one architecture branch of the Tailwind version
/// table, parsed from that branch alone.
({String? asset, String? sha}) _archPins(String installer, String arch) {
  final branch = RegExp(
    '^\\s+$arch\\)\\s*\$',
    multiLine: true,
  ).firstMatch(installer);
  if (branch == null) {
    return (asset: null, sha: null);
  }
  final end = installer.indexOf(';;', branch.end);
  if (end == -1) {
    return (asset: null, sha: null);
  }
  final body = installer.substring(branch.end, end);
  return (
    asset: RegExp(
      r'^\s*asset=(\d+)\s*$',
      multiLine: true,
    ).firstMatch(body)?.group(1),
    sha: RegExp(
      r'^\s*sha=([0-9a-f]{64})\s*$',
      multiLine: true,
    ).firstMatch(body)?.group(1),
  );
}

/// Everything from the flavour marker to the end of the file, or null when the
/// marker is missing. The region above the marker is flavour-specific.
String? _sharedTail(String dockerfile) {
  final markerCount = flavourMarker.allMatches(dockerfile).length;
  final at = dockerfile.indexOf(flavourMarker);
  return markerCount == 1 && at != -1 ? dockerfile.substring(at) : null;
}

/// 1-based line number of the first difference between two tails.
int _firstDifferingLine(String a, String b) {
  final aLines = a.split('\n');
  final bLines = b.split('\n');
  final shorter = aLines.length < bLines.length ? aLines.length : bLines.length;
  for (var i = 0; i < shorter; i++) {
    if (aLines[i] != bLines[i]) {
      return i + 1;
    }
  }
  return shorter + 1;
}

/// The `docker/build-push-action` step block of one job segment: from that
/// step's `uses:` line up to the next step (`- …`) or the end of the segment.
/// Null when the job has no such step. Used to scope the `platforms:` assertion
/// to the step that publishes, so a `platforms:` input on another step (the
/// documented `docker/setup-qemu-action` input, for example) cannot satisfy or
/// corrupt it.
String? _buildPushStep(String segment) {
  final step = RegExp(
    r'^[ \t]*-[ \t]*uses:[ \t]*docker/build-push-action@',
    multiLine: true,
  ).firstMatch(segment);
  if (step == null) {
    return null;
  }
  final rest = segment.substring(step.end);
  final next = RegExp(r'^[ \t]*-[ \t]', multiLine: true).firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}

/// The GHA cache scope belonging to a job, derived from its name so the two
/// jobs can never claim the same scope.
String _cacheScope(String job) => job.replaceAll('-image', '');

bool _sameOrder(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      return false;
    }
  }
  return true;
}

/// Asserts that [needle] is a whole line of one job's segment — not merely a
/// substring, and not a line in a sibling job. Job segments start at the job
/// key, so an indentation-trimmed line comparison is exact enough here.
void _expectJobLine(
  List<String> findings,
  String label,
  String segment,
  String needle, {
  required String change,
}) {
  final lines = segment.split('\n').map((line) => line.trim());
  if (!lines.any((line) => line == needle)) {
    findings.add('$buildWorkflowPath: $label has no `$needle` line — $change');
  }
}

void _expectOnce(
  List<String> findings,
  String path,
  String text,
  String needle, {
  required String change,
}) {
  final count = needle.allMatches(text).length;
  if (count != 1) {
    findings.add('$path: `$needle` appears $count times — $change');
  }
}

void _expectPresent(
  List<String> findings,
  String path,
  String text,
  List<String> needles, {
  required String change,
}) {
  for (final needle in needles) {
    if (!text.contains(needle)) {
      findings.add('$path: `$needle` is missing — $change');
    }
  }
}

void _expectMatch(
  List<String> findings,
  String path,
  String text,
  RegExp pattern, {
  required String change,
}) {
  if (!pattern.hasMatch(text)) {
    findings.add('$path: `${pattern.pattern}` does not match — $change');
  }
}

/// Prints the findings and exits non-zero. `Never` so `main` knows the run
/// stops here.
Never _fail(List<String> findings) {
  stderr.writeln(
    'check_image_build: ${findings.length} pin hygiene finding(s):',
  );
  for (final finding in findings) {
    stderr.writeln('  - $finding');
  }
  exit(1);
}
