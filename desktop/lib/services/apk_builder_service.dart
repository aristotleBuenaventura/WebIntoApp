import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
