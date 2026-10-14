import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../constants/app_window_sizes.dart';
import '../models/build_result.dart';
import '../providers/app_provider.dart';
import '../widgets/developer_branding.dart';
import '../widgets/frozen_scroll_viewport.dart';

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _logScroll = ScrollController();
  String? _selectedLogo;
  String? _customIconPath;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppWindowSizes.applyMainMinimum();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  String? get _resolvedIconPath {
    if (_customIconPath != null) return _customIconPath;
    final provider = context.read<AppProvider>();
    if (_selectedLogo == null) return null;
    return p.join(provider.logosDir, _selectedLogo!);
  }

  Future<void> _pickCustomIcon() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() {
      _customIconPath = path;
      _selectedLogo = null;
    });
  }

  Future<void> _pickLogosFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select logos folder',
    );
    if (path == null || !mounted) return;
    context.read<AppProvider>().setLogosDir(path);
    setState(() {
      _customIconPath = null;
      _selectedLogo = null;
    });
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;

    final iconPath = _resolvedIconPath;
    if (iconPath == null || !File(iconPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an app icon first.')),
      );
      return;
    }

    final provider = context.read<AppProvider>();
    final result = await provider.generateApk(
      appName: _nameController.text.trim(),
      url: _urlController.text.trim(),
      iconPath: iconPath,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.status == BuildStatus.success
              ? (result.message ?? 'APK ready')
              : (result.message ?? 'Build failed'),
        ),
        backgroundColor: result.status == BuildStatus.success
            ? Colors.green.shade700
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final theme = Theme.of(context);
    if (provider.logLines.length != _lastLogCount) {
      _lastLogCount = provider.logLines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_logScroll.hasClients) return;
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Into App'),
        actions: [
          IconButton(
            tooltip: provider.themeMode == ThemeMode.dark
                ? 'Light theme'
                : 'Dark theme',
            onPressed: () {
              provider.setThemeMode(
                provider.themeMode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              );
            },
            icon: Icon(
              provider.themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FrozenScrollViewport(
            minWidth: 900,
            minHeight: 560,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final formPanel = Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Enter app name, target URL, and icon — then '
                                  'generate a debug APK into the project dist/ folder.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'App name',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  hintText: 'Banglabet Affiliates',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.smartphone),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'App name is required.';
                                  }
                                  return null;
                                },
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'APK file: ${_previewApkName()}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Website URL',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _urlController,
                                decoration: const InputDecoration(
                                  hintText: 'https://example.com/affsignup',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.link),
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (text.isEmpty) {
                                    return 'URL is required.';
                                  }
                                  final uri = Uri.tryParse(text);
                                  if (uri == null ||
                                      !(uri.isScheme('http') ||
                                          uri.isScheme('https'))) {
                                    return 'Enter a valid http(s) URL.';
                                  }
                                  return null;
                                },
                              ),
                              const Divider(height: 32),
                              Row(
                                children: [
                                  Text(
                                    'App icon',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: provider.isBuilding
                                        ? null
                                        : _pickLogosFolder,
                                    icon: const Icon(
                                      Icons.folder_open,
                                      size: 18,
                                    ),
                                    label: const Text('Folder'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                provider.logosDir,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      // ignore: deprecated_member_use
                                      value: _selectedLogo != null &&
                                              provider.logoFiles
                                                  .contains(_selectedLogo)
                                          ? _selectedLogo
                                          : null,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'Select from logos folder',
                                      ),
                                      items: provider.logoFiles
                                          .map(
                                            (file) => DropdownMenuItem(
                                              value: file,
                                              child: Text(
                                                file,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: provider.isBuilding
                                          ? null
                                          : (value) {
                                              setState(() {
                                                _selectedLogo = value;
                                                _customIconPath = null;
                                              });
                                            },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: provider.isBuilding
                                        ? null
                                        : _pickCustomIcon,
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Browse'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _IconPreview(path: _resolvedIconPath),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: provider.isBuilding ? null : _generate,
                          icon: provider.isBuilding
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.android),
                          label: Text(
                            provider.isBuilding
                                ? 'Building APK…'
                                : 'Generate APK',
                          ),
                        ),
                        if (provider.isBuilding) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                        ],
                      ],
                    ),
                  ),
                );

                final resultsPanel = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                      child: Row(
                        children: [
                          Text('Build log', style: theme.textTheme.titleMedium),
                          const Spacer(),
                          if (provider.logLines.isNotEmpty)
                            TextButton(
                              onPressed: provider.isBuilding
                                  ? null
                                  : provider.clearLog,
                              child: const Text('Clear log'),
                            ),
                          if (provider.results.isNotEmpty)
                            TextButton(
                              onPressed: provider.isBuilding
                                  ? null
                                  : provider.clearResults,
                              child: const Text('Clear results'),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: provider.logLines.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Build output will appear here.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              margin: const EdgeInsets.symmetric(horizontal: 24),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: SelectionArea(
                                child: ListView.builder(
                                  controller: _logScroll,
                                  itemCount: provider.logLines.length,
                                  itemBuilder: (context, index) {
                                    return Text(
                                      provider.logLines[index],
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        fontFamily: 'Menlo',
                                        fontFamilyFallback: const [
                                          'Consolas',
                                          'monospace',
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: Text(
                        'Recent builds',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: provider.results.isEmpty
                          ? Center(
                              child: Text(
                                'No builds yet.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              itemCount: provider.results.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                return _ResultTile(
                                  result: provider.results[index],
                                );
                              },
                            ),
                    ),
                  ],
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: formPanel),
                    VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Expanded(flex: 3, child: resultsPanel),
                  ],
                );
              },
            ),
          ),
          const Positioned(
            right: 16,
            bottom: 8,
            child: DeveloperBranding(),
          ),
        ],
      ),
    );
  }

  String _previewApkName() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return 'App_Name.apk';
    final slug = name.replaceAll(RegExp(r'[^A-Za-z0-9_ -]'), '');
    return '${slug.replaceAll(' ', '_')}.apk';
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 120,
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: path == null || !File(path!).existsSync()
          ? Center(
              child: Text(
                'Icon preview',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Row(
              children: [
                const SizedBox(width: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(path!),
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    p.basename(path!),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final BuildResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (result.status) {
      BuildStatus.idle => (
          Icons.hourglass_empty,
          theme.colorScheme.outline,
          'Idle',
        ),
      BuildStatus.running => (
          Icons.hourglass_top,
          theme.colorScheme.primary,
          'Running',
        ),
      BuildStatus.success => (
          Icons.check_circle,
          Colors.green,
          'Success',
        ),
      BuildStatus.failed => (
          Icons.error_outline,
          theme.colorScheme.error,
          'Failed',
        ),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.appName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    result.url,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (result.message != null) ...[
                    const SizedBox(height: 4),
                    Text(result.message!, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
