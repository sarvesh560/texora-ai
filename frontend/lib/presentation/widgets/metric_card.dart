import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;
  final Color? accentColor;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? titleColor;
  final Color? valueColor;
  final Color? subtitleColor;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.trailing,
    this.accentColor,
    this.backgroundColor,
    this.borderColor,
    this.titleColor,
    this.valueColor,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accentColor ?? AppColors.primaryBlue;
    final effectiveBg = backgroundColor ?? AppColors.surface;
    final effectiveBorder = borderColor ?? AppColors.border;
    final effectiveTitle = titleColor ?? AppColors.textSecondary;
    final effectiveValue = valueColor ?? AppColors.textPrimary;
    final effectiveSub = subtitleColor ?? AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: effectiveBorder, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x05000000),
            offset: Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: effectiveAccent.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: effectiveAccent, size: 18),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: effectiveTitle,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: effectiveValue,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                color: effectiveSub,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

