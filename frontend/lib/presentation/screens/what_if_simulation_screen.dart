import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/digital_twin_models.dart';
import '../../data/services/api_service.dart';
import '../widgets/metric_card.dart';

class WhatIfSimulationScreen extends StatefulWidget {
  final String? initialMachineCode;

  const WhatIfSimulationScreen({
    super.key,
    this.initialMachineCode,
  });

  @override
  State<WhatIfSimulationScreen> createState() => _WhatIfSimulationScreenState();
}

class _WhatIfSimulationScreenState extends State<WhatIfSimulationScreen> {
  final ApiService _apiService = ApiService();

  // Scenario Configuration Inputs
  final TextEditingController _scenarioNameController =
      TextEditingController(text: 'Hypothetical Loom Failure & Strategy Evaluation');
  List<String> _selectedMachineCodes = ['WEV-AJ-02'];
  double _failureDurationHours = 4.0;
  double _repairDurationHours = 2.5;
  double _capacityReductionPct = 100.0;
  String _sparePartsAvailability = 'FULL';
  int _techniciansAvailable = 2;
  double _demandVariationPct = 0.0;
  final String _selectedStrategy = 'ALL_COMPARISON';

  // State Management
  bool _isSimulating = false;
  bool _isLoadingAi = false;
  bool _isStaleResults = false;
  String? _errorMessage;
  WhatIfScenarioModel? _activeScenario;
  SimulationRunModel? _activeRun;
  AIStrategyExplanationModel? _aiExplanation;
  List<DemoScenarioModel> _demoScenarios = [];

  // Playback Mode State
  int _currentPlaybackIndex = 0;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialMachineCode != null && widget.initialMachineCode!.isNotEmpty) {
      _selectedMachineCodes = [widget.initialMachineCode!];
      _scenarioNameController.text = 'What-If Outage Analysis on ${widget.initialMachineCode}';
    }
    _loadDemoScenarios();
    _executeSimulation();
  }

  @override
  void dispose() {
    _scenarioNameController.dispose();
    _playbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDemoScenarios() async {
    final demos = await _apiService.fetchWhatIfDemoScenarios();
    if (mounted) {
      setState(() {
        _demoScenarios = demos;
      });
    }
  }

  Future<void> _executeSimulation() async {
    setState(() {
      _isSimulating = true;
      _errorMessage = null;
    });

    try {
      final payload = {
        'name': _scenarioNameController.text.trim().isEmpty
            ? 'Hypothetical Scenario on ${_selectedMachineCodes.join(', ')}'
            : _scenarioNameController.text.trim(),
        'description': 'Interactive What-If simulation run via Operations Studio',
        'scenario_type': _selectedMachineCodes.length > 1 ? 'MULTI_MACHINE_FAILURE' : 'SINGLE_MACHINE_FAILURE',
        'failure_duration_hours': _failureDurationHours,
        'repair_duration_hours': _repairDurationHours,
        'capacity_reduction_pct': _capacityReductionPct,
        'spare_parts_availability': _sparePartsAvailability,
        'technicians_available': _techniciansAvailable,
        'demand_variation_pct': _demandVariationPct,
        'shift_duration_hours': 8.0,
        'selected_strategy': _selectedStrategy,
        'machine_codes': _selectedMachineCodes,
        'failure_type': 'SIMULATED_BEARING_DRIVE_FAULT',
      };

      final res = await _apiService.createWhatIfScenario(payload);
      if (res['status'] == 'success' && res['scenario'] != null) {
        final scenario = WhatIfScenarioModel.fromJson(res['scenario'] as Map<String, dynamic>);
        final run = scenario.latestRun;

        if (mounted) {
          setState(() {
            _activeScenario = scenario;
            _activeRun = run;
            _isSimulating = false;
            _isStaleResults = false;
            _currentPlaybackIndex = 0;
            _aiExplanation = null;
          });
          // Auto-fetch AI explanation
          _requestAiExplanation(scenario.scenarioId);
        }
      } else {
        if (mounted) {
          setState(() {
            _isSimulating = false;
            _errorMessage = res['message'] ?? 'Failed to execute What-If simulation';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSimulating = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _loadAndRunDemo(String demoCode) async {
    setState(() {
      _isSimulating = true;
      _errorMessage = null;
    });

    final res = await _apiService.loadWhatIfDemoScenario(demoCode);
    if (res['status'] == 'success' && res['scenario'] != null) {
      final scenario = WhatIfScenarioModel.fromJson(res['scenario'] as Map<String, dynamic>);
      final run = res['run'] != null
          ? SimulationRunModel.fromJson(res['run'] as Map<String, dynamic>)
          : scenario.latestRun;

      if (mounted) {
        setState(() {
          _activeScenario = scenario;
          _activeRun = run;
          _scenarioNameController.text = scenario.name;
          _failureDurationHours = scenario.failureDurationHours;
          _repairDurationHours = scenario.repairDurationHours;
          _capacityReductionPct = scenario.capacityReductionPct;
          _sparePartsAvailability = scenario.sparePartsAvailability;
          _techniciansAvailable = scenario.techniciansAvailable;
          _demandVariationPct = scenario.demandVariationPct;
          _selectedMachineCodes = scenario.machineChanges.map((m) => m['machine_code'].toString()).toList();
          if (_selectedMachineCodes.isEmpty) _selectedMachineCodes = ['WEV-AJ-02'];
          _isSimulating = false;
          _isStaleResults = false;
          _currentPlaybackIndex = 0;
          _aiExplanation = null;
        });
        _requestAiExplanation(scenario.scenarioId);
      }
    } else {
      if (mounted) {
        setState(() {
          _isSimulating = false;
          _errorMessage = res['message'] ?? 'Failed to load demo';
        });
      }
    }
  }

  Future<void> _requestAiExplanation(String scenarioId) async {
    setState(() {
      _isLoadingAi = true;
    });

    final exp = await _apiService.requestAIStrategyExplanation(scenarioId);
    if (mounted) {
      setState(() {
        _aiExplanation = exp;
        _isLoadingAi = false;
      });
    }
  }

  void _togglePlayback() {
    final events = _activeRun?.result?.timelineEvents ?? [];
    if (events.isEmpty) return;

    if (_isPlaying) {
      _playbackTimer?.cancel();
      setState(() {
        _isPlaying = false;
      });
    } else {
      setState(() {
        _isPlaying = true;
      });
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
        if (_currentPlaybackIndex < events.length - 1) {
          setState(() {
            _currentPlaybackIndex++;
          });
        } else {
          timer.cancel();
          setState(() {
            _isPlaying = false;
          });
        }
      });
    }
  }

  void _resetPlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _currentPlaybackIndex = 0;
      _isPlaying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D), // Dark Navy Command Center Background
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Panel: Scenario Configuration Levers
                Container(
                  width: 380,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: _buildConfigurationPanel(),
                ),

                // Right Panel: Results, Strategy Comparison & AI Reasoning
                Expanded(
                  child: _isSimulating
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage != null
                          ? _buildErrorView()
                          : _buildResultsDashboard(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withAlpha(38),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryBlueLight.withAlpha(100)),
                  ),
                  child: const Icon(
                    Icons.science_rounded,
                    color: AppColors.primaryBlueLight,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          const Text(
                            'What-If Simulation Studio & AI Strategy Advisor',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: const Text(
                              'DETERMINISTIC SIMULATION ISOLATION GUARANTEED',
                              style: TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Evaluate hypothetical machine disruptions, capacity bottlenecks, and multi-agent recovery strategies without altering live operational data.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Demo Scenarios Quick Actions
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('BENCHMARK SCENARIOS:', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (_demoScenarios.isNotEmpty)
                  ..._demoScenarios.map((demo) {
                    Color btnColor = demo.demoCode == 'DEMO_A'
                        ? const Color(0xFF38BDF8)
                        : (demo.demoCode == 'DEMO_B' ? const Color(0xFFF59E0B) : const Color(0xFFA855F7));
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton(
                        onPressed: () => _loadAndRunDemo(demo.demoCode),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: btnColor,
                          side: BorderSide(color: btnColor.withAlpha(180)),
                        ),
                        child: Text(demo.title.split('—').first.trim()),
                      ),
                    );
                  })
                else ...[
                  OutlinedButton(
                    onPressed: () => _loadAndRunDemo('DEMO_A'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0xFF0284C7)),
                    ),
                    child: const Text('Demo A: Single Loom'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _loadAndRunDemo('DEMO_B'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF59E0B),
                      side: const BorderSide(color: Color(0xFFD97706)),
                    ),
                    child: const Text('Demo B: Weaving Cluster'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _loadAndRunDemo('DEMO_C'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFA855F7),
                      side: const BorderSide(color: Color(0xFF9333EA)),
                    ),
                    child: const Text('Demo C: Spinning Shortage'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationPanel() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SCENARIO CONFIGURATION',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            if (_activeScenario != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _activeScenario!.scenarioId,
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Scenario Title Input
        TextField(
          controller: _scenarioNameController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          onChanged: (_) {
            setState(() {
              _isStaleResults = true;
            });
          },
          decoration: InputDecoration(
            labelText: 'Scenario Name',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Target Machine Multi-Select Chips
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                'Target Disrupted Machines',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_selectedMachineCodes.length} selected',
              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildDepartmentMachineGroup('Spinning (SPN)', ['SPN-CARD-01', 'SPN-DRAW-01', 'SPN-RS-01', 'SPN-RS-02', 'SPN-RS-03', 'SPN-WND-01', 'SPN-WND-02']),
        _buildDepartmentMachineGroup('Weaving Shed (WEV)', ['WEV-AJ-01', 'WEV-AJ-02', 'WEV-AJ-03', 'WEV-AJ-04', 'WEV-RAP-01', 'WEV-WARP-01']),
        _buildDepartmentMachineGroup('Knitting Div (KNT)', ['KNT-CS-01', 'KNT-CS-02', 'KNT-DBL-01', 'KNT-FLAT-01']),
        _buildDepartmentMachineGroup('Dyeing & Proc (DYE)', ['DYE-PKG-01', 'DYE-SF-01', 'DYE-SF-02', 'DYE-THIES-01']),
        _buildDepartmentMachineGroup('Finishing (FIN)', ['FIN-COMP-01', 'FIN-INSP-01', 'FIN-INSP-02', 'FIN-STNT-01']),
        const SizedBox(height: 16),

        // Failure Duration Slider
        _buildSliderWithLabel(
          label: 'Hypothetical Failure Duration',
          value: _failureDurationHours,
          min: 1.0,
          max: 24.0,
          unit: 'hours',
          onChanged: (val) {
            setState(() {
              _isStaleResults = true;
              _failureDurationHours = val;
              if (_repairDurationHours > val) _repairDurationHours = val;
            });
          },
        ),

        // Repair Duration Slider
        _buildSliderWithLabel(
          label: 'Estimated Repair Duration',
          value: _repairDurationHours,
          min: 0.5,
          max: _failureDurationHours,
          unit: 'hours',
          onChanged: (val) {
            setState(() {
              _isStaleResults = true;
              _repairDurationHours = val;
            });
          },
        ),

        // Capacity Reduction Slider
        _buildSliderWithLabel(
          label: 'Machine Capacity Loss',
          value: _capacityReductionPct,
          min: 10.0,
          max: 100.0,
          unit: '%',
          onChanged: (val) {
            setState(() {
              _isStaleResults = true;
              _capacityReductionPct = val;
            });
          },
        ),

        // Spare Parts Availability Dropdown
        const Text(
          'Warehouse Spare Parts Stock',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _sparePartsAvailability,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'FULL', child: Text('Full Stock Available (Optimal)')),
                DropdownMenuItem(value: 'PARTIAL', child: Text('Partial Stock (Priority Allocation)')),
                DropdownMenuItem(value: 'UNAVAILABLE', child: Text('Unavailable / Stockout (Infeasible)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _isStaleResults = true;
                    _sparePartsAvailability = val;
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Available Technicians Counter
        const Text(
          'Available Maintenance Technicians',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          children: [1, 2, 3, 4].map((count) {
            final isSelected = _techniciansAvailable == count;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isStaleResults = true;
                      _techniciansAvailable = count;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryBlue : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppColors.primaryBlueLight : const Color(0xFF334155),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$count Tech${count > 1 ? 's' : ''}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // Run Simulation Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: _isSimulating ? null : _executeSimulation,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text(
              'RUN DETERMINISTIC SIMULATION',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDepartmentMachineGroup(String deptTitle, List<String> codes) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            deptTitle,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: codes.map((code) {
              final isSelected = _selectedMachineCodes.contains(code);
              return FilterChip(
                selected: isSelected,
                label: Text(code),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: const Color(0xFF1E293B),
                selectedColor: AppColors.errorRed.withAlpha(200),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: isSelected ? AppColors.errorRed : const Color(0xFF334155),
                  ),
                ),
                onSelected: (selected) {
                  setState(() {
                    _isStaleResults = true;
                    if (selected) {
                      _selectedMachineCodes.add(code);
                    } else if (_selectedMachineCodes.length > 1) {
                      _selectedMachineCodes.remove(code);
                    }
                    if (_scenarioNameController.text.startsWith('What-If') || _scenarioNameController.text.startsWith('Hypothetical')) {
                      _scenarioNameController.text = 'What-If Analysis on ${_selectedMachineCodes.join(', ')}';
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderWithLabel({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(
              '${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) * 2).toInt().clamp(1, 100),
          activeColor: AppColors.primaryBlueLight,
          inactiveColor: const Color(0xFF1E293B),
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildResultsDashboard() {
    final result = _activeRun?.result;
    final evals = _activeRun?.strategyEvaluations ?? [];
    final events = result?.timelineEvents ?? [];

    if (result == null) {
      return const Center(child: Text('No simulation result generated.', style: TextStyle(color: Colors.white)));
    }

    final activeTargetCodes = _activeScenario?.machineChanges.map((m) => m['machine_code'].toString()).toList() ?? _selectedMachineCodes;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Stale Input Warning Banner
        if (_isStaleResults)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF78350F),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'INPUTS MODIFIED: Displayed simulation reflects previous run on [${activeTargetCodes.join(', ')}]. Click RUN DETERMINISTIC SIMULATION to re-compute.',
                    style: const TextStyle(color: Color(0xFFFEF3C7), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                ElevatedButton(
                  onPressed: _executeSimulation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: const Text('RE-RUN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ],
            ),
          ),

        // Production Impact Metrics Row (Consistent Dark Styling Applied)
        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: 'Lost Machine Hours',
                value: '${result.lostMachineOperatingHours}h',
                icon: Icons.timer_off_rounded,
                accentColor: AppColors.errorRed,
                backgroundColor: const Color(0xFF0F172A),
                borderColor: const Color(0xFF1E293B),
                titleColor: const Color(0xFF94A3B8),
                valueColor: Colors.white,
                subtitleColor: const Color(0xFF64748B),
                subtitle: '${activeTargetCodes.length} Machine(s) Disrupted',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                title: 'Department Capacity Drop',
                value: '${result.capacityReductionPct.toStringAsFixed(1)}%',
                icon: Icons.trending_down_rounded,
                accentColor: AppColors.warningOrange,
                backgroundColor: const Color(0xFF0F172A),
                borderColor: const Color(0xFF1E293B),
                titleColor: const Color(0xFF94A3B8),
                valueColor: Colors.white,
                subtitleColor: const Color(0xFF64748B),
                subtitle: 'Bottleneck: ${result.bottleneckDepartment} Dept',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                title: 'Unmitigated Output Loss',
                value: '${result.estimatedOutputLoss['METERS'] ?? result.estimatedOutputLoss['KG'] ?? 0.0} ${result.bottleneckDepartment == 'SPN' || result.bottleneckDepartment == 'KNT' ? 'kg' : 'm'}',
                icon: Icons.inventory_rounded,
                accentColor: const Color(0xFFF97316),
                backgroundColor: const Color(0xFF0F172A),
                borderColor: const Color(0xFF1E293B),
                titleColor: const Color(0xFF94A3B8),
                valueColor: Colors.white,
                subtitleColor: const Color(0xFF64748B),
                subtitle: 'Unmitigated Baseline Loss',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                title: 'Impacted Production Orders',
                value: '${result.potentialOrderDelays.length} Orders',
                icon: Icons.assignment_late_rounded,
                accentColor: result.potentialOrderDelays.isNotEmpty ? AppColors.errorRed : AppColors.successGreen,
                backgroundColor: const Color(0xFF0F172A),
                borderColor: const Color(0xFF1E293B),
                titleColor: const Color(0xFF94A3B8),
                valueColor: Colors.white,
                subtitleColor: const Color(0xFF64748B),
                subtitle: 'Delivery Risk Assessed',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Visual Simulation Playback Timeline
        if (events.isNotEmpty) ...[
          _buildSimulationPlaybackSection(events, activeTargetCodes),
          const SizedBox(height: 24),
        ],

        // 3 Recovery Strategies Comparison
        _buildSectionHeader('RECOVERY STRATEGIES EVALUATION (A vs B vs C)', Icons.compare_arrows_rounded),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: evals.map((evaluation) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _buildStrategyCard(evaluation, result),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // AI Strategy Advisor Reasoning Panel
        _buildAiAdvisorPanel(),
      ],
    );
  }

  Widget _buildSimulationPlaybackSection(List<dynamic> events, List<String> activeTargetCodes) {
    if (_currentPlaybackIndex >= events.length) _currentPlaybackIndex = 0;
    final currentFrame = events[_currentPlaybackIndex] as Map<String, dynamic>;
    final frameLabel = currentFrame['timestamp_label'] ?? 'T + 00:00h';
    final frameEvents = currentFrame['events'] as List? ?? [];
    final machineStates = currentFrame['machine_states'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.movie_filter_rounded, color: Color(0xFF38BDF8), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Visual Simulation Playback Mode',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      frameLabel,
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _resetPlayback,
                    icon: const Icon(Icons.replay_rounded, color: Color(0xFF94A3B8)),
                    tooltip: 'Reset to T+00:00',
                  ),
                  IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
                    tooltip: _isPlaying ? 'Pause' : 'Play Timeline',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Timeline Slider
          Slider(
            value: _currentPlaybackIndex.toDouble(),
            min: 0.0,
            max: (events.length - 1).toDouble().clamp(0.0, 100.0),
            divisions: events.length > 1 ? events.length - 1 : 1,
            activeColor: const Color(0xFF38BDF8),
            inactiveColor: const Color(0xFF1E293B),
            onChanged: (val) {
              setState(() {
                _currentPlaybackIndex = val.toInt();
              });
            },
          ),

          // Event Marker Banner
          if (frameEvents.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_note_rounded, color: Color(0xFFF59E0B), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${frameEvents[0]['title']}: ${frameEvents[0]['description']}',
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Visual Machine State Transitions Matrix with Provenance Distinction
          if (machineStates.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: const [
                Text(
                  'TIMELINE ASSET STATE TRANSITIONS:',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Distinguishing Hypothetical Failures vs Operational Baseline Incidents',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontStyle: FontStyle.italic),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: machineStates.entries.map((entry) {
                final code = entry.key;
                final state = entry.value.toString();
                final isHypothetical = activeTargetCodes.contains(code);
                final isBaselineIncident = code == 'WEV-AJ-02' && !isHypothetical;

                Color chipColor = AppColors.successGreen;
                if (state == 'CRITICAL') chipColor = AppColors.errorRed;
                if (state == 'WARNING') chipColor = AppColors.warningOrange;
                if (state == 'UNDER_MAINTENANCE') chipColor = const Color(0xFF38BDF8);
                if (state == 'UNKNOWN') chipColor = const Color(0xFF94A3B8);

                String provenanceTag = '';
                if (isHypothetical) {
                  provenanceTag = ' [HYPOTHETICAL]';
                } else if (isBaselineIncident) {
                  provenanceTag = ' [BASELINE INCIDENT]';
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: chipColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: chipColor.withAlpha(100)),
                  ),
                  child: Text(
                    '$code: $state$provenanceTag',
                    style: TextStyle(color: chipColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStrategyCard(RecoveryStrategyEvaluationModel eval, SimulationResultModel result) {
    Color rankColor = eval.rank == 1 ? AppColors.successGreen : (eval.isFeasible ? const Color(0xFF38BDF8) : AppColors.errorRed);

    String rankBadgeText = 'RANK #${eval.rank}';
    if (eval.isTied) {
      rankBadgeText = 'RANK #${eval.rank} (TIED)';
    } else if (eval.rank == 1) {
      rankBadgeText = 'RANK #1 • RECOMMENDED';
    }

    String viabilityLabel = 'HIGH EFFECTIVENESS';
    Color viabilityColor = const Color(0xFF38BDF8);
    if (eval.effectivenessLevel == 'TEMPORARY_WORKAROUND') {
      viabilityLabel = 'TEMPORARY WORKAROUND (0% ASSET RECOVERY)';
      viabilityColor = const Color(0xFFF59E0B);
    } else if (!eval.isFeasible) {
      viabilityLabel = 'INFEASIBLE';
      viabilityColor = AppColors.errorRed;
    }

    final formula = eval.estimatedCost['formula_breakdown']?.toString() ?? 'Standard cost model';
    final totalCost = (eval.estimatedCost['total_estimated_cost_inr'] as num?)?.toInt() ?? 
        ((eval.estimatedCost['production_loss_penalty_inr'] ?? 0).toInt() + (eval.estimatedCost['labor_cost_inr'] ?? 0).toInt() + (eval.estimatedCost['spare_parts_cost_inr'] ?? 0).toInt());

    final unit = result.bottleneckDepartment == 'SPN' || result.bottleneckDepartment == 'KNT' ? 'kg' : 'm';
    final unmitigatedVal = eval.unmitigatedBaselineLoss['METERS'] ?? eval.unmitigatedBaselineLoss['KG'] ?? result.estimatedOutputLoss['METERS'] ?? result.estimatedOutputLoss['KG'] ?? 0.0;
    final netLossVal = eval.estimatedOutputLoss['METERS'] ?? eval.estimatedOutputLoss['KG'] ?? 0.0;
    final volumeSavedVal = eval.volumeProtectedUnits['METERS'] ?? eval.volumeProtectedUnits['KG'] ?? (unmitigatedVal - netLossVal > 0 ? unmitigatedVal - netLossVal : 0.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: eval.rank == 1 ? AppColors.successGreen.withAlpha(180) : const Color(0xFF1E293B),
          width: eval.rank == 1 ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Rank and Feasibility / Viability Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: rankColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: rankColor.withAlpha(100)),
                ),
                child: Text(
                  rankBadgeText,
                  style: TextStyle(color: rankColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: eval.isFeasible ? AppColors.successGreen.withAlpha(30) : AppColors.errorRed.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  eval.isFeasible ? 'FEASIBLE' : 'INFEASIBLE',
                  style: TextStyle(
                    color: eval.isFeasible ? AppColors.successGreen : AppColors.errorRed,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Strategy Viability Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: viabilityColor.withAlpha(25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              viabilityLabel,
              style: TextStyle(color: viabilityColor, fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),

          Text(
            eval.strategyName,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          if (eval.isTied && eval.tieBreakerNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              eval.tieBreakerNote,
              style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 10, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 12),

          // Core Metrics Summary: Unmitigated vs Post-Recovery Mitigated Output
          _buildStrategyMetricRow('Est. Downtime', '${eval.estimatedDowntimeHours}h'),
          _buildStrategyMetricRow('Capacity Recovered', '${eval.capacityRecoveredPct.toInt()}%'),
          _buildStrategyMetricRow('Unmitigated Baseline Loss', '$unmitigatedVal $unit'),
          _buildStrategyMetricRow('Post-Strategy Net Loss', '$netLossVal $unit'),
          _buildStrategyMetricRow('Protected Output Volume', '+$volumeSavedVal $unit (Saved)', isHighlight: true),
          _buildStrategyMetricRow('Est. Total Cost', '₹$totalCost INR'),
          const SizedBox(height: 8),

          // Transparent Formula Box
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COST FORMULA & ASSUMPTIONS:',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  formula,
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          const Divider(color: Color(0xFF1E293B)),
          const SizedBox(height: 8),

          // Pros
          const Text('ADVANTAGES:', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
          ...eval.pros.map((p) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 12),
                    const SizedBox(width: 4),
                    Expanded(child: Text(p, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10))),
                  ],
                ),
              )),
          const SizedBox(height: 8),

          // Cons
          const Text('TRADE-OFFS & LIMITS:', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold)),
          ...eval.cons.map((c) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 12),
                    const SizedBox(width: 4),
                    Expanded(child: Text(c, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStrategyMetricRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          Text(
            value,
            style: TextStyle(
              color: isHighlight ? const Color(0xFF34D399) : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiAdvisorPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology_rounded, color: Color(0xFFA855F7), size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'AI Operations Strategy Advisor',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (_aiExplanation != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _aiExplanation!.isLiveGemini ? const Color(0xFF064E3B) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _aiExplanation!.isLiveGemini ? const Color(0xFF059669) : const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _aiExplanation!.isLiveGemini ? Icons.auto_awesome_rounded : Icons.code_rounded,
                        color: _aiExplanation!.isLiveGemini ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _aiExplanation!.isLiveGemini ? 'LIVE GEMINI INFERENCE (${_aiExplanation!.modelName})' : 'LOCAL DETERMINISTIC ADVISOR',
                        style: TextStyle(
                          color: _aiExplanation!.isLiveGemini ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (_isLoadingAi)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(width: 12),
                    Text('Synthesizing executive AI strategy explanation...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  ],
                ),
              ),
            )
          else if (_aiExplanation != null) ...[
            // Executive Summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _aiExplanation!.executiveSummary,
                style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 16),

            // Rationale
            const Text(
              'RECOMMENDATION RATIONALE & EVIDENCE CORRELATION',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            Text(
              _aiExplanation!.recommendationRationale,
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 16),

            // Operational Risks
            const Text(
              'OPERATIONAL RISKS & ASSUMPTIONS',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            ..._aiExplanation!.operationalRisks.map((risk) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(risk, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF38BDF8), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.errorRed, size: 48),
          const SizedBox(height: 12),
          Text(_errorMessage ?? 'Simulation failed', style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _executeSimulation, child: const Text('Retry Simulation')),
        ],
      ),
    );
  }
}
