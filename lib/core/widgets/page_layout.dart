import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A consistent page shell used by every feature screen.
///
/// Provides:
/// - A top section with title, optional subtitle and actions
/// - A scrollable body with consistent padding
/// - SafeArea handling for notches and system UI
///
/// Use this instead of raw Scaffold so every page has identical structure.
class ExaltedPage extends StatelessWidget {
  const ExaltedPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.child,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          title: title,
          subtitle: subtitle,
          actions: actions,
          leading: leading,
        ),
        const SizedBox(height: AppSpacing.md),
        if (child != null) Expanded(child: child!),
      ],
    );

    return SafeArea(
      child: scrollable
          ? Column(
              children: [
                SizedBox(
                  height: 120,
                  child: body,
                ),
                Expanded(child: const SizedBox.shrink()),
              ],
            )
          : body,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    this.subtitle,
    this.actions,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[
      if (leading != null) ...[
        leading!,
        const SizedBox(width: AppSpacing.md),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      if (actions != null && actions!.isNotEmpty) ...[
        const SizedBox(width: AppSpacing.md),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: actions!,
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(children: children),
    );
  }
}

/// A consistent content area for pages that show a list or table.
class ExaltedPageBody extends StatelessWidget {
  const ExaltedPageBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: child,
    );
  }
}
