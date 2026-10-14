import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/build_result.dart';

class ApkBuilderService {
  /// Resolves the Android project root (parent of `desktop/`).
  static String resolveProjectRoot() {
    final script = Platform.script.toFilePath();
    // When running from Flutter: .../desktop/.dart_tool/... or .../desktop/
    var dir = Directory(p.dirname(script));
    for (var i = 0; i < 8; i++) {
      final candidate = dir.path;
      if (File(p.join(candidate, 'scripts', 'build_one_apk.sh')).existsSync()) {
        return candidate;
      }
      if (File(p.join(candidate, 'gradlew')).existsSync() &&
          Directory(p.join(candidate, 'app')).existsSync()) {
        return candidate;
      }
      // Also check parent when cwd is desktop/
      final parent = dir.parent;
      if (File(p.join(parent.path, 'scripts', 'build_one_apk.sh'))
          .existsSync()) {
        return parent.path;
      }
      dir = parent;
    }

    final cwd = Directory.current.path;
    if (File(p.join(cwd, 'scripts', 'build_one_apk.sh')).existsSync()) {
      return cwd;
    }
    if (p.basename(cwd) == 'desktop' &&
        File(p.join(cwd, '..', 'scripts', 'build_one_apk.sh')).existsSync()) {
      return p.normalize(p.join(cwd, '..'));
    }

    return p.normalize(p.join(Directory.current.path, '..'));
  }

  Future<BuildResult> build({
    required String appName,
    required String url,
    required String iconPath,
    void Function(String line)? onLog,
  }) async {
    final projectRoot = resolveProjectRoot();
    final script = p.join(projectRoot, 'scripts', 'build_one_apk.sh');

    if (!File(script).existsSync()) {
      return BuildResult(
        appName: appName,
        url: url,
        status: BuildStatus.failed,
        message: 'Build script not found at $script',
        timestamp: DateTime.now(),
      );
    }

    if (!File(iconPath).existsSync()) {
      return BuildResult(
        appName: appName,
        url: url,
        status: BuildStatus.failed,
        message: 'Icon not found: $iconPath',
        timestamp: DateTime.now(),
      );
    }

    onLog?.call('Project: $projectRoot');

    if (Platform.isWindows) {
      return _buildOnWindows(
        projectRoot: projectRoot,
        appName: appName,
        url: url,
        iconPath: iconPath,
        onLog: onLog,
      );
    }

    onLog?.call('Running build_one_apk.sh…');

    final process = await Process.start(
      '/bin/bash',
      [script, appName, url, iconPath],
      workingDirectory: projectRoot,
      environment: {
        ...Platform.environment,
        'JAVA_HOME':
            Platform.environment['JAVA_HOME'] ??
            '/Applications/Android Studio.app/Contents/jbr/Contents/Home',
        'ANDROID_HOME':
            Platform.environment['ANDROID_HOME'] ??
            '${Platform.environment['HOME']}/Library/Android/sdk',
      },
    );

    final buffer = StringBuffer();
    String? apkPath;

    void handleLine(String line) {
      if (line.isEmpty) return;
      buffer.writeln(line);
      onLog?.call(line);
      if (line.startsWith('APK_PATH=')) {
        apkPath = line.substring('APK_PATH='.length).trim();
      } else if (line.startsWith('OK -> ')) {
        final match = RegExp(r'OK -> (.+?)(?:\s+\(|$)').firstMatch(line);
        if (match != null) {
          apkPath = match.group(1);
        }
      }
    }

    final stdoutSub = process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(handleLine);
    final stderrSub = process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(handleLine);

    final code = await process.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();

    if (code == 0) {
      return BuildResult(
        appName: appName,
        url: url,
        status: BuildStatus.success,
        apkPath: apkPath,
        message: apkPath != null ? 'Saved to $apkPath' : 'Build succeeded',
        timestamp: DateTime.now(),
      );
    }

    return BuildResult(
      appName: appName,
      url: url,
      status: BuildStatus.failed,
      message: 'Build failed (exit $code). See log for details.',
      timestamp: DateTime.now(),
    );
  }

  Future<BuildResult> _buildOnWindows({
    required String projectRoot,
    required String appName,
    required String url,
    required String iconPath,
    void Function(String line)? onLog,
  }) async {
    final javaHome = await _resolveJavaHome(onLog);
    if (javaHome == null) {
      return BuildResult(
        appName: appName,
        url: url,
        status: BuildStatus.failed,
        message:
            'JDK 17 or newer was not found. Install a JDK and set JAVA_HOME.',
        timestamp: DateTime.now(),
      );
    }

    final started = DateTime.now();
    final slug = _slugify(appName);
    final appId = 'com.$slug.app';
    final outName = _apkFileName(appName);
    final outApk = p.join(projectRoot, 'dist', '$outName.apk');

    onLog?.call('package: $appId');
    onLog?.call('url:     $url');
    onLog?.call('icon:    $iconPath');

    final sourceBytes = await File(iconPath).readAsBytes();
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      return BuildResult(
        appName: appName,
        url: url,
        status: BuildStatus.failed,
        message: 'Could not read the icon image.',
        timestamp: DateTime.now(),
      );
    }

    final bg = _detectLogoBackground(decoded);
    final splash = _deriveSplashColors(bg);
    onLog?.call(
      'splash:  #${splash.base} (soft=#${splash.soft} deep=#${splash.deep})',
    );

    await _writeProjectFiles(
      projectRoot: projectRoot,
      appName: appName,
      url: url,
      appId: appId,
      splash: splash,
    );
    await _writeIcons(projectRoot, decoded);
    onLog?.call('Wrote name, URL, splash colors, and launcher icons.');
    onLog?.call('Starting Gradle. The first build often takes 1–3 minutes.');

    final javaExe = p.join(javaHome, 'bin', 'java.exe');
    final wrapperJar = p.join(
      projectRoot,
      'gradle',
      'wrapper',
      'gradle-wrapper.jar',
    );
    final process = await Process.start(
      javaExe,
      [
        '-classpath',
        wrapperJar,
        'org.gradle.wrapper.GradleWrapperMain',
        'assembleDebug',
        '--console=plain',
      ],
      workingDirectory: projectRoot,
      environment: {
        ...Platform.environment,
        'JAVA_HOME': javaHome,
        'PATH': '${p.join(javaHome, 'bin')};${Platform.environment['PATH'] ?? ''}',
      },
    );

    final code = await _pipeProcess(process, onLog);
    if (code != 0) {
      return BuildResult(
        appName: appName,
        url: url,
        status: BuildStatus.failed,
        message: 'Build failed (exit $code). See log for details.',
        timestamp: DateTime.now(),
      );
    }

    final debugApk = p.join(
      projectRoot,
      'app',
      'build',
      'outputs',
      'apk',
      'debug',
      'app-debug.apk',
    );
    if (!File(debugApk).existsSync()) {
      return BuildResult(
        appName: appName,
        url: url,
        status: BuildStatus.failed,
        message: 'Gradle finished but app-debug.apk was not found.',
        timestamp: DateTime.now(),
      );
    }

    await Directory(p.join(projectRoot, 'dist')).create(recursive: true);
    await File(debugApk).copy(outApk);
    final seconds = DateTime.now().difference(started).inSeconds;
    final sizeMb = (await File(outApk).length()) / (1024 * 1024);
    onLog?.call(
      'OK -> $outApk (${sizeMb.toStringAsFixed(1)} MB, ${seconds}s)',
    );
    onLog?.call('APK_PATH=$outApk');

    return BuildResult(
      appName: appName,
      url: url,
      status: BuildStatus.success,
      apkPath: outApk,
      message: 'Saved to $outApk',
      timestamp: DateTime.now(),
    );
  }

  Future<int> _pipeProcess(
    Process process,
    void Function(String line)? onLog,
  ) async {
    final done = Completer<void>();
    var remaining = 2;

    void handle(String line) {
      if (line.trim().isEmpty) return;
      onLog?.call(line);
    }

    void finish() {
      remaining -= 1;
      if (remaining == 0 && !done.isCompleted) done.complete();
    }

    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(handle, onDone: finish, onError: (_) => finish());
    process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(handle, onDone: finish, onError: (_) => finish());

    final code = await process.exitCode;
    await done.future;
    return code;
  }

  Future<String?> _resolveJavaHome(void Function(String line)? onLog) async {
    final candidates = <String>[];
    final envHome = Platform.environment['JAVA_HOME'];
    if (envHome != null && envHome.isNotEmpty) candidates.add(envHome);

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null) {
      final jdks = Directory(p.join(userProfile, '.jdks'));
      if (jdks.existsSync()) {
        for (final entity in jdks.listSync().whereType<Directory>()) {
          candidates.add(entity.path);
        }
      }
    }

    String? best;
    var bestMajor = 0;
    for (final home in candidates) {
      final javaExe = p.join(home, 'bin', 'java.exe');
      if (!File(javaExe).existsSync()) continue;
      final major = await _javaMajor(javaExe);
      if (major >= 17 && major > bestMajor) {
        best = home;
        bestMajor = major;
      }
    }

    if (best != null) {
      onLog?.call('Java: $best (major $bestMajor)');
    }
    return best;
  }

  Future<int> _javaMajor(String javaExe) async {
    final result = await Process.run(javaExe, ['-version']);
    final text = '${result.stdout}\n${result.stderr}';
    final match = RegExp(r'version "(\d+)').firstMatch(text);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Future<void> _writeProjectFiles({
    required String projectRoot,
    required String appName,
    required String url,
    required String appId,
    required ({String soft, String base, String deep}) splash,
  }) async {
    final strings = '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">${_xmlEscape(appName)}</string>
    <string name="app_url">${_xmlEscape(url)}</string>
</resources>
''';
    final colors = '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="splash_background">#${splash.base}</color>
    <color name="splash_background_deep">#${splash.deep}</color>
    <color name="splash_background_soft">#${splash.soft}</color>
    <color name="progress_accent">#FFFFFF</color>
</resources>
''';
    await File(
      p.join(projectRoot, 'app', 'src', 'main', 'res', 'values', 'strings.xml'),
    ).writeAsString(strings.trimLeft());
    await File(
      p.join(projectRoot, 'app', 'src', 'main', 'res', 'values', 'colors.xml'),
    ).writeAsString(colors.trimLeft());

    final gradleFile = File(p.join(projectRoot, 'app', 'build.gradle.kts'));
    var gradle = await gradleFile.readAsString();
    gradle = gradle.replaceFirst(
      RegExp('namespace = ".*?"'),
      'namespace = "com.webviewshell.app"',
    );
    gradle = gradle.replaceFirst(
      RegExp('applicationId = ".*?"'),
      'applicationId = "$appId"',
    );
    await gradleFile.writeAsString(gradle);
  }

  Future<void> _writeIcons(String projectRoot, img.Image source) async {
    const sizes = {
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };
    for (final entry in sizes.entries) {
      final resized = img.copyResize(
        source,
        width: entry.value,
        height: entry.value,
        interpolation: img.Interpolation.cubic,
      );
      final file = File(
        p.join(
          projectRoot,
          'app',
          'src',
          'main',
          'res',
          entry.key,
          'ic_launcher.png',
        ),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(img.encodePng(resized));
    }
  }

  ({int r, int g, int b}) _detectLogoBackground(img.Image image) {
    final counts = <int, int>{};
    void consider(int x, int y) {
      if (x < 0 || y < 0 || x >= image.width || y >= image.height) return;
      final pixel = image.getPixel(x, y);
      if (pixel.a.toInt() <= 200) return;
      final key = (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final width = image.width;
    final height = image.height;
    for (var x = 0; x < width; x += 2) {
      for (final y in [0, 1, 2, height - 1, height - 2, height - 3]) {
        consider(x, y);
      }
    }
    for (var y = 0; y < height; y += 2) {
      for (final x in [0, 1, 2, width - 1, width - 2, width - 3]) {
        consider(x, y);
      }
    }

    if (counts.isEmpty) return (r: 25, g: 30, b: 51);
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return (r: (top >> 16) & 0xFF, g: (top >> 8) & 0xFF, b: top & 0xFF);
  }

  ({String soft, String base, String deep}) _deriveSplashColors(
    ({int r, int g, int b}) color,
  ) {
    int mix(int channel, int target, double amount) {
      final value = channel + (target - channel) * amount;
      return value.round().clamp(0, 255);
    }

    String hex(int r, int g, int b) =>
        '${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

    final lum = (0.299 * color.r + 0.587 * color.g + 0.114 * color.b) / 255.0;
    late final ({int r, int g, int b}) soft;
    late final ({int r, int g, int b}) deep;
    if (lum > 0.85) {
      soft = (
        r: mix(color.r, 255, 0.08),
        g: mix(color.g, 255, 0.08),
        b: mix(color.b, 255, 0.08),
      );
      deep = (
        r: mix(color.r, 0, 0.12),
        g: mix(color.g, 0, 0.12),
        b: mix(color.b, 0, 0.12),
      );
    } else if (lum < 0.08) {
      soft = (
        r: mix(color.r, 255, 0.14),
        g: mix(color.g, 255, 0.14),
        b: mix(color.b, 255, 0.14),
      );
      deep = (r: 0, g: 0, b: 0);
    } else {
      soft = (
        r: mix(color.r, 255, 0.18),
        g: mix(color.g, 255, 0.18),
        b: mix(color.b, 255, 0.18),
      );
      deep = (
        r: mix(color.r, 0, 0.22),
        g: mix(color.g, 0, 0.22),
        b: mix(color.b, 0, 0.22),
      );
    }

    return (
      soft: hex(soft.r, soft.g, soft.b),
      base: hex(color.r, color.g, color.b),
      deep: hex(deep.r, deep.g, deep.b),
    );
  }

  String _slugify(String name) {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (slug.isEmpty) return 'app';
    if (RegExp(r'^[0-9]').hasMatch(slug)) return 'app$slug';
    return slug;
  }

  String _apkFileName(String name) {
    final cleaned = name
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
    return cleaned.isEmpty ? 'app' : cleaned;
  }

  String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  List<String> listLogoFiles(String logosDir) {
    final dir = Directory(logosDir);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((name) {
          final lower = name.toLowerCase();
          return lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.webp');
        })
        .toList()
      ..sort();
  }
}
