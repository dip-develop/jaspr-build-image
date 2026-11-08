/// Pin hygiene for the two published Jaspr toolchain images. The published
/// image, the Dockerfile that builds it and the installer that feeds it must
/// agree on every pin before a tag goes to GHCR.
///
/// **A pin value may appear in exactly two places**: this `const` block, and
/// the one file that consumes it. Every other file is forbidden from holding
/// it.
///
/// - SDK versions → the `FROM` line of each Dockerfile (a `FROM` cannot be an
///   `ARG` without losing readability and `docker manifest` tooling).
/// - `jaspr_cli` and Tailwind versions → the workflow `env:` block, passed as
///   build args. No Dockerfile holds a version default.
/// - Tailwind asset ids and sha256 digests → `scripts/install-tailwind.sh`'s
///   version table.
/// - The derived tags → one `# image:` comment per Dockerfile and one `tags:`
///   line per job.
///
/// The two flavours exist for a real dependency reason and must stay separate
/// images, so the strongest check here is that everything after their `FROM`
/// line is byte-identical: they cannot drift apart.
///
/// Pin hygiene, not a release gate: it reports drift and exits non-zero so CI
/// shows it; nothing is measured against a threshold.
///
/// Run with: `dart run tool/check_image_build.dart`
import 'dart:io';

const String dartPin = '3.13.4';
const String flutterPin = '3.44.9';
const String jasprCliPin = '0.23.5';
const String tailwindPin = '4.3.0';

const String tailwindX64AssetId = '415534359';
const String tailwindArm64AssetId = '415534366';
const String tailwindX64Sha256 =
    '73f0e5459054e5cfaa8ab6f3b940f3fbe0f13cc7fd83bc24e7c655033c203400';
const String tailwindArm64Sha256 =
    '8f48dcb72be3b351c10563c5329b4638ba8516820dc3b3a1609625a166e87cbd';

const String imageRepo = 'ghcr.io/dip-develop/jaspr-build-image';
const String dartTag = 'dart-$dartPin-jaspr-$jasprCliPin-tailwind-$tailwindPin';
const String flutterTag =
    'flutter-$flutterPin-jaspr-$jasprCliPin-tailwind-$tailwindPin';
const String dartImage = '$imageRepo:$dartTag';
const String flutterImage = '$imageRepo:$flutterTag';

const String dartDockerfilePath = 'docker/dart.Dockerfile';
const String flutterDockerfilePath = 'docker/flutter.Dockerfile';
const String installerPath = 'scripts/install-tailwind.sh';
const String buildWorkflowPath = '.github/workflows/build-image.yml';
const String ciWorkflowPath = '.github/workflows/ci.yml';

/// The build args the Dockerfiles declare bare, so a `docker build` without
/// `--build-arg` fails rather than shipping an unpinned toolchain.
const List<String> _bareArgs = <String>[
  'ARG JASPR_CLI_VERSION',
  'ARG TW_VERSION',
];

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
    installerPath,
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
  final installer = File(installerPath).readAsStringSync();
  final buildWorkflow = File(buildWorkflowPath).readAsStringSync();
  final ciWorkflow = File(ciWorkflowPath).readAsStringSync();

  // Each SDK version lives in exactly one FROM line.
  if (!dartDockerfile.contains('FROM dart:$dartPin')) {
    findings.add(
      '$dartDockerfilePath: the SDK line is not `FROM dart:$dartPin` — pin the '
      'Dart SDK there, not in an ARG',
    );
  }
  if (!flutterDockerfile.contains(
    'FROM ghcr.io/cirruslabs/flutter:$flutterPin',
  )) {
    findings.add(
      '$flutterDockerfilePath: the SDK line is not '
      '`FROM ghcr.io/cirruslabs/flutter:$flutterPin`',
    );
  }

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

  // A copy-paste swap between the flavours is the mistake this catches.
  if (dartDockerfile.contains('flutter-')) {
    findings.add(
      '$dartDockerfilePath: mentions `flutter-` — this is the Dart flavour; '
      'the `$flutterTag` tag and any Flutter reference belong to '
      '$flutterDockerfilePath',
    );
  }
  if (flutterDockerfile.contains('dart-')) {
    findings.add(
      '$flutterDockerfilePath: mentions `dart-` — this is the Flutter flavour; '
      'the `$dartTag` tag and any Dart reference belong to '
      '$dartDockerfilePath',
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

  // Post-FROM body equality: everything after the FROM line is identical.
  final dartBody = _postFromBody(dartDockerfile);
  final flutterBody = _postFromBody(flutterDockerfile);
  if (dartBody == null) {
    findings.add('$dartDockerfilePath: no `FROM` line to compare');
  }
  if (flutterBody == null) {
    findings.add('$flutterDockerfilePath: no `FROM` line to compare');
  }
  if (dartBody != null && flutterBody != null && dartBody != flutterBody) {
    final dartLines = dartBody.split('\n');
    final flutterLines = flutterBody.split('\n');
    final shorter = dartLines.length < flutterLines.length
        ? dartLines.length
        : flutterLines.length;
    var firstDiff = shorter;
    for (var i = 0; i < shorter; i++) {
      if (dartLines[i] != flutterLines[i]) {
        firstDiff = i;
        break;
      }
    }
    findings.add(
      '$dartDockerfilePath and $flutterDockerfilePath: the build stages have '
      'diverged at body line ${firstDiff + 1} after the FROM line — the two '
      'files must stay byte-identical from the FROM line down',
    );
  }

  // The installer is the only file holding the Tailwind version, asset ids and
  // digests.
  _expectPresent(findings, installerPath, installer, <String>[
    '$tailwindPin)',
    tailwindX64AssetId,
    tailwindArm64AssetId,
    tailwindX64Sha256,
    tailwindArm64Sha256,
    'sha256sum -c',
    'install -m 0755',
    'tailwindcss --help',
  ], change: 'add it to the version table of $installerPath');

  // Segment-aware job checks: a whole-file substring check cannot see a swapped
  // pair, a per-job slice can.
  const dartJobKey = '  dart-image:';
  const flutterJobKey = '  flutter-image:';
  final dartJobAt = buildWorkflow.indexOf(dartJobKey);
  final flutterJobAt = buildWorkflow.indexOf(flutterJobKey);
  if (dartJobKey.allMatches(buildWorkflow).length != 1 ||
      flutterJobKey.allMatches(buildWorkflow).length != 1 ||
      dartJobAt > flutterJobAt) {
    findings.add(
      '$buildWorkflowPath: expected exactly one `dart-image:` job followed by '
      'exactly one `flutter-image:` job',
    );
  } else {
    final dartJob = buildWorkflow.substring(dartJobAt, flutterJobAt);
    final flutterJob = buildWorkflow.substring(flutterJobAt);
    if (!dartJob.contains(dartImage)) {
      findings.add(
        '$buildWorkflowPath: the `dart-image:` job does not tag '
        '`$dartImage` — put that tag on its `tags:` line',
      );
    }
    if (dartJob.contains('flutter-')) {
      findings.add(
        '$buildWorkflowPath: the `dart-image:` job mentions `flutter-` — the '
        'two tags are swapped between the jobs',
      );
    }
    if (!flutterJob.contains(flutterImage)) {
      findings.add(
        '$buildWorkflowPath: the `flutter-image:` job does not tag '
        '`$flutterImage` — put that tag on its `tags:` line',
      );
    }
    if (flutterJob.contains('dart-')) {
      findings.add(
        '$buildWorkflowPath: the `flutter-image:` job mentions `dart-` — the '
        'two tags are swapped between the jobs',
      );
    }
  }

  _expectPresent(findings, buildWorkflowPath, buildWorkflow, <String>[
    'JASPR_CLI_VERSION: $jasprCliPin',
    'TW_VERSION: $tailwindPin',
    'platforms: linux/amd64,linux/arm64',
    'contents: read',
    'packages: write',
  ], change: 'keep it in $buildWorkflowPath at the level named above');

  for (final token in _deployTokens) {
    if (buildWorkflow.contains(token)) {
      findings.add(
        '$buildWorkflowPath: contains `$token` — this workflow publishes a '
        'public package and must never be able to reach a host',
      );
    }
  }

  // CI stays read-only: no write scope, no secret, one job that runs this check.
  if (!ciWorkflow.contains('dart run tool/check_image_build.dart')) {
    findings.add(
      '$ciWorkflowPath: does not run `dart run tool/check_image_build.dart` — '
      'the pins would go unchecked on every PR',
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
    'check_image_build: OK — $dartDockerfilePath, $flutterDockerfilePath, the '
    'workflow and the installer agree on Dart $dartPin / Flutter $flutterPin, '
    'jaspr_cli $jasprCliPin and Tailwind $tailwindPin; tags $dartTag and '
    '$flutterTag.',
  );
}

/// Everything after the first `FROM` line, or null when there is none. The
/// `FROM` line itself differs per flavour by design and is asserted separately.
String? _postFromBody(String dockerfile) {
  final match = RegExp(r'^FROM ', multiLine: true).firstMatch(dockerfile);
  if (match == null) {
    return null;
  }
  final lineEnd = dockerfile.indexOf('\n', match.start);
  return lineEnd == -1 ? '' : dockerfile.substring(lineEnd + 1);
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
