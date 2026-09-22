enum BuildStatus { idle, running, success, failed }

class BuildResult {
  const BuildResult({
    required this.appName,
    required this.url,
    required this.status,
    this.apkPath,
    this.message,
    this.timestamp,
  });

  final String appName;
  final String url;
  final BuildStatus status;
  final String? apkPath;
  final String? message;
  final DateTime? timestamp;
}
