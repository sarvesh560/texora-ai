import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/config/app_config.dart';

class AppSidebar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  @override
  Widget build(BuildContext context) {
    final isCollapsed = widget.isCollapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isCollapsed ? 72 : 260,
      color: const Color(0xFF0A0F1D), // Dark Navy Background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding & Header
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 12 : 16,
              vertical: 18,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF1E293B), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment:
                  isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue.withAlpha(80),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.precision_manufacturing_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      if (!isCollapsed) ...[
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppConfig.appName,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Commercial Industrial AI',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isCollapsed && widget.onToggleCollapse != null)
                  IconButton(
                    onPressed: widget.onToggleCollapse,
                    icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF64748B), size: 20),
                    tooltip: 'Collapse sidebar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),

          // Sub-header Badge (when expanded)
          if (!isCollapsed)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_rounded, color: Color(0xFF38BDF8), size: 12),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Operational Node: Coimbatore-01',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          if (isCollapsed && widget.onToggleCollapse != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: IconButton(
                  onPressed: widget.onToggleCollapse,
                  icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 20),
                  tooltip: 'Expand sidebar',
                ),
              ),
            ),

          // Navigation Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                vertical: 8,
                horizontal: isCollapsed ? 8 : 10,
              ),
              children: [
                // OVERVIEW
                _buildSectionTitle('OVERVIEW', isCollapsed),
                _buildNavItem(
                  index: 0,
                  icon: Icons.dashboard_customize_rounded,
                  label: 'Executive Command',
                  isCollapsed: isCollapsed,
                  badge: 'LIVE',
                  badgeColor: const Color(0xFF38BDF8),
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.grid_view_rounded,
                  label: 'Factory Digital Twin',
                  isCollapsed: isCollapsed,
                  badge: 'TWIN',
                  badgeColor: const Color(0xFF38BDF8),
                ),

                const SizedBox(height: 10),

                // OPERATIONS
                _buildSectionTitle('OPERATIONS', isCollapsed),
                _buildNavItem(
                  index: 10,
                  icon: Icons.hub_rounded,
                  label: 'AI Agent Operations',
                  isCollapsed: isCollapsed,
                  badge: 'FLEET',
                  badgeColor: const Color(0xFF38BDF8),
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.insights_rounded,
                  label: 'Incident Intelligence',
                  isCollapsed: isCollapsed,
                  badge: 'OPS',
                  badgeColor: AppColors.errorRed,
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.psychology_rounded,
                  label: 'Machine Health & AI',
                  isCollapsed: isCollapsed,
                  badge: 'AI',
                  badgeColor: const Color(0xFFA855F7),
                ),
                _buildNavItem(
                  index: 4,
                  icon: Icons.build_circle_rounded,
                  label: 'Factory Recovery',
                  isCollapsed: isCollapsed,
                  badge: 'ORCH',
                  badgeColor: const Color(0xFF0D9488),
                ),
                _buildNavItem(
                  index: 11,
                  icon: Icons.handyman_rounded,
                  label: 'Maintenance Execution',
                  isCollapsed: isCollapsed,
                  badge: 'EXEC',
                  badgeColor: const Color(0xFFEA580C),
                ),

                const SizedBox(height: 10),

                // GOVERNANCE
                _buildSectionTitle('AI & GOVERNANCE', isCollapsed),
                _buildNavItem(
                  index: 5,
                  icon: Icons.gavel_rounded,
                  label: 'Approval Center',
                  isCollapsed: isCollapsed,
                  badge: 'GATE',
                  badgeColor: const Color(0xFFF59E0B),
                ),
                _buildNavItem(
                  index: 6,
                  icon: Icons.shield_outlined,
                  label: 'Audit Trail',
                  isCollapsed: isCollapsed,
                  badge: 'AUDIT',
                  badgeColor: const Color(0xFF10B981),
                ),

                const SizedBox(height: 10),

                // SANDBOX & SIMULATION (ISOLATED)
                _buildSectionTitle('SANDBOX / SIMULATION', isCollapsed),
                _buildNavItem(
                  index: 7,
                  icon: Icons.tune_rounded,
                  label: 'Telemetry Simulator',
                  isCollapsed: isCollapsed,
                  badge: 'TEST',
                  badgeColor: const Color(0xFF64748B),
                ),
                _buildNavItem(
                  index: 8,
                  icon: Icons.science_rounded,
                  label: 'What-If Simulation',
                  isCollapsed: isCollapsed,
                  badge: 'SANDBOX',
                  badgeColor: const Color(0xFF64748B),
                ),
                _buildNavItem(
                  index: 9,
                  icon: Icons.hub_rounded,
                  label: 'System Diagnostics',
                  isCollapsed: isCollapsed,
                  badge: 'STATUS',
                  badgeColor: AppColors.successGreen,
                ),
              ],
            ),
          ),

          // Footer
          Container(
            padding: EdgeInsets.all(isCollapsed ? 12 : 14),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFF1E293B), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment:
                  isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Operational Fleet Online',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isCollapsed) {
    if (isCollapsed) {
      return const Divider(color: Color(0xFF1E293B), height: 16);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 6, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isCollapsed,
    String? badge,
    Color? badgeColor,
  }) {
    final isActive = widget.selectedIndex == index;

    final item = InkWell(
      onTap: () => widget.onDestinationSelected(index),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: isCollapsed ? 10 : 10,
          vertical: 9,
        ),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isActive
              ? Border.all(color: AppColors.primaryBlue.withAlpha(140), width: 1.2)
              : null,
        ),
        child: Row(
          mainAxisAlignment:
              isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isActive ? AppColors.primaryBlueLight : const Color(0xFF94A3B8),
              size: 18,
            ),
            if (!isCollapsed) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFFCBD5E1),
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? AppColors.primaryBlue).withAlpha(35),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: (badgeColor ?? AppColors.primaryBlue).withAlpha(80),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: badgeColor ?? AppColors.primaryBlueLight,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );

    if (isCollapsed) {
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 200),
        child: item,
      );
    }

    return item;
  }
}
