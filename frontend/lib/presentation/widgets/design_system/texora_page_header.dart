import 'package:flutter/material.dart';
import '../../../core/theme/texora_design_system.dart';

/// Reusable Page Header matching reference_13_screens.png
/// White surface (#FFFFFF), 60px height, bottom border (#E2E8F0),
/// Screen title, AI Running status pill, Search, Notification Bell, and Factory Manager profile.
class TexoraPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? statusPill;
  final VoidCallback? onSearchTap;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onProfileTap;
  final int notificationCount;
  final int? pendingApprovalCount;
  final VoidCallback? onApprovalsTap;
  final VoidCallback? onAdminTap;
  final Widget? leading;

  const TexoraPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.statusPill,
    this.onSearchTap,
    this.onNotificationsTap,
    this.onProfileTap,
    this.notificationCount = 3,
    this.pendingApprovalCount,
    this.onApprovalsTap,
    this.onAdminTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 768;
    final isUltraCompact = screenWidth < 480;

    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: isUltraCompact ? 8 : (isCompact ? 12 : 20)),
      decoration: const BoxDecoration(
        color: TexoraColors.headerBg,
        border: Border(
          bottom: BorderSide(color: TexoraColors.headerBorder, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 8),
          ],
          // Title & optional subtitle / status pill
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isUltraCompact ? 13 : (isCompact ? 15 : 20),
                    fontWeight: FontWeight.w700,
                    color: TexoraColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (statusPill != null && !isUltraCompact) ...[
                  const SizedBox(width: 10),
                  statusPill!,
                ],
                if (subtitle != null && !isCompact) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• $subtitle',
                    style: TexoraTypography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pending Approvals Badge (Real-time count)
              if (pendingApprovalCount != null && pendingApprovalCount! > 0) ...[
                InkWell(
                  onTap: onApprovalsTap,
                  borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7), // Amber 100
                      borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
                      border: Border.all(color: const Color(0xFFF59E0B).withAlpha(120), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.gavel_rounded, size: 14, color: Color(0xFFB45309)),
                        const SizedBox(width: 5),
                        Text(
                          '$pendingApprovalCount Pending',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Admin System Diagnostics Button
              if (onAdminTap != null && !isUltraCompact) ...[
                IconButton(
                  onPressed: onAdminTap,
                  icon: const Icon(Icons.admin_panel_settings_outlined, size: 20, color: TexoraColors.textMuted),
                  tooltip: 'System & Backend Diagnostics (Admin)',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),
              ],

              // Search Icon (hidden on ultra-compact)
              if (!isUltraCompact)
                IconButton(
                  onPressed: onSearchTap ?? () {},
                  icon: const Icon(Icons.search_rounded, size: 20, color: TexoraColors.textMuted),
                  tooltip: 'Search factory assets & telemetry',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),

              if (!isUltraCompact) const SizedBox(width: 4),

              // Notification Bell with Badge
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: onNotificationsTap ?? () {},
                    icon: const Icon(Icons.notifications_none_rounded, size: 20, color: TexoraColors.textMuted),
                    tooltip: 'System Alerts',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                  if (notificationCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: TexoraColors.critical,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                      ),
                    ),
                ],
              ),

              if (!isUltraCompact) ...[
                const SizedBox(width: 6),
                Container(width: 1, height: 20, color: TexoraColors.cardBorder),
                const SizedBox(width: 6),
              ],

              // Manager Profile Dropdown
              InkWell(
                onTap: onProfileTap ?? () {},
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Center(
                          child: Icon(Icons.person_rounded, size: 18, color: Colors.white),
                        ),
                      ),
                      if (!isCompact) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'Factory Manager',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: TexoraColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: TexoraColors.textMuted),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
