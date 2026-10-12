import 'package:flutter/material.dart';
import '../../data/models/workflow_timeline_models.dart';
import '../../data/services/api_service.dart';

class BusinessImpactCard extends StatefulWidget {
  final int incidentId;

  const BusinessImpactCard({
    super.key,
    required this.incidentId,
  });

  @override
  State<BusinessImpactCard> createState() => _BusinessImpactCardState();
}

class _BusinessImpactCardState extends State<BusinessImpactCard> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  BusinessImpactModel? _impact;

  // Interactive Calculator State
  int _calcMachineCount = 1;
  double _calcDowntimeHours = 2.5;
  double _calcHourlyValueInr = 4500.0;
  bool _showCalculator = false;

  @override
  void initState() {
    super.initState();
    _fetchBusinessImpact();
  }

  @override
  void didUpdateWidget(covariant BusinessImpactCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incidentId != widget.incidentId) {
      _fetchBusinessImpact();
    }
  }

  Future<void> _fetchBusinessImpact() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _apiService.getBusinessImpact(widget.incidentId);
      if (!mounted) return;

      if (data != null && data['kpis'] != null) {
        final parsed = BusinessImpactModel.fromJson(data);
        setState(() {
          _impact = parsed;
          _isLoading = false;
          _calcDowntimeHours = parsed.kpis.potentialDowntimeHours;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Business impact calculations unavailable for Incident #${widget.incidentId}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading financial model: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
              ),
              SizedBox(height: 12),
              Text(
                'Computing Deterministic Financial Exposure Model...',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _impact == null) {
      return const SizedBox.shrink();
    }

    final kpis = _impact!.kpis;
    final strategies = _impact!.strategyComparison;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.currency_rupee_rounded, color: Color(0xFF10B981), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Operational Disruption & Business Impact Intelligence',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () {
                    setState(() {
                      _showCalculator = !_showCalculator;
                    });
                  },
                  icon: Icon(_showCalculator ? Icons.close_rounded : Icons.calculate_rounded, size: 16),
                  label: Text(_showCalculator ? 'Hide Calculator' : 'Interactive Exposure Calculator'),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top KPI Metrics Grid
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildKpiCard(
                      label: 'Potential Downtime',
                      value: '${kpis.potentialDowntimeHours} hrs',
                      subtitle: 'With Recommended Strategy',
                      accentColor: const Color(0xFF38BDF8),
                      icon: Icons.timer_outlined,
                    ),
                    _buildKpiCard(
                      label: 'Estimated Output Loss',
                      value: '${kpis.productionOutputLoss} units',
                      subtitle: 'Output Disruption',
                      accentColor: const Color(0xFFF59E0B),
                      icon: Icons.inventory_2_outlined,
                    ),
                    _buildKpiCard(
                      label: 'Estimated Repair Cost',
                      value: '₹${kpis.estimatedRepairCostInr.toInt()}',
                      subtitle: 'Labor & Spares',
                      accentColor: const Color(0xFFA855F7),
                      icon: Icons.build_outlined,
                    ),
                    _buildKpiCard(
                      label: 'Net Risk Avoided',
                      value: '₹${kpis.netFinancialRiskAvoidedInr.toInt()}',
                      subtitle: 'Vs Unmitigated Outage',
                      accentColor: const Color(0xFF10B981),
                      icon: Icons.shield_outlined,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Strategy Comparison Table
                const Text(
                  'RECOVERY STRATEGY FINANCIAL & OPERATIONAL COMPARISON',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: strategies.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final s = strategies[index];
                    final isRecommended = s.strategyCode == kpis.recommendedStrategy;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isRecommended ? const Color(0xFF1E293B) : const Color(0xFF0A0F1D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isRecommended ? const Color(0xFF10B981).withAlpha(150) : const Color(0xFF1E293B),
                          width: isRecommended ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isRecommended ? const Color(0xFF10B981).withAlpha(30) : const Color(0xFF1E293B),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isRecommended ? const Color(0xFF10B981) : const Color(0xFF64748B),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '#${s.rank}',
                                style: TextStyle(
                                  color: isRecommended ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      s.strategyName,
                                      style: TextStyle(
                                        color: isRecommended ? Colors.white : const Color(0xFFCBD5E1),
                                        fontSize: 13,
                                        fontWeight: isRecommended ? FontWeight.w700 : FontWeight.w600,
                                      ),
                                    ),
                                    if (isRecommended) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withAlpha(30),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'RECOMMENDED',
                                          style: TextStyle(
                                            color: Color(0xFF10B981),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Restores ${s.capacityRecoveredPct}% capacity • ${s.pros.isNotEmpty ? s.pros[0] : ""}',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${s.estimatedDowntimeHours} hrs downtime',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Est. Cost: ₹${s.estimatedCostInr.toInt()}',
                                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Interactive Exposure Calculator Panel
                if (_showCalculator) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0F1D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF38BDF8).withAlpha(100)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tune_rounded, color: Color(0xFF38BDF8), size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Interactive Plant Exposure Estimator',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Adjust machine parameters to estimate potential outage exposure across your production line.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                        const SizedBox(height: 14),

                        // Inputs
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Affected Machine Count: $_calcMachineCount',
                                    style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                                  ),
                                  Slider(
                                    value: _calcMachineCount.toDouble(),
                                    min: 1,
                                    max: 10,
                                    divisions: 9,
                                    activeColor: const Color(0xFF38BDF8),
                                    onChanged: (val) {
                                      setState(() {
                                        _calcMachineCount = val.toInt();
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Value / Hour: ₹${_calcHourlyValueInr.toInt()}',
                                    style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                                  ),
                                  Slider(
                                    value: _calcHourlyValueInr,
                                    min: 1000,
                                    max: 15000,
                                    divisions: 28,
                                    activeColor: const Color(0xFF10B981),
                                    onChanged: (val) {
                                      setState(() {
                                        _calcHourlyValueInr = val;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Calculated outcome
                        Builder(
                          builder: (context) {
                            final unmitHours = _calcDowntimeHours * 3.2;
                            final unmitTotal = _calcMachineCount * unmitHours * _calcHourlyValueInr;
                            final mitTotal = (_calcMachineCount * _calcDowntimeHours * _calcHourlyValueInr) + (kpis.estimatedRepairCostInr * _calcMachineCount);
                            final saved = unmitTotal - mitTotal;

                            return Container(
                              margin: const EdgeInsets.only(top: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    children: [
                                      const Text('Unmitigated Exposure', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text('₹${unmitTotal.toInt()}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  Container(width: 1, height: 28, color: const Color(0xFF1E293B)),
                                  Column(
                                    children: [
                                      const Text('With Texora AI', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text('₹${mitTotal.toInt()}', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  Container(width: 1, height: 28, color: const Color(0xFF1E293B)),
                                  Column(
                                    children: [
                                      const Text('Estimated Risk Avoided', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text('₹${saved.toInt()}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Data Provenance Transparency Notice
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0F1D),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, color: Color(0xFF64748B), size: 14),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'DATA PROVENANCE: Downtime & cost metrics are calculated deterministically via Factory Digital Twin models. Operational figures are illustrative estimates, not commercial warranty commitments.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String label,
    required String value,
    required String subtitle,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500),
              ),
              Icon(icon, color: accentColor, size: 14),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accentColor,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
          ),
        ],
      ),
    );
  }
}
