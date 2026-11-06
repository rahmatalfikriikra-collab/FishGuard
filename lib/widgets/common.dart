import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// Card with the prototype's rounded/shadowed look.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.only(bottom: 15),
    this.accent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Widget content = Container(
      width: double.infinity,
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent ?? c.border),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: c.primary.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: content,
    );
  }
}

/// Full-width button matching `.btn` in the prototype.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = ButtonVariant.primary,
    this.expand = true,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonVariant variant;
  final bool expand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool disabled = onPressed == null;

    late final Color bg;
    late final Color fg;
    switch (variant) {
      case ButtonVariant.primary:
        bg = c.primary;
        fg = Colors.white;
      case ButtonVariant.secondary:
        bg = c.border;
        fg = c.textMain;
      case ButtonVariant.warning:
        bg = c.warning;
        fg = Colors.white;
      case ButtonVariant.success:
        bg = c.accent;
        fg = Colors.white;
      case ButtonVariant.danger:
        bg = c.danger;
        fg = Colors.white;
      case ButtonVariant.ghost:
        bg = Colors.transparent;
        fg = c.primary;
    }

    final Widget child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 20, color: disabled ? fg.withValues(alpha: 0.6) : fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: dense ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: disabled ? fg.withValues(alpha: 0.6) : fg,
            ),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 14 : 20,
              vertical: dense ? 10 : 15,
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

enum ButtonVariant { primary, secondary, warning, success, danger, ghost }

/// Section heading in the prototype's uppercase muted style.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: c.textMuted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Big status banner: colour + icon + text, never colour alone (PRD HOME-1).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.large = false});

  final SeaStatus status;
  final bool large;

  Color _color(AppColors c) => switch (status) {
        SeaStatus.layak => c.accent,
        SeaStatus.waspada => c.warning,
        SeaStatus.tidakLayak => c.danger,
      };

  IconData get _icon => switch (status) {
        SeaStatus.layak => Icons.check_circle,
        SeaStatus.waspada => Icons.warning_amber_rounded,
        SeaStatus.tidakLayak => Icons.dangerous,
      };

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color color = _color(c);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 10,
        vertical: large ? 12 : 5,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(large ? 12 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_icon, size: large ? 24 : 14, color: Colors.white),
          SizedBox(width: large ? 8 : 4),
          Flexible(
            child: Text(
              large ? status.label : status.shortLabel,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: large ? 17 : 11,
                letterSpacing: large ? 0.3 : 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small label chip.
class Chip2 extends StatelessWidget {
  const Chip2({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tint = color ?? c.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? tint : tint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tint.withValues(alpha: filled ? 1 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: filled ? Colors.white : tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : tint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Key/value row used in the fuel breakdown and trip summary.
class BreakdownRow extends StatelessWidget {
  const BreakdownRow({
    super.key,
    required this.label,
    required this.value,
    this.total = false,
  });

  final String label;
  final String value;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: total ? 10 : 0, bottom: 6),
      decoration: total
          ? BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: total ? 16 : 15,
              color: total ? c.primary : c.textMuted,
              fontWeight: total ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: total ? 17 : 15,
              color: total ? c.primary : c.textMain,
              fontWeight: total ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline notice box (disclaimer, "butuh internet, lakukan di darat", ...).
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.color,
    this.action,
  });

  final String text;
  final IconData icon;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tint = color ?? c.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: c.textMain,
                  ),
                ),
              ),
            ],
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: 10),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Bottom-sheet container with a drag handle, used for point details etc.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: c.textMain,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          subtitle!,
                          style: TextStyle(fontSize: 14, color: c.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          Flexible(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}

String duaDigit(int v) => v.toString().padLeft(2, '0');
