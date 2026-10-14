import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/digital_twin_models.dart';

/// Interactive Animated Factory Flow View
/// Visualizes inter-departmental manufacturing stages:
/// Spinning -> Weaving / Knitting -> Dyeing -> Finishing
///
/// NOTE: Flow animations represent a conceptual factory process flow,
/// not verified physical movement of material.
class FactoryFlowView extends StatefulWidget {
  final DigitalTwinSnapshotModel? snapshot;
  final String selectedDepartment;
  final MachineTwinModel? selectedMachine;
  final Function(String departmentCode) onSelectDepartment;
  final Function(MachineTwinModel machine) onSelectMachine;
  final Function(String machineCode)? onNavigateToWhatIfWithMachine;

  const FactoryFlowView({
    super.key,
    required this.snapshot,
    required this.selectedDepartment,
    required this.selectedMachine,
    required this.onSelectDepartment,
    required this.onSelectMachine,
    this.onNavigateToWhatIfWithMachine,
  });

  @override
  State<FactoryFlowView> createState() => _FactoryFlowViewState();
}

class _FactoryFlowViewState extends State<FactoryFlowView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Map<String, List<MachineTwinModel>> _groupMachinesByDept() {
    final map = <String, List<MachineTwinModel>>{
      'SPN': [],
      'WEV': [],
      'KNT': [],
      'DYE': [],
      'FIN': [],
    };
    if (widget.snapshot == null) return map;
    for (final m in widget.snapshot!.machineStates) {
      if (map.containsKey(m.departmentCode)) {
        map[m.departmentCode]!.add(m);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final deptGroups = _groupMachinesByDept();
    final isReducedMotion = MediaQuery.of(context).disableAnimations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Conceptual Flow Banner
        Container(
          margin: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0B132B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_tree_rounded, color: Color(0xFF38BDF8), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    children: [
                      const TextSpan(
                        text: 'Process Flow Topology: ',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(
                        text: 'Spinning (Yarn) ➔ Weaving & Knitting (Fabrication) ➔ Dyeing (Wet Processing) ➔ Finishing (Inspection). ',
                      ),
                      TextSpan(
                        text: 'Note: Animations indicate conceptual manufacturing sequence; telemetry disruptions highlight upstream/downstream flow constraints.',
                        style: TextStyle(color: Colors.white.withAlpha(140), fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Interactive Flow Diagram Canvas
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _FactoryFlowPainter(
                        animationValue: isReducedMotion ? 0.0 : _pulseController.value,
                        deptGroups: deptGroups,
                        selectedDept: widget.selectedDepartment,
                      ),
                      child: _buildDepartmentInteractiveGrid(constraints, deptGroups),
                    );
                  },
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Department Machine Sub-Grid (Interactive Floor)
        Expanded(
          flex: 4,
          child: Container(
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.precision_manufacturing_rounded, color: AppColors.primaryBlueLight, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.selectedDepartment == 'ALL'
                                  ? 'Active Assets: All Factory Departments (${widget.snapshot?.totalMachines ?? 25} Units)'
                                  : 'Active Assets: ${_getDepartmentFullName(widget.selectedDepartment)} (${deptGroups[widget.selectedDepartment]?.length ?? 0} Units)',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Click any machine to inspect telemetry & limits',
                        style: TextStyle(color: Colors.white.withAlpha(120), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _buildMachineSubGrid(deptGroups),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getDepartmentFullName(String code) {
    switch (code) {
      case 'SPN':
        return 'Spinning Department';
      case 'WEV':
        return 'Weaving Shed';
      case 'KNT':
        return 'Knitting Division';
      case 'DYE':
        return 'Dyeing & Processing';
      case 'FIN':
        return 'Finishing & Inspection';
      default:
        return 'Factory Floor';
    }
  }

  Widget _buildDepartmentInteractiveGrid(
      BoxConstraints constraints, Map<String, List<MachineTwinModel>> deptGroups) {
    // 4 Column Stage Layout:
    // Col 0: Spinning (SPN)
    // Col 1: Weaving (WEV) [Top] / Knitting (KNT) [Bottom]
    // Col 2: Dyeing (DYE)
    // Col 3: Finishing (FIN)
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;

    final colW = (w - 48) / 4;
    final cardW = math.min(colW, 220.0);
    final cardH = math.min(h * 0.42, 170.0);

    return Stack(
      children: [
        // SPN (Col 0, centered)
        Positioned(
          left: (colW - cardW) / 2,
          top: (h - cardH) / 2,
          width: cardW,
          height: cardH,
          child: _buildDepartmentFlowCard('SPN', 'Spinning Dept', 'Yarn Production', deptGroups['SPN'] ?? []),
        ),

        // WEV (Col 1, upper)
        Positioned(
          left: colW + (colW - cardW) / 2,
          top: h * 0.06,
          width: cardW,
          height: cardH,
          child: _buildDepartmentFlowCard('WEV', 'Weaving Shed', 'Woven Fabric Route', deptGroups['WEV'] ?? []),
        ),

        // KNT (Col 1, lower)
        Positioned(
          left: colW + (colW - cardW) / 2,
          top: h * 0.52,
          width: cardW,
          height: cardH,
          child: _buildDepartmentFlowCard('KNT', 'Knitting Div', 'Knitted Fabric Route', deptGroups['KNT'] ?? []),
        ),

        // DYE (Col 2, centered)
        Positioned(
          left: colW * 2 + (colW - cardW) / 2,
          top: (h - cardH) / 2,
          width: cardW,
          height: cardH,
          child: _buildDepartmentFlowCard('DYE', 'Dyeing & Proc', 'Wet Coloration', deptGroups['DYE'] ?? []),
        ),

        // FIN (Col 3, centered)
        Positioned(
          left: colW * 3 + (colW - cardW) / 2,
          top: (h - cardH) / 2,
          width: cardW,
          height: cardH,
          child: _buildDepartmentFlowCard('FIN', 'Finishing & Insp', 'Quality & Packaging', deptGroups['FIN'] ?? []),
        ),
      ],
    );
  }

  Widget _buildDepartmentFlowCard(
    String code,
    String name,
    String routeRole,
    List<MachineTwinModel> machines,
  ) {
    final isSelected = widget.selectedDepartment == code;
    final running = machines.where((m) => m.twinPresentationState == 'RUNNING').length;
    final warning = machines.where((m) => m.twinPresentationState == 'WARNING').length;
    final critical = machines.where((m) => m.twinPresentationState == 'CRITICAL').length;
    final stale = machines.where((m) => m.twinPresentationState == 'UNKNOWN' || m.isStale).length;
    final total = machines.length;

    final hasDisruption = critical > 0;
    final hasWarning = warning > 0;

    Color statusColor = AppColors.successGreen;
    if (hasDisruption) {
      statusColor = AppColors.errorRed;
    } else if (hasWarning) {
      statusColor = AppColors.warningOrange;
    } else if (stale > 0 && running == 0) {
      statusColor = const Color(0xFF64748B);
    }

    return InkWell(
      onTap: () => widget.onSelectDepartment(code),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlueLight
                : (hasDisruption ? AppColors.errorRed.withAlpha(160) : const Color(0xFF1E293B)),
            width: isSelected ? 2 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withAlpha(50),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ]
              : (hasDisruption
                  ? [
                      BoxShadow(
                        color: AppColors.errorRed.withAlpha(30),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : null),
        ),
        child: LayoutBuilder(
          builder: (context, cardConstraints) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: cardConstraints.maxWidth,
                height: math.max(cardConstraints.maxHeight, 115.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Header Row: Dept Code + Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue.withAlpha(40),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  code,
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),

                    // Route Subtitle
                    Text(
                      routeRole,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                    ),

                    // Breakdown Chips
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0F1D),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatPill('Total', '$total', Colors.white),
                          _buildStatPill('Run', '$running', AppColors.successGreen),
                          if (warning > 0) _buildStatPill('Warn', '$warning', AppColors.warningOrange),
                          if (critical > 0) _buildStatPill('Crit', '$critical', AppColors.errorRed),
                          if (stale > 0 && critical == 0 && warning == 0)
                            _buildStatPill('Stale', '$stale', const Color(0xFF94A3B8)),
                        ],
                      ),
                    ),

                    // Disruption Indicator
                    if (hasDisruption)
                      Row(
                        children: [
                          const Icon(Icons.warning_rounded, color: AppColors.errorRed, size: 12),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'FLOW BOTTLENECK DETECTED',
                              style: TextStyle(
                                color: AppColors.errorRed,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          const Icon(Icons.sync_alt_rounded, color: Color(0xFF34D399), size: 12),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'FLOW NOMINAL',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  Widget _buildMachineSubGrid(Map<String, List<MachineTwinModel>> deptGroups) {
    List<MachineTwinModel> displayMachines = [];
    if (widget.selectedDepartment == 'ALL') {
      displayMachines = widget.snapshot?.machineStates ?? [];
    } else {
      displayMachines = deptGroups[widget.selectedDepartment] ?? [];
    }

    if (displayMachines.isEmpty) {
      return const Center(
        child: Text(
          'No machines in this department zone.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      );
    }

    return GridView.builder(
      scrollDirection: Axis.horizontal,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        mainAxisExtent: 180,
        mainAxisSpacing: 10,
      ),
      itemCount: displayMachines.length,
      itemBuilder: (context, index) {
        final machine = displayMachines[index];
        final isSelected = widget.selectedMachine?.code == machine.code;
        final stateColor = _getStateColor(machine.twinPresentationState);

        return InkWell(
          onTap: () => widget.onSelectMachine(machine),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0B132B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppColors.primaryBlueLight : stateColor.withAlpha(90),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        machine.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: stateColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Text(
                  machine.name,
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        machine.twinPresentationState,
                        style: TextStyle(
                          color: stateColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${machine.healthScore.toInt()}% Health',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStateColor(String state) {
    switch (state.toUpperCase()) {
      case 'RUNNING':
        return AppColors.successGreen;
      case 'WARNING':
        return AppColors.warningOrange;
      case 'CRITICAL':
        return AppColors.errorRed;
      case 'UNDER_MAINTENANCE':
        return AppColors.primaryBlueLight;
      default:
        return const Color(0xFF64748B);
    }
  }
}

/// Custom painter for the animated material flow paths
class _FactoryFlowPainter extends CustomPainter {
  final double animationValue;
  final Map<String, List<MachineTwinModel>> deptGroups;
  final String selectedDept;

  _FactoryFlowPainter({
    required this.animationValue,
    required this.deptGroups,
    required this.selectedDept,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final colW = (w - 48) / 4;
    final cardW = math.min(colW, 220.0);
    final cardH = math.min(h * 0.42, 170.0);

    // Node Anchor Points (Right edge / Left edge)
    final spnOut = Offset((colW - cardW) / 2 + cardW, h / 2);

    final wevIn = Offset(colW + (colW - cardW) / 2, h * 0.06 + cardH / 2);
    final wevOut = Offset(colW + (colW - cardW) / 2 + cardW, h * 0.06 + cardH / 2);

    final kntIn = Offset(colW + (colW - cardW) / 2, h * 0.52 + cardH / 2);
    final kntOut = Offset(colW + (colW - cardW) / 2 + cardW, h * 0.52 + cardH / 2);

    final dyeIn = Offset(colW * 2 + (colW - cardW) / 2, h / 2);
    final dyeOut = Offset(colW * 2 + (colW - cardW) / 2 + cardW, h / 2);

    final finIn = Offset(colW * 3 + (colW - cardW) / 2, h / 2);

    // Check Disruption States
    final spnDisrupted = (deptGroups['SPN'] ?? []).any((m) => m.twinPresentationState == 'CRITICAL');
    final wevDisrupted = (deptGroups['WEV'] ?? []).any((m) => m.twinPresentationState == 'CRITICAL');
    final kntDisrupted = (deptGroups['KNT'] ?? []).any((m) => m.twinPresentationState == 'CRITICAL');
    final dyeDisrupted = (deptGroups['DYE'] ?? []).any((m) => m.twinPresentationState == 'CRITICAL');

    // 1. SPN -> WEV
    _drawFlowPath(canvas, spnOut, wevIn, isDisrupted: spnDisrupted, label: 'Yarn to Looms');

    // 2. SPN -> KNT
    _drawFlowPath(canvas, spnOut, kntIn, isDisrupted: spnDisrupted, label: 'Yarn to Knitting');

    // 3. WEV -> DYE
    _drawFlowPath(canvas, wevOut, dyeIn, isDisrupted: wevDisrupted, label: 'Greige Woven');

    // 4. KNT -> DYE
    _drawFlowPath(canvas, kntOut, dyeIn, isDisrupted: kntDisrupted, label: 'Greige Knit');

    // 5. DYE -> FIN
    _drawFlowPath(canvas, dyeOut, finIn, isDisrupted: dyeDisrupted, label: 'Dyed Fabric');
  }

  void _drawFlowPath(
    Canvas canvas,
    Offset start,
    Offset end, {
    required bool isDisrupted,
    required String label,
  }) {
    final path = Path();
    path.moveTo(start.dx, start.dy);

    final midX = (start.dx + end.dx) / 2;
    path.cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);

    // Draw Base Track
    final trackPaint = Paint()
      ..color = isDisrupted
          ? AppColors.errorRed.withAlpha(50)
          : const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawPath(path, trackPaint);

    // Draw Animated Pulse along the path
    final metric = path.computeMetrics().firstOrNull;
    if (metric != null && metric.length > 0) {
      final pulseDist = (animationValue * metric.length) % metric.length;
      final tangent = metric.getTangentForOffset(pulseDist);

      if (tangent != null) {
        final pulseColor = isDisrupted ? AppColors.errorRed : const Color(0xFF38BDF8);

        // Glow Circle
        final glowPaint = Paint()
          ..color = pulseColor.withAlpha(120)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(tangent.position, 5, glowPaint);

        // Solid Core Circle
        final corePaint = Paint()..color = Colors.white;
        canvas.drawCircle(tangent.position, 2.5, corePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FactoryFlowPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.deptGroups != deptGroups ||
        oldDelegate.selectedDept != selectedDept;
  }
}
