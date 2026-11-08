/// Pin hygiene for the two published Jaspr toolchain images. The published
/// image, the Dockerfiles that build it and the installers that feed them must
/// agree on every pin before a tag goes to GHCR.
///
/// **The `const` block below is the only place a pin is *chosen*.** Every other
/// occurrence of a pin value is a *copy*, and this checker asserts each copy
/// byte-for-byte. The copies are:
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
/// Nothing outside that list may hold a pin value.
///
/// The two flavours exist for a real dependency reason and must stay separate
/// images, so the strongest structural check here is that everything from the
/// `# ---- end of flavour-specific setup ----` marker down is byte-identical in
/// both Dockerfiles: the shared tail cannot drift apart. Only the region above
/// the marker is flavour-specific.
///
/// The workflow is checked per job, not per file: platforms, tags, cache scope
/// and the Flutter build arg live inside a job segment, so a change to one job
/// cannot be masked by the other job's copy of the same line. The job set, the
/// `permissions:` block and the `secrets.` allowlist are closed lists: a new
/// job, a new permission or a second secret fails.
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
  }

  // Shared-tail equality: everything from the flavour marker down is identical.
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
    'xz-utils',
    "git config --global --add safe.directory '*'",
    'dart --version',
  ], change: 'keep it in the Flutter installer');
  _expectMatch(
    findings,
    flutterInstallerPath,
    flutterInstaller,
    RegExp(r'^flutter .*--version ', multiLine: true),
    change: 'the installer must smoke-check `flutter --version`',
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
    if (!segment.contains('platforms: linux/amd64,linux/arm64')) {
      findings.add(
        '$buildWorkflowPath: $label does not publish both platforms — its '
        '`platforms:` line must read `linux/amd64,linux/arm64`',
      );
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
    if (dartJob.contains('FLUTTER_VERSION')) {
      findings.add(
        '$buildWorkflowPath: the `dart-image:` job passes `FLUTTER_VERSION` — '
        'only the flutter flavour installs a Flutter SDK',
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
    if (!flutterJob.contains('FLUTTER_VERSION=\${{ env.FLUTTER_VERSION }}')) {
      findings.add(
        '$buildWorkflowPath: the `flutter-image:` job does not pass '
        '`FLUTTER_VERSION` — the Flutter installer would refuse the build, and '
        'the version must come from the `env:` block',
      );
    }
  }

  _expectPresent(findings, buildWorkflowPath, buildWorkflow, <String>[
    'JASPR_CLI_VERSION: $jasprCliPin',
    'TW_VERSION: $tailwindPin',
    'FLUTTER_VERSION: $flutterPin',
    'registry: ghcr.io',
    'username: \${{ github.actor }}',
    'password: \${{ secrets.$_onlySecret }}',
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
  stdout.writeln(
    'check_image_build: OK — $dartDockerfilePath, $flutterDockerfilePath, '
    '$buildWorkflowPath and the two installers agree on Dart $dartPin / Flutter '
    '$flutterPin (Dart $flutterDartPin bundled), jaspr_cli $jasprCliPin and '
    'Tailwind $tailwindPin; the Flutter SDK comes from the sha256-pinned archive '
    '$flutterArchive; tags $dartTag and $flutterTag.',
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
