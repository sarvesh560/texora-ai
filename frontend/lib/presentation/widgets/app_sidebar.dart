import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/texora_design_system.dart';

class AppSidebar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onDestinationSelected;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onAdminSelected;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onAdminSelected,
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
      width: isCollapsed ? 72 : 240,
      decoration: const BoxDecoration(
        color: TexoraColors.sidebarBg,
        border: Border(
          right: BorderSide(color: TexoraColors.sidebarBorder, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branding & Header
          Container(
            height: 60,
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 12 : 16,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: TexoraColors.sidebarBorder, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment:
                  isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Stylized Geometric Cyan/Blue Logo
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF06B6D4), Color(0xFF2563EB)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: TexoraColors.primaryBlue.withAlpha(90),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.auto_awesome_mosaic_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      if (!isCollapsed) ...[
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                AppConfig.appName,
                                style: TextStyle(
                                  color: TexoraColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Autonomous Factory Operations',
                                style: TextStyle(
                                  color: TexoraColors.sidebarTextInactive,
                                  fontSize: 9.5,
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
                    icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFF64748B), size: 18),
                    tooltip: 'Collapse sidebar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),

          if (isCollapsed && widget.onToggleCollapse != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: IconButton(
                  onPressed: widget.onToggleCollapse,
                  icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 18),
                  tooltip: 'Expand sidebar',
                ),
              ),
            ),

          // Navigation Items (Scrollable)
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                vertical: 8,
                horizontal: isCollapsed ? 8 : 10,
              ),
              children: [
                // ============================================
                // PRIMARY OPERATIONAL WORKSPACES (11 Destinations)
                // ============================================
                _buildNavItem(
                  index: 0,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.hub_outlined,
                  activeIcon: Icons.hub_rounded,
                  label: 'AI Agents',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.precision_manufacturing_outlined,
                  activeIcon: Icons.precision_manufacturing_rounded,
                  label: 'Machine Monitoring',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.insights_outlined,
                  activeIcon: Icons.insights_rounded,
                  label: 'Incident Intelligence',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 4,
                  icon: Icons.factory_outlined,
                  activeIcon: Icons.factory_rounded,
                  label: 'Production',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 5,
                  icon: Icons.build_outlined,
                  activeIcon: Icons.build_rounded,
                  label: 'Maintenance',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 6,
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2_rounded,
                  label: 'Inventory',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 7,
                  icon: Icons.verified_outlined,
                  activeIcon: Icons.verified_rounded,
                  label: 'Quality',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 8,
                  icon: Icons.bolt_outlined,
                  activeIcon: Icons.bolt_rounded,
                  label: 'Energy',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 9,
                  icon: Icons.insert_chart_outlined,
                  activeIcon: Icons.insert_chart_rounded,
                  label: 'Reports & Analytics',
                  isCollapsed: isCollapsed,
                ),
                _buildNavItem(
                  index: 10,
                  icon: Icons.smart_toy_outlined,
                  activeIcon: Icons.smart_toy_rounded,
                  label: 'AI Copilot',
                  isCollapsed: isCollapsed,
                ),
              ],
            ),
          ),

          // Sidebar Footer: Live Fleet Indicator & Admin Diagnostics
          Container(
            padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 10 : 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: TexoraColors.sidebarBorder, width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment:
                      isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: TexoraColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isCollapsed) ...[
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Operational Fleet Online',
                          style: TextStyle(
                            color: TexoraColors.sidebarTextInactive,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                if (widget.onAdminSelected != null) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: widget.onAdminSelected,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisAlignment:
                            isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                        children: [
                          const Icon(Icons.admin_panel_settings_outlined, size: 14, color: Color(0xFF64748B)),
                          if (!isCollapsed) ...[
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Diagnostics (Admin)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
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

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isCollapsed,
  }) {
    final isActive = widget.selectedIndex == index;

    final item = InkWell(
      onTap: () => widget.onDestinationSelected(index),
      borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
      hoverColor: TexoraColors.sidebarHover,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: isCollapsed ? 12 : 12,
          vertical: 9,
        ),
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        decoration: BoxDecoration(
          color: isActive ? TexoraColors.sidebarActivePill : Colors.transparent,
          borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
        ),
        child: Row(
          mainAxisAlignment:
              isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? TexoraColors.sidebarTextActive : TexoraColors.sidebarTextInactive,
              size: 19,
            ),
            if (!isCollapsed) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? TexoraColors.sidebarTextActive : TexoraColors.textSecondary,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
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
