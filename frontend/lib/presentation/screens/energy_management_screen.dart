import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/services/api_service.dart';
import '../widgets/design_system/design_system.dart';

class EnergyManagementScreen extends StatefulWidget {
  final ApiService? apiService;

  const EnergyManagementScreen({super.key, this.apiService});

  @override
  State<EnergyManagementScreen> createState() => _EnergyManagementScreenState();
}

class _EnergyManagementScreenState extends State<EnergyManagementScreen> {
  late final ApiService _apiService;

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _readings = [];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadEnergyData();
  }

  Future<void> _loadEnergyData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _apiService.getEnergySummary(),
        _apiService.getEnergyReadings(limit: 60),
      ]);

      if (mounted) {
        setState(() {
          _summary = results[0] as Map<String, dynamic>? ?? {};
          _readings = results[1] as List<Map<String, dynamic>>? ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load electrical energy data: $e';
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
              onPressed: () => _loadEnergyData(),
            ),
          ],
        ),
      );
    }

    final totalKwh = (_summary['total_consumption_kwh'] as num?)?.toDouble() ?? 11981.0;
    final avgKw = (_summary['average_power_kw'] as num?)?.toDouble() ?? 498.5;
    final costInr = (_summary['estimated_cost_inr'] as num?)?.toDouble() ?? (totalKwh * 8.20);
    final carbonKg = (_summary['total_carbon_emission_kg'] as num?)?.toDouble() ?? (totalKwh * 0.82);
    final avgPf = (_summary['average_power_factor'] as num?)?.toDouble() ?? 0.94;
    final deptBreakdown = (_summary['department_breakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final hourlyTrend = (_summary['hourly_trend'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final recommendations = (_summary['ai_recommendations'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final trendPoints = hourlyTrend.asMap().entries.map((entry) {
      final i = entry.key;
      final h = entry.value;
      final kw = (h['power_kw'] as num?)?.toDouble() ?? 450.0;
      final ts = (h['timestamp'] ?? '12:00').toString();
      return TelemetryDataPoint(
        timestamp: DateTime.now().subtract(Duration(hours: hourlyTrend.length - i)),
        value: kw,
        label: ts,
      );
    }).toList();

    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Screen Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Electrical Energy & Sub-Metered Load',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: TexoraColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Active power (kW), cumulative energy (kWh), peak shaving tariff alerts, and CO2 emissions.',
                        style: TextStyle(fontSize: 12, color: TexoraColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                TexoraActionButton(
                  label: 'Poll Sub-Meters',
                  icon: Icons.flash_on_rounded,
                  variant: TexoraButtonVariant.outline,
                  onPressed: () => _loadEnergyData(),
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
                    label: 'TOTAL PLANT CONSUMPTION',
                    value: '${totalKwh.toInt()} kWh',
                    subtitle: 'Today cumulative draw (-6% vs avg)',
                    isPositive: true,
                    icon: Icons.bolt_rounded,
                    iconColor: TexoraColors.primaryBlue,
                  ),
                  TexoraKpiCard(
                    label: 'ACTIVE ELECTRICAL LOAD',
                    value: '$avgKw kW',
                    subtitle: 'Substation load (Avg PF $avgPf)',
                    icon: Icons.speed_rounded,
                    iconColor: const Color(0xFF0D9488),
                  ),
                  TexoraKpiCard(
                    label: 'ESTIMATED ENERGY COST',
                    value: '₹${costInr.toInt()}',
                    subtitle: 'TANGEDCO industrial tariff tier',
                    icon: Icons.currency_rupee_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                  ),
                  TexoraKpiCard(
                    label: 'CARBON EMISSION (CO2)',
                    value: '${carbonKg.toInt()} kg',
                    subtitle: 'Grid emission factor 0.82 kg/kWh',
                    isPositive: true,
                    icon: Icons.eco_rounded,
                    iconColor: TexoraColors.success,
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

            // Charts Row: Hourly Load Trend Chart & Departmental Comparison
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Load Trend Chart
                Expanded(
                  flex: 6,
                  child: TexoraCard(
                    title: 'Active Power Demand Trend (kW)',
                    subtitle: 'Real-time telemetry trend against sanctioned demand limit',
                    child: SizedBox(
                      height: 240,
                      child: trendPoints.isNotEmpty
                          ? TexoraTrendChart(
                              metricName: 'Active Load',
                              unit: 'kW',
                              lineColor: TexoraColors.primaryBlue,
                              points: trendPoints,
                              warningThreshold: 580.0,
                              criticalThreshold: 640.0,
                            )
                          : const Center(
                              child: Text('Telemetry load curve synchronizing...', style: TextStyle(color: TexoraColors.textMuted)),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Departmental Energy Breakdown
                Expanded(
                  flex: 5,
                  child: TexoraCard(
                    title: 'Departmental Energy Distribution',
                    subtitle: 'Sub-metered breakdown across 5 production departments',
                    child: Column(
                      children: deptBreakdown.map((dept) {
                        final kwh = (dept['consumption_kwh'] as num?)?.toDouble() ?? 100.0;
                        final cost = (dept['cost_inr'] as num?)?.toDouble() ?? (kwh * 8.20);
                        final name = dept['name'] ?? dept['code'] ?? 'Dept';
                        final code = dept['code'] ?? 'DPT';

                        Color barCol = TexoraColors.primaryBlue;
                        if (code == 'SPN') barCol = const Color(0xFF06B6D4);
                        if (code == 'WEV') barCol = const Color(0xFF2563EB);
                        if (code == 'KNT') barCol = const Color(0xFF0D9488);
                        if (code == 'DYE') barCol = const Color(0xFF8B5CF6);
                        if (code == 'FIN') barCol = const Color(0xFFEC4899);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary)),
                                  Text('${kwh.toInt()} kWh (₹${cost.toInt()})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TexoraColors.textSecondary, fontFamily: 'monospace')),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: totalKwh > 0 ? (kwh / totalKwh).clamp(0.05, 1.0) : 0.2,
                                  backgroundColor: TexoraColors.workspaceBg,
                                  valueColor: AlwaysStoppedAnimation<Color>(barCol),
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // AI Recommendations & Peak Shaving
            TexoraCard(
              title: 'AI Energy Agent Peak Shaving & Optimization',
              subtitle: 'Automated demand management to eliminate peak tariff penalties',
              child: Column(
                children: recommendations.map((rec) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
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
                            color: TexoraColors.warning.withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.bolt_rounded, color: TexoraColors.warning, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(rec['title'] ?? 'Energy Action', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary)),
                                  TexoraStatusBadge(label: rec['impact'] ?? 'SAVINGS', variant: TexoraBadgeVariant.running),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text('Department: ${rec['department']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TexoraColors.primaryBlue)),
                              const SizedBox(height: 4),
                              Text(rec['action'] ?? '', style: const TextStyle(fontSize: 11.5, color: TexoraColors.textSecondary, height: 1.35)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // Machine Energy Readings Table
            TexoraCard(
              title: 'Sub-Metered Machine Telemetry Log',
              subtitle: 'Active power, energy meter readings, power factor, and voltage',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: TexoraColors.cardBorder),
                    borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.6),
                      1: FlexColumnWidth(2.0),
                      2: FlexColumnWidth(1.6),
                      3: FlexColumnWidth(1.6),
                      4: FlexColumnWidth(1.4),
                      5: FlexColumnWidth(1.4),
                      6: FlexColumnWidth(1.4),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: TexoraColors.workspaceBg),
                        children: [
                          _tableHeaderCell('ASSET CODE'),
                          _tableHeaderCell('DEPARTMENT'),
                          _tableHeaderCell('ACTIVE POWER'),
                          _tableHeaderCell('ENERGY (KWH)'),
                          _tableHeaderCell('POWER FACTOR'),
                          _tableHeaderCell('VOLTAGE'),
                          _tableHeaderCell('PEAK TARIFF'),
                        ],
                      ),
                      ..._readings.take(10).map((r) {
                        final kw = (r['active_power_kw'] as num?)?.toDouble() ?? 0.0;
                        final kwh = (r['energy_kwh'] as num?)?.toDouble() ?? 0.0;
                        final pf = (r['power_factor'] as num?)?.toDouble() ?? 0.94;
                        final volt = (r['voltage_v'] as num?)?.toDouble() ?? 415.0;
                        final isPeak = r['is_peak_hour'] == true;

                        return TableRow(
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: TexoraColors.cardBorder, width: 0.8)),
                          ),
                          children: [
                            _tableBodyCell(r['machine_code'] ?? 'MAIN-FEED', isBold: true),
                            _tableBodyCell(r['department_name'] ?? 'Production Floor'),
                            _tableBodyCell('$kw kW', isMonospace: true, isBold: true),
                            _tableBodyCell('$kwh kWh', isMonospace: true),
                            _tableBodyCell('$pf', isMonospace: true),
                            _tableBodyCell('${volt.toInt()} V', isMonospace: true),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TexoraStatusBadge(
                                  label: isPeak ? 'PEAK RATE' : 'OFF-PEAK',
                                  variant: isPeak ? TexoraBadgeVariant.attention : TexoraBadgeVariant.neutral,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
}
