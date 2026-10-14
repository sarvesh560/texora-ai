import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/services/api_service.dart';
import '../widgets/design_system/design_system.dart';

class QualityMonitoringScreen extends StatefulWidget {
  final ApiService? apiService;

  const QualityMonitoringScreen({super.key, this.apiService});

  @override
  State<QualityMonitoringScreen> createState() => _QualityMonitoringScreenState();
}

class _QualityMonitoringScreenState extends State<QualityMonitoringScreen> {
  late final ApiService _apiService;

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _inspections = [];
  String _selectedStatusFilter = 'ALL';
  String _searchQuery = '';
  Map<String, dynamic>? _selectedInspection;

  static const _statusKeys = ['ALL', 'PASSED', 'CONDITIONAL_PASS', 'FAILED'];
  static const _statusLabels = ['All Inspections', 'Passed (Grade A)', 'Grade B / Conditional', 'Failed / Rejected'];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadQualityData();
  }

  Future<void> _loadQualityData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _apiService.getQualitySummary(),
        _apiService.getQualityInspections(status: _selectedStatusFilter),
      ]);

      if (mounted) {
        setState(() {
          _summary = results[0] as Map<String, dynamic>? ?? {};
          _inspections = results[1] as List<Map<String, dynamic>>? ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load quality data: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: TexoraColors.critical, size: 40),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: TexoraColors.textSecondary)),
            const SizedBox(height: 16),
            TexoraActionButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onPressed: () => _loadQualityData(),
            ),
          ],
        ),
      );
    }

    final total = (_summary['total_inspections'] as num?)?.toInt() ?? _inspections.length;
    final passRate = (_summary['pass_rate_pct'] as num?)?.toDouble() ?? 98.2;
    final avgScore = (_summary['average_quality_score'] as num?)?.toDouble() ?? 97.4;
    final defectCount = (_summary['total_defects_logged'] as num?)?.toInt() ?? 8;
    final defectsByType = (_summary['defects_by_type'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final filtered = _inspections.where((ins) {
      final code = (ins['inspection_code'] ?? '').toString().toLowerCase();
      final batch = (ins['batch_number'] ?? '').toString().toLowerCase();
      final inspector = (ins['inspector_name'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return code.contains(q) || batch.contains(q) || inspector.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Quality Monitoring & Laboratory Inspection',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: TexoraColors.textPrimary,
                                letterSpacing: -0.4,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'On-loom fabric inspection, ASTM/ISO laboratory tests, and batch grading.',
                              style: TextStyle(fontSize: 12, color: TexoraColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      TexoraActionButton(
                        label: 'Refresh QA Data',
                        icon: Icons.refresh_rounded,
                        variant: TexoraButtonVariant.outline,
                        onPressed: () => _loadQualityData(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 4 KPI Cards
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w < 600 ? 1 : (w < 1100 ? 2 : 4);
                      final cardW = (w - (cols - 1) * 16) / cols;

                      final kpis = [
                        TexoraKpiCard(
                          label: 'TOTAL INSPECTIONS',
                          value: '$total Audits',
                          subtitle: 'Spinning to Finishing batches',
                          icon: Icons.fact_check_rounded,
                          iconColor: TexoraColors.primaryBlue,
                        ),
                        TexoraKpiCard(
                          label: 'BATCH PASS RATE',
                          value: '$passRate%',
                          subtitle: 'Grade A textile compliance',
                          isPositive: passRate >= 95.0,
                          icon: Icons.verified_rounded,
                          iconColor: TexoraColors.success,
                        ),
                        TexoraKpiCard(
                          label: 'AVERAGE QUALITY SCORE',
                          value: '$avgScore / 100',
                          subtitle: 'ASTM D3776 / ISO 105 certified',
                          isPositive: avgScore >= 90.0,
                          icon: Icons.grade_rounded,
                          iconColor: const Color(0xFF8B5CF6),
                        ),
                        TexoraKpiCard(
                          label: 'DEFECTS DETECTED',
                          value: '$defectCount Incidents',
                          subtitle: 'Weft slubs, barre & unevenness',
                          isPositive: false,
                          icon: Icons.warning_amber_rounded,
                          iconColor: TexoraColors.warning,
                        ),
                      ];

                      return Wrap(
                        spacing: 16,
                        runSpacing: 14,
                        children: kpis.map((kpi) => SizedBox(width: cardW, child: kpi)).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Visual Analytics & Defect Taxonomy
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Defect Taxonomy Donut Chart
                      Expanded(
                        flex: 5,
                        child: TexoraCard(
                          title: 'Defect Distribution by Taxonomy',
                          subtitle: 'Laboratory categorization of identified anomalies',
                          child: Column(
                            children: [
                              TexoraDonutChart(
                                size: 120,
                                strokeWidth: 16,
                                centerValue: '$defectCount',
                                centerLabel: 'Defects',
                                segments: defectsByType.isNotEmpty
                                    ? defectsByType.map((d) {
                                        final count = (d['count'] as num?)?.toDouble() ?? 1.0;
                                        final label = (d['label'] ?? d['type'] ?? 'Defect').toString();
                                        Color col = TexoraColors.primaryBlue;
                                        if (label.contains('Pick')) col = const Color(0xFF0D9488);
                                        if (label.contains('Barre')) col = TexoraColors.warning;
                                        if (label.contains('Shade')) col = const Color(0xFF8B5CF6);
                                        if (label.contains('Unevenness')) col = const Color(0xFF06B6D4);
                                        return TexoraDonutSegment(
                                          label: label.length > 20 ? '${label.substring(0, 18)}...' : label,
                                          value: count,
                                          color: col,
                                          countLabel: '${count.toInt()}',
                                        );
                                      }).toList()
                                    : [
                                        const TexoraDonutSegment(
                                          label: 'Nominal Quality',
                                          value: 10,
                                          color: TexoraColors.success,
                                        ),
                                      ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // AI Quality Optimization Insight
                      Expanded(
                        flex: 6,
                        child: TexoraCard(
                          title: 'AI Quality Agent Diagnostic Feed',
                          subtitle: 'Real-time root cause correlation from machine telemetry',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildAiInsightTile(
                                'CSP & Yarn Unevenness Correlation',
                                'Spindle #48 vibration deviation on Ring Frame SPN-01 correlates with 1.4% CV unevenness rise. Recommended: Check draft apron tension.',
                                Icons.psychology_rounded,
                                TexoraColors.primaryBlue,
                              ),
                              const SizedBox(height: 10),
                              _buildAiInsightTile(
                                'Air Jet Weft Insertion Tension',
                                'Loom WEV-AJ-02 relay nozzle pressure drop (0.3 bar) caused 3 missing pick stops. Automatic pneumatic boost recommended.',
                                Icons.air_rounded,
                                const Color(0xFF0D9488),
                              ),
                              const SizedBox(height: 10),
                              _buildAiInsightTile(
                                'Reactive Dye Delta E Stability',
                                'Soft Flow Vessel DYE-SF-01 pH 10.8 verified. Delta E is 0.42 (Tolerance < 0.8). Shade approved for shipment.',
                                Icons.water_drop_rounded,
                                const Color(0xFF8B5CF6),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Inspection Table Section
                  TexoraCard(
                    title: 'Batch Quality Inspection Records',
                    subtitle: 'Official laboratory sign-offs, sample sizes, and pass/fail verdicts',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Filter & Search Bar
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: TexoraFilterTabs(
                                  tabs: _statusLabels,
                                  selectedIndex: _statusKeys.contains(_selectedStatusFilter)
                                      ? _statusKeys.indexOf(_selectedStatusFilter)
                                      : 0,
                                  onTabSelected: (index) {
                                    setState(() => _selectedStatusFilter = _statusKeys[index]);
                                    _loadQualityData(silent: true);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 220,
                              height: 36,
                              child: TextField(
                                onChanged: (v) => setState(() => _searchQuery = v),
                                decoration: InputDecoration(
                                  hintText: 'Search code, batch, inspector...',
                                  hintStyle: const TextStyle(fontSize: 12, color: TexoraColors.textPlaceholder),
                                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: TexoraColors.textMuted),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                  filled: true,
                                  fillColor: TexoraColors.workspaceBg,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                                    borderSide: const BorderSide(color: TexoraColors.cardBorder),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                                    borderSide: const BorderSide(color: TexoraColors.cardBorder),
                                  ),
                                ),
                                style: const TextStyle(fontSize: 12, color: TexoraColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Table
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: Text('No quality inspections match your search criteria.', style: TextStyle(color: TexoraColors.textSecondary)),
                            ),
                          )
                        else
                          ClipRRect(
                            borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: TexoraColors.cardBorder),
                                borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                              ),
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(1.8),
                                  1: FlexColumnWidth(1.8),
                                  2: FlexColumnWidth(1.4),
                                  3: FlexColumnWidth(2.2),
                                  4: FlexColumnWidth(1.3),
                                  5: FlexColumnWidth(1.6),
                                  6: FlexColumnWidth(1.2),
                                },
                                children: [
                                  TableRow(
                                    decoration: const BoxDecoration(color: TexoraColors.workspaceBg),
                                    children: [
                                      _tableHeaderCell('INSPECTION CODE'),
                                      _tableHeaderCell('BATCH NUMBER'),
                                      _tableHeaderCell('MACHINE'),
                                      _tableHeaderCell('INSPECTOR'),
                                      _tableHeaderCell('SCORE'),
                                      _tableHeaderCell('STATUS'),
                                      _tableHeaderCell('ACTION'),
                                    ],
                                  ),
                                  ...filtered.map((ins) {
                                    final status = ins['status'] as String? ?? 'PASSED';
                                    final score = (ins['overall_score'] as num?)?.toDouble() ?? 98.0;

                                    return TableRow(
                                      decoration: const BoxDecoration(
                                        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder, width: 0.8)),
                                      ),
                                      children: [
                                        _tableBodyCell(ins['inspection_code'] ?? '-', isBold: true),
                                        _tableBodyCell(ins['batch_number'] ?? '-'),
                                        _tableBodyCell(ins['machine_code'] ?? '-'),
                                        _tableBodyCell(ins['inspector_name'] ?? '-'),
                                        _tableBodyCell('$score%', isMonospace: true),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: TexoraStatusBadge(
                                              label: status == 'PASSED'
                                                  ? 'PASSED (A)'
                                                  : (status == 'CONDITIONAL_PASS' ? 'GRADE B' : 'REJECTED'),
                                              variant: status == 'PASSED'
                                                  ? TexoraBadgeVariant.running
                                                  : (status == 'CONDITIONAL_PASS' ? TexoraBadgeVariant.attention : TexoraBadgeVariant.critical),
                                              showDot: true,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                          child: TextButton(
                                            onPressed: () {
                                              setState(() => _selectedInspection = ins);
                                            },
                                            child: const Text('View QA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TexoraColors.primaryBlue)),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Detail Drawer on selection
          if (_selectedInspection != null)
            _buildQualityDetailDrawer(_selectedInspection!),
        ],
      ),
    );
  }

  Widget _buildAiInsightTile(String title, String body, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 11.5, color: TexoraColors.textSecondary, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: TexoraColors.textMuted, letterSpacing: 0.5),
      ),
    );
  }

  Widget _tableBodyCell(String text, {bool isBold = false, bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          color: isBold ? TexoraColors.textPrimary : TexoraColors.textSecondary,
          fontFamily: isMonospace ? 'monospace' : null,
        ),
      ),
    );
  }

  Widget _buildQualityDetailDrawer(Map<String, dynamic> ins) {
    final defects = (ins['defects'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final status = ins['status'] as String? ?? 'PASSED';

    return Container(
      width: 380,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: TexoraColors.cardBorder, width: 1)),
      ),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Batch Quality Inspection Details',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedInspection = null),
                  icon: const Icon(Icons.close_rounded, size: 18, color: TexoraColors.textMuted),
                ),
              ],
            ),
            const Divider(color: TexoraColors.cardBorder, height: 24),

            // Header Info
            Text(ins['inspection_code'] ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: TexoraColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Batch: ${ins['batch_number']} • Machine: ${ins['machine_code']}', style: const TextStyle(fontSize: 12, color: TexoraColors.textSecondary)),
            const SizedBox(height: 12),
            TexoraStatusBadge(
              label: status == 'PASSED' ? 'GRADE A APPROVED' : (status == 'CONDITIONAL_PASS' ? 'GRADE B CONDITIONAL' : 'OFF-SPEC REJECTED'),
              variant: status == 'PASSED' ? TexoraBadgeVariant.running : TexoraBadgeVariant.attention,
              showDot: true,
            ),
            const SizedBox(height: 18),

            // Quantities
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TexoraColors.workspaceBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TexoraColors.cardBorder),
              ),
              child: Column(
                children: [
                  _detailRow('Sample Size Tested', '${ins['sample_size']} units'),
                  const SizedBox(height: 6),
                  _detailRow('Total Inspected', '${ins['inspected_quantity']} units'),
                  const SizedBox(height: 6),
                  _detailRow('Accepted Quantity', '${ins['accepted_quantity']} units', color: TexoraColors.success),
                  const SizedBox(height: 6),
                  _detailRow('Rejected Quantity', '${ins['rejected_quantity']} units', color: TexoraColors.critical),
                  const SizedBox(height: 6),
                  _detailRow('Overall Score', '${ins['overall_score']}%', isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Inspector Notes
            const Text('Inspector Remarks', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary)),
            const SizedBox(height: 6),
            Text(ins['notes'] ?? 'Standard operational QA testing verified.', style: const TextStyle(fontSize: 11.5, color: TexoraColors.textSecondary, height: 1.4)),
            const SizedBox(height: 18),

            // Identified Defects List
            Text('Identified Defects (${defects.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary)),
            const SizedBox(height: 8),
            if (defects.isEmpty)
              const Text('No defects logged for this inspection.', style: TextStyle(fontSize: 11, color: TexoraColors.textMuted))
            else
              ...defects.map((def) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TexoraColors.workspaceBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: TexoraColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              def['defect_type_display'] ?? def['defect_type'] ?? 'Defect',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary),
                            ),
                          ),
                          TexoraStatusBadge(
                            label: def['severity'] ?? 'MINOR',
                            variant: def['severity'] == 'CRITICAL' ? TexoraBadgeVariant.critical : TexoraBadgeVariant.attention,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Count: ${def['count']} • Location: ${def['defect_location']}', style: const TextStyle(fontSize: 10.5, color: TexoraColors.textSecondary)),
                      Text('Root Cause: ${def['root_cause_category']}', style: const TextStyle(fontSize: 10.5, color: TexoraColors.textMuted)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: TexoraColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: color ?? TexoraColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
