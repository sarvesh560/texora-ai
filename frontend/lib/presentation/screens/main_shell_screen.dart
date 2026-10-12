import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../widgets/app_sidebar.dart';
import 'executive_command_center_screen.dart';
import 'digital_twin_screen.dart';
import 'incident_intelligence_screen.dart';
import 'machine_health_agent_screen.dart';
import 'factory_recovery_screen.dart';
import 'approval_center_screen.dart';
import 'audit_trail_screen.dart';
import 'simulation_screen.dart';
import 'what_if_simulation_screen.dart';
import 'backend_status_screen.dart';
import 'ai_agent_operations_screen.dart';
import 'maintenance_execution_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedNavIndex = 0;
  String? _targetWhatIfMachine;
  bool _isSidebarCollapsed = false;

  void _navigateToTab(int index, {String? targetMachine}) {
    setState(() {
      _selectedNavIndex = index;
      if (targetMachine != null) {
        _targetWhatIfMachine = targetMachine;
      }
    });
  }

  void _navigateToWhatIf(String machineCode) {
    setState(() {
      _targetWhatIfMachine = machineCode;
      _selectedNavIndex = 8; // What-If Simulation (Sandbox)
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final autoCollapse = screenWidth < 1100;
    final effectiveCollapsed = _isSidebarCollapsed || autoCollapse;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      body: Row(
        children: [
          // Enterprise Dark Navigation Sidebar
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
              });
            },
          ),

          // Main Screen Content Area
          Expanded(
            child: Container(
              color: AppColors.background,
              child: IndexedStack(
                index: _selectedNavIndex,
                children: [
                  // 0: Executive Command Center
                  ExecutiveCommandCenterScreen(
                    onNavigate: (index, {targetMachine}) =>
                        _navigateToTab(index, targetMachine: targetMachine),
                  ),

                  // 1: Factory Digital Twin & Dependency Flow
                  DigitalTwinScreen(
                    onNavigateToWhatIfWithMachine: _navigateToWhatIf,
                  ),

                  // 2: Incident Intelligence Workspace
                  IncidentIntelligenceScreen(
                    onNavigateToRecovery: (caseId) => _navigateToTab(4),
                    onNavigateToApprovals: () => _navigateToTab(5),
                  ),

                  // 3: Machine Health AI Specialist
                  const MachineHealthAgentScreen(),

                  // 4: Factory Autonomous Recovery & Work Orders
                  const FactoryRecoveryScreen(),

                  // 5: Manager Approval Center
                  ApprovalCenterScreen(
                    onNavigate: (index, {targetMachine}) =>
                        _navigateToTab(index, targetMachine: targetMachine),
                  ),

                  // 6: Immutable Audit Trail & Governance
                  const AuditTrailScreen(),

                  // 7: Telemetry Simulator (Isolated Testing Sandbox)
                  const SimulationScreen(),

                  // 8: What-If Simulation Studio (Simulation Sandbox)
                  WhatIfSimulationScreen(
                    key: ValueKey(_targetWhatIfMachine ?? 'default'),
                    initialMachineCode: _targetWhatIfMachine,
                  ),

                  // 9: Backend & Connectivity Status
                  const BackendStatusScreen(),

                  // 10: AI Agent Operations Center (Specialist Fleet & Pipeline)
                  AiAgentOperationsScreen(
                    onNavigate: (index, {targetMachine}) =>
                        _navigateToTab(index, targetMachine: targetMachine),
                  ),

                  // 11: Maintenance Execution Center (Work Orders & Verification)
                  MaintenanceExecutionScreen(
                    onNavigate: (index, {targetMachine}) =>
                        _navigateToTab(index, targetMachine: targetMachine),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
