import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/services/api_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/design_system/design_system.dart';
import 'executive_command_center_screen.dart';
import 'incident_intelligence_screen.dart';
import 'machine_health_agent_screen.dart';
import 'approval_center_screen.dart';
import 'backend_status_screen.dart';
import 'ai_agent_operations_screen.dart';
import 'maintenance_execution_screen.dart';
import 'factory_copilot_screen.dart';
import 'production_intelligence_screen.dart';
import 'inventory_management_screen.dart';
import 'quality_monitoring_screen.dart';
import 'energy_management_screen.dart';
import 'reports_analytics_screen.dart';
import '../widgets/floating_copilot_assistant.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  final ApiService _apiService = ApiService();
  int _selectedNavIndex = 0;
  bool _isSidebarCollapsed = false;
  bool _isCopilotFullScreen = false;
  bool _isApprovalCenterOpen = false;
  bool _isDiagnosticsOpen = false;
  int _pendingApprovalCount = 0;
  Timer? _approvalsPoller;

  @override
  void initState() {
    super.initState();
    _fetchPendingCount();
    _approvalsPoller = Timer.periodic(const Duration(seconds: 25), (_) => _fetchPendingCount());
  }

  @override
  void dispose() {
    _approvalsPoller?.cancel();
    super.dispose();
  }

  Future<void> _fetchPendingCount() async {
    try {
      final list = await _apiService.fetchApprovalRequestsList(status: 'PENDING');
      if (mounted) {
        setState(() {
          _pendingApprovalCount = list.length;
        });
      }
    } catch (_) {
      // Non-blocking background telemetry fetch
    }
  }

  /// Strictly manual navigation handler.
  /// Navigation occurs ONLY through explicit user interactions (sidebar selection,
  /// user-clicked buttons, or tab clicks).
  /// Automatic screen switching, background route redirects, and presentation tours
  /// are permanently disabled.
  void _navigateToTab(int index, {String? targetMachine, bool isExplicitUserAction = true}) {
    if (!isExplicitUserAction) return; // Prevent any automatic programmatic navigation
    setState(() {
      _selectedNavIndex = index;
      _isCopilotFullScreen = false;
      _isApprovalCenterOpen = false;
      _isDiagnosticsOpen = false;
    });
  }

  String _getPageTitle(int index) {
    switch (index) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'AI Agents';
      case 2:
        return 'Machine Monitoring';
      case 3:
        return 'Incident Intelligence';
      case 4:
        return 'Production';
      case 5:
        return 'Maintenance';
      case 6:
        return 'Inventory';
      case 7:
        return 'Quality';
      case 8:
        return 'Energy';
      case 9:
        return 'Reports & Analytics';
      case 10:
        return 'AI Copilot';
      default:
        return 'Dashboard';
    }
  }

  Widget? _getStatusPill(int index) {
    if (index == 0 || index == 1 || index == 2) {
      String label = 'AI Running';
      if (index == 1) label = '6 Agents Active';
      if (index == 2) label = 'Live Telemetry';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: TexoraColors.successBg,
          borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
          border: Border.all(color: TexoraColors.successBorder, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, color: TexoraColors.successText, size: 6.5),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: TexoraColors.successText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Dedicated Fullscreen Copilot Mode
    if (_isCopilotFullScreen) {
      return FactoryCopilotScreen(
        onExit: () => setState(() => _isCopilotFullScreen = false),
        onNavigate: (index, {targetMachine}) =>
            _navigateToTab(index, targetMachine: targetMachine),
      );
    }

    // Dedicated Approval Center Overlay
    if (_isApprovalCenterOpen) {
      return Scaffold(
        backgroundColor: TexoraColors.workspaceBg,
        body: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: TexoraColors.headerBg,
                border: Border(bottom: BorderSide(color: TexoraColors.headerBorder, width: 1)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _isApprovalCenterOpen = false);
                      _fetchPendingCount();
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 18, color: TexoraColors.primaryBlue),
                    label: const Text(
                      'Back to Factory Workspaces',
                      style: TextStyle(
                        color: TexoraColors.primaryBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
                      border: Border.all(color: const Color(0xFFF59E0B).withAlpha(120)),
                    ),
                    child: Text(
                      '$_pendingApprovalCount Pending Approvals',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ApprovalCenterScreen(
                onNavigate: (index, {targetMachine}) {
                  setState(() => _isApprovalCenterOpen = false);
                  _navigateToTab(index, targetMachine: targetMachine);
                },
                onClose: () {
                  setState(() => _isApprovalCenterOpen = false);
                  _fetchPendingCount();
                },
              ),
            ),
          ],
        ),
      );
    }

    // Dedicated System Diagnostics Overlay (Administrative Access)
    if (_isDiagnosticsOpen) {
      return Scaffold(
        backgroundColor: TexoraColors.workspaceBg,
        body: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: TexoraColors.headerBg,
                border: Border(bottom: BorderSide(color: TexoraColors.headerBorder, width: 1)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _isDiagnosticsOpen = false),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18, color: TexoraColors.primaryBlue),
                    label: const Text(
                      'Back to Factory Workspaces',
                      style: TextStyle(
                        color: TexoraColors.primaryBlue,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.admin_panel_settings_outlined, size: 16, color: TexoraColors.textMuted),
                      SizedBox(width: 6),
                      Text(
                        'Administrative Diagnostics & Infrastructure',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: TexoraColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: BackendStatusScreen(
                onClose: () => setState(() => _isDiagnosticsOpen = false),
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final autoCollapse = screenWidth < 1024;
    final effectiveCollapsed = _isSidebarCollapsed || autoCollapse;

    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: Stack(
        children: [
          Row(
            children: [
              // Enterprise 11-Destination Navigation Sidebar
              AppSidebar(
                selectedIndex: _selectedNavIndex,
                isCollapsed: effectiveCollapsed,
                onToggleCollapse: () {
                  setState(() {
                    _isSidebarCollapsed = !_isSidebarCollapsed;
                  });
                },
                onDestinationSelected: (index) {
                  setState(() {
                    _selectedNavIndex = index;
                    _isApprovalCenterOpen = false;
                    _isDiagnosticsOpen = false;
                  });
                },
                onAdminSelected: () {
                  setState(() {
                    _isDiagnosticsOpen = true;
                    _isApprovalCenterOpen = false;
                  });
                },
              ),

              // Main Application Header and Workspace Area
              Expanded(
                child: Column(
                  children: [
                    // Top Bar / Page Header matching reference_13_screens.png
                    TexoraPageHeader(
                      title: _getPageTitle(_selectedNavIndex),
                      statusPill: _getStatusPill(_selectedNavIndex),
                      notificationCount: 3,
                      pendingApprovalCount: _pendingApprovalCount,
                      onApprovalsTap: () {
                        setState(() {
                          _isApprovalCenterOpen = true;
                          _isDiagnosticsOpen = false;
                        });
                      },
                      onAdminTap: () {
                        setState(() {
                          _isDiagnosticsOpen = true;
                          _isApprovalCenterOpen = false;
                        });
                      },
                      onSearchTap: () {
                        // Global search modal or focus
                      },
                      onNotificationsTap: () {
                        _navigateToTab(3); // Jump to Incident Intelligence
                      },
                      onProfileTap: () {
                        setState(() {
                          _isDiagnosticsOpen = true;
                          _isApprovalCenterOpen = false;
                        });
                      },
                    ),

                    // Active Screen Workspace: 11 Primary Operational Destinations
                    Expanded(
                      child: Container(
                        color: TexoraColors.workspaceBg,
                        child: IndexedStack(
                          index: _selectedNavIndex,
                          children: [
                            // 0: Executive Command Center (Dashboard)
                            ExecutiveCommandCenterScreen(
                              onNavigate: (index, {targetMachine}) =>
                                  _navigateToTab(index, targetMachine: targetMachine),
                            ),

                            // 1: AI Agent Operations Center (Fleet & Execution Workflows)
                            AiAgentOperationsScreen(
                              onNavigate: (index, {targetMachine}) =>
                                  _navigateToTab(index, targetMachine: targetMachine),
                            ),

                            // 2: Machine Monitoring (Live Telemetry & Contextual Digital Twin)
                            const MachineHealthAgentScreen(),

                            // 3: Incident Intelligence Workspace (Root Cause, AI Analysis & Audit Log)
                            IncidentIntelligenceScreen(
                              onNavigateToRecovery: (caseId) => _navigateToTab(4),
                              onNavigateToApprovals: () {
                                setState(() => _isApprovalCenterOpen = true);
                              },
                            ),

                            // 4: Production Intelligence (Batches, Capacity & Contextual Recovery)
                            ProductionIntelligenceScreen(
                              onNavigate: (index, {targetMachine}) =>
                                  _navigateToTab(index, targetMachine: targetMachine),
                            ),

                            // 5: Maintenance Execution Center (Work Orders & Verification)
                            MaintenanceExecutionScreen(
                              onNavigate: (index, {targetMachine}) =>
                                  _navigateToTab(index, targetMachine: targetMachine),
                            ),

                            // 6: Spare Parts Inventory Management
                            const InventoryManagementScreen(),

                            // 7: Quality Monitoring & Defect Analytics
                            const QualityMonitoringScreen(),

                            // 8: Energy Management & Sub-Metering
                            const EnergyManagementScreen(),

                            // 9: Reports & Analytics with CSV Export
                            const ReportsAnalyticsScreen(),

                            // 10: Enterprise AI Copilot Full Workspace
                            FactoryCopilotScreen(
                              onExit: () => setState(() => _selectedNavIndex = 0),
                              onNavigate: (index, {targetMachine}) =>
                                  _navigateToTab(index, targetMachine: targetMachine),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Floating AI Assistant accessible from all screens
          FloatingCopilotAssistant(
            onOpenFullScreen: () {
              setState(() {
                _selectedNavIndex = 10;
              });
            },
            onNavigate: (index, {targetMachine}) =>
                _navigateToTab(index, targetMachine: targetMachine),
          ),
        ],
      ),
    );
  }
}
