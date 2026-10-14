import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

/// Reusable 4-column KPI Card matching reference_13_screens.png (Screens 1, 7, 10, 11)
class TexoraKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final bool isPositive;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;

  const TexoraKpiCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.isPositive = true,
    this.icon,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusLg),
        border: Border.all(color: TexoraColors.cardBorder, width: 1),
        boxShadow: TexoraSpacing.cardShadow,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TexoraTypography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (icon != null)
                  Icon(
                    icon,
                    size: 16,
                    color: iconColor ?? TexoraColors.textMuted,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TexoraTypography.kpiValue,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 12,
                    color: isPositive ? TexoraColors.successText : TexoraColors.criticalText,
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isPositive ? TexoraColors.successText : TexoraColors.criticalText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
