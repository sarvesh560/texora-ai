import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';
import 'texora_status_badge.dart';

class TexoraAgentCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;
  final String status;
  final bool isActive;
  final String? modelName;
  final String? latency;
  final String? lastExecutionTime;
  final List<String> capabilities;
  final VoidCallback? onTap;

  const TexoraAgentCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
    this.status = 'Active',
    this.isActive = true,
    this.modelName,
    this.latency,
    this.lastExecutionTime,
    this.capabilities = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TexoraSpacing.radiusCard),
      child: Container(
        padding: const EdgeInsets.all(TexoraSpacing.lg),
        decoration: BoxDecoration(
          color: TexoraColors.cardBg,
          borderRadius: BorderRadius.circular(TexoraSpacing.radiusCard),
          border: Border.all(color: TexoraColors.borderDefault, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(15, 23, 42, 0.04),
              offset: Offset(0, 1),
              blurRadius: 3,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Row: Icon, Title, Subtitle, and Active Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Agent Icon Container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: iconColor.withAlpha(40)),
                  ),
                  child: Center(
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                ),
                const SizedBox(width: TexoraSpacing.md),

                // Name and Description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: TexoraColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: TexoraColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: TexoraSpacing.sm),

                // Status Badge
                TexoraStatusBadge(
                  label: status,
                  variant: isActive
                      ? TexoraBadgeVariant.running
                      : TexoraBadgeVariant.attention,
                  showDot: false,
                ),
              ],
            ),

            // Capabilities Tags (if present)
            if (capabilities.isNotEmpty) ...[
              const SizedBox(height: TexoraSpacing.md),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: capabilities.take(3).map((cap) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: TexoraColors.workspaceBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: TexoraColors.borderDefault),
                    ),
                    child: Text(
                      cap.replaceAll('_', ' '),
                      style: const TextStyle(
                        fontSize: 10,
                        color: TexoraColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // Footer / Metadata Row (Provider, Latency, Action hint)
            const SizedBox(height: TexoraSpacing.md),
            const Divider(color: TexoraColors.borderDefault, height: 1),
            const SizedBox(height: TexoraSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    modelName ?? 'Groq / Gemini Hybrid',
                    style: const TextStyle(
                      fontSize: 11,
                      color: TexoraColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (latency != null)
                  Text(
                    latency!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: TexoraColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: TexoraColors.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
