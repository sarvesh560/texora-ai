import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

enum BadgeType { success, warning, error, neutral, info }

class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeType type;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.type,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    Color border;

    switch (type) {
      case BadgeType.success:
        bg = AppColors.successGreenLight;
        fg = AppColors.successGreen;
        border = const Color(0xFFA7F3D0);
        break;
      case BadgeType.warning:
        bg = AppColors.warningOrangeLight;
        fg = AppColors.warningOrange;
        border = const Color(0xFFFDE68A);
        break;
      case BadgeType.error:
        bg = AppColors.errorRedLight;
        fg = AppColors.errorRed;
        border = const Color(0xFFFECACA);
        break;
      case BadgeType.info:
        bg = AppColors.primaryBlueMuted;
        fg = AppColors.primaryBlue;
        border = const Color(0xFFBFDBFE);
        break;
      case BadgeType.neutral:
        bg = AppColors.surfaceSecondary;
        fg = AppColors.textSecondary;
        border = AppColors.border;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
