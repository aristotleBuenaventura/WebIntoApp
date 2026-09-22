import 'package:flutter/material.dart';

class DeveloperBranding extends StatelessWidget {
  const DeveloperBranding({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      'Developed by Aris',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
        fontSize: 11,
      ),
    );
  }
}
