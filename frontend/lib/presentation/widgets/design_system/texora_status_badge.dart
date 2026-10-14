import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

enum TexoraBadgeVariant {
  running,
  active,
  attention,
  critical,
  inProgress,
  open,
  completed,
  neutral,
}

/// Reusable status capsule badge matching reference_13_screens.png
class TexoraStatusBadge extends StatelessWidget {
  final String label;
  final TexoraBadgeVariant variant;
  final bool showDot;
  final double? fontSize;

  const TexoraStatusBadge({
    super.key,
    required this.label,
    this.variant = TexoraBadgeVariant.neutral,
    this.showDot = false,
    this.fontSize,
  });

  factory TexoraStatusBadge.fromStatus(String status, {bool showDot = false}) {
    final s = status.toUpperCase().trim();
    if (s == 'OPERATIONAL' || s == 'RUNNING' || s == 'ACTIVE' || s == 'PASSED' || s == 'IN STOCK' || s == 'SUCCESS') {
      return TexoraStatusBadge(label: status, variant: TexoraBadgeVariant.running, showDot: showDot);
    } else if (s == 'ATTENTION' || s == 'WARNING' || s == 'MEDIUM' || s == 'PENDING' || s == 'BOTTLENECK') {
      return TexoraStatusBadge(label: status, variant: TexoraBadgeVariant.attention, showDot: showDot);
    } else if (s == 'CRITICAL' || s == 'HIGH' || s == 'DELAYED' || s == 'LOW STOCK' || s == 'FAILED' || s == 'OFF-SPEC') {
      return TexoraStatusBadge(label: status, variant: TexoraBadgeVariant.critical, showDot: showDot);
    } else if (s == 'IN PROGRESS' || s == 'ASSIGNED' || s == 'REPAIR_IN_PROGRESS') {
      return TexoraStatusBadge(label: status, variant: TexoraBadgeVariant.inProgress, showDot: showDot);
    } else if (s == 'OPEN' || s == 'STAGED' || s == 'CREATED') {
      return TexoraStatusBadge(label: status, variant: TexoraBadgeVariant.open, showDot: showDot);
    } else if (s == 'COMPLETED' || s == 'VERIFIED' || s == 'RESOLVED' || s == 'LOW') {
      return TexoraStatusBadge(label: status, variant: TexoraBadgeVariant.completed, showDot: showDot);
    }
    return TexoraStatusBadge(label: status, variant: TexoraBadgeVariant.neutral, showDot: showDot);
  }

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color text;
    Color border;

    switch (variant) {
      case TexoraBadgeVariant.running:
      case TexoraBadgeVariant.active:
        bg = TexoraColors.successBg;
        text = TexoraColors.successText;
        border = TexoraColors.successBorder;
        break;
      case TexoraBadgeVariant.attention:
        bg = TexoraColors.warningBg;
        text = TexoraColors.warningText;
        border = TexoraColors.warningBorder;
        break;
      case TexoraBadgeVariant.critical:
        bg = TexoraColors.criticalBg;
        text = TexoraColors.criticalText;
        border = TexoraColors.criticalBorder;
        break;
      case TexoraBadgeVariant.inProgress:
        bg = TexoraColors.infoBg;
        text = TexoraColors.infoText;
        border = TexoraColors.infoBorder;
        break;
      case TexoraBadgeVariant.open:
        bg = Colors.white;
        text = TexoraColors.primaryBlue;
        border = TexoraColors.primaryBlue.withAlpha(120);
        break;
      case TexoraBadgeVariant.completed:
        bg = const Color(0xFFF0FDF4);
        text = const Color(0xFF15803D);
        border = const Color(0xFFBBF7D0);
        break;
      case TexoraBadgeVariant.neutral:
        bg = TexoraColors.neutralBg;
        text = TexoraColors.neutralText;
        border = TexoraColors.cardBorder;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: text,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize ?? 11,
                fontWeight: FontWeight.w600,
                color: text,
                letterSpacing: 0.1,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
