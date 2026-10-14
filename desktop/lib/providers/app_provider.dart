import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/build_result.dart';
import '../services/apk_builder_service.dart';

class AppProvider extends ChangeNotifier {
  AppProvider({ApkBuilderService? builder})
      : _builder = builder ?? ApkBuilderService() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    logosDir = p.join(home, 'Downloads', 'BDT_LOGOS');
    projectRoot = ApkBuilderService.resolveProjectRoot();
    refreshLogos();
  }

  final ApkBuilderService _builder;

  ThemeMode themeMode = ThemeMode.system;
  late String logosDir;
  late String projectRoot;
  List<String> logoFiles = const [];
  bool isBuilding = false;
  final List<String> logLines = [];
  final List<BuildResult> results = [];
  String? errorMessage;

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
  }

  void setLogosDir(String path) {
    logosDir = path;
    refreshLogos();
  }

  void refreshLogos() {
    logoFiles = _builder.listLogoFiles(logosDir);
    notifyListeners();
  }

  void clearLog() {
    logLines.clear();
    notifyListeners();
  }

  void clearResults() {
    results.clear();
    notifyListeners();
  }

  void _appendLog(String line) {
    logLines.add(line);
    notifyListeners();
  }

  Future<BuildResult> generateApk({
    required String appName,
    required String url,
    required String iconPath,
  }) async {
    isBuilding = true;
    errorMessage = null;
    logLines.clear();
    notifyListeners();

    late final BuildResult result;
    try {
      result = await _builder.build(
        appName: appName,
        url: url,
        iconPath: iconPath,
        onLog: _appendLog,
      );
    } catch (error) {
      _appendLog('ERROR: $error');
      result = BuildResult(
        appName: appName,
        url: url,
        status: BuildStatus.failed,
        message: error.toString(),
        timestamp: DateTime.now(),
      );
    }

    results.insert(0, result);
    isBuilding = false;
    if (result.status == BuildStatus.failed) {
      errorMessage = result.message;
    }
    notifyListeners();
    return result;
  }
}
