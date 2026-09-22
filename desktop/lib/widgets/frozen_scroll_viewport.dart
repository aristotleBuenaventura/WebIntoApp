import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps [child] laid out at least [minWidth]×[minHeight]. When the parent
/// viewport is smaller on either axis, scroll bars appear instead of
/// reflowing or squeezing the layout.
class FrozenScrollViewport extends StatelessWidget {
  const FrozenScrollViewport({
    super.key,
    required this.minWidth,
    required this.minHeight,
    required this.child,
  });

  final double minWidth;
  final double minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final needsHorizontal = constraints.maxWidth < minWidth;
        final needsVertical = constraints.maxHeight < minHeight;

        if (!needsHorizontal && !needsVertical) {
          return child;
        }

        final width = math.max(constraints.maxWidth, minWidth);
        final height = math.max(constraints.maxHeight, minHeight);

        Widget content = SizedBox(
          width: width,
          height: height,
          child: child,
        );

        if (needsHorizontal) {
          content = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          );
        }

        if (needsVertical) {
          content = SingleChildScrollView(
            child: content,
          );
        }

        return content;
      },
    );
  }
}
