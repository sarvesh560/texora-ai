import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/services/api_service.dart';
import '../widgets/design_system/design_system.dart';

class ReportsAnalyticsScreen extends StatefulWidget {
  final ApiService? apiService;

  const ReportsAnalyticsScreen({super.key, this.apiService});

  @override
  State<ReportsAnalyticsScreen> createState() => _ReportsAnalyticsScreenState();
}

class _ReportsAnalyticsScreenState extends State<ReportsAnalyticsScreen> {
  late final ApiService _apiService;

  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  String _selectedCategory = 'factory_overview';
  String _selectedRange = 'today';
  String _searchQuery = '';

  Map<String, dynamic> _reportData = {};

  final List<Map<String, String>> _categories = [
    {'key': 'factory_overview', 'label': 'Factory Overview', 'icon': 'dashboard'},
    {'key': 'machine_health', 'label': 'Machine Health', 'icon': 'precision_manufacturing'},
    {'key': 'quality', 'label': 'Quality & QA', 'icon': 'verified'},
    {'key': 'inventory', 'label': 'Spare Parts Inventory', 'icon': 'inventory_2'},
    {'key': 'energy', 'label': 'Energy & Power', 'icon': 'bolt'},
  ];

  final List<Map<String, String>> _ranges = [
    {'key': 'today', 'label': 'Today'},
    {'key': '7d', 'label': 'Past 7 Days'},
    {'key': '30d', 'label': 'Past 30 Days'},
    {'key': 'all', 'label': 'All Time'},
  ];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadReport();
  }

  Future<void> _loadReport({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final res = await _apiService.getReportsOverview(
        category: _selectedCategory,
        range: _selectedRange,
      );

      if (mounted) {
        setState(() {
          _reportData = res ?? {};
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to generate report: $e';
        });
      }
    }
  }

  Future<void> _handleCsvExport() async {
    setState(() => _isExporting = true);

    try {
      final csvText = await _apiService.fetchReportsCsv(
        category: _selectedCategory,
        range: _selectedRange,
      );

      if (!mounted) return;
      setState(() => _isExporting = false);

      if (csvText == null || csvText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to download CSV: Empty response from server.'),
            backgroundColor: TexoraColors.critical,
          ),
        );
        return;
      }

      // Show Export Confirmation Dialog with CSV content and copy action
      final lines = csvText.trim().split('\n');
      final filename = 'texora_${_selectedCategory}_${_selectedRange}_report.csv';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: TexoraColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
            side: const BorderSide(color: TexoraColors.cardBorder),
          ),
          title: Row(
            children: [
              const Icon(Icons.file_download_done_rounded, color: TexoraColors.success, size: 24),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'CSV Export Generated',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: TexoraColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TexoraColors.workspaceBg,
                    borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                    border: Border.all(color: TexoraColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, color: TexoraColors.primaryBlue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          filename,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: TexoraColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${lines.length} lines • ${(csvText.length / 1024).toStringAsFixed(1)} KB',
                        style: const TextStyle(fontSize: 11, color: TexoraColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Preview Data (First 8 Rows):',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: TexoraColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: Text(
                          lines.take(8).join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close', style: TextStyle(color: TexoraColors.textSecondary)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy to Clipboard'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TexoraColors.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                ),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: csvText));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Report CSV copied to clipboard ($filename).'),
                    backgroundColor: TexoraColors.success,
                  ),
                );
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export error: $e'),
          backgroundColor: TexoraColors.critical,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Operational Reports & Analytics',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: TexoraColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _reportData['category_label'] ?? 'Enterprise audit logs, performance metrics, and database-backed exports.',
                        style: const TextStyle(fontSize: 12, color: TexoraColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 10,
                  children: [
                    TexoraActionButton(
                      label: 'Refresh',
                      icon: Icons.refresh_rounded,
                      variant: TexoraButtonVariant.outline,
                      onPressed: () => _loadReport(),
                    ),
                    ElevatedButton.icon(
                      icon: _isExporting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.file_download_outlined, size: 16),
                      label: Text(_isExporting ? 'Exporting...' : 'Export CSV'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TexoraColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                        ),
                      ),
                      onPressed: _isExporting ? null : _handleCsvExport,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Category Tabs & Range Filter Bar
            TexoraCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'REPORT CATEGORY:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: TexoraColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _categories.map((cat) {
                              final isSel = _selectedCategory == cat['key'];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  onTap: () {
                                    if (_selectedCategory != cat['key']) {
                                      setState(() => _selectedCategory = cat['key']!);
                                      _loadReport();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: isSel ? const Color(0xFFEFF6FF) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(TexoraSpacing.radiusSm),
                                      border: Border.all(
                                        color: isSel ? TexoraColors.primaryBlue : TexoraColors.cardBorder,
                                      ),
                                    ),
                                    child: Text(
                                      cat['label']!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                        color: isSel ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: TexoraColors.cardBorder, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'TIMEFRAME:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: TexoraColors.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ..._ranges.map((rng) {
                            final isSel = _selectedRange == rng['key'];
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(rng['label']!),
                                selected: isSel,
                                selectedColor: const Color(0xFFEFF6FF),
                                backgroundColor: TexoraColors.workspaceBg,
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                  color: isSel ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
                                  side: BorderSide(
                                    color: isSel ? TexoraColors.primaryBlue : TexoraColors.cardBorder,
                                  ),
                                ),
                                onSelected: (sel) {
                                  if (sel && _selectedRange != rng['key']) {
                                    setState(() => _selectedRange = rng['key']!);
                                    _loadReport();
                                  }
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                      if (_reportData['generated_at'] != null)
                        Text(
                          'Synced: ${_reportData['generated_at']}',
                          style: const TextStyle(fontSize: 11, color: TexoraColors.textMuted),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Content Area: Loading or Error or KPIs + Table
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              TexoraCard(
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: TexoraColors.critical, size: 36),
                      const SizedBox(height: 10),
                      Text(_errorMessage!, style: const TextStyle(color: TexoraColors.textSecondary)),
                      const SizedBox(height: 14),
                      TexoraActionButton(
                        label: 'Retry Loading',
                        icon: Icons.refresh_rounded,
                        onPressed: () => _loadReport(),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // 4 Dynamic KPI Cards from backend response
              _buildKpisGrid(),
              const SizedBox(height: 18),

              // Report Data Table Card with Search
              _buildDataTableCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKpisGrid() {
    final kpis = (_reportData['kpis'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (kpis.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w < 600 ? 1 : (w < 1100 ? 2 : 4);
        final cardW = (w - (cols - 1) * 16) / cols;

        return Wrap(
          spacing: 16,
          runSpacing: 14,
          children: kpis.map((kpi) {
            return SizedBox(
              width: cardW,
              child: TexoraKpiCard(
                label: (kpi['label'] ?? '').toString().toUpperCase(),
                value: (kpi['value'] ?? '-').toString(),
                subtitle: (kpi['subtext'] ?? '').toString(),
                icon: Icons.insights_rounded,
                iconColor: TexoraColors.primaryBlue,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDataTableCard() {
    final columns = (_reportData['columns'] as List?)?.cast<String>() ?? [];
    final rowKeys = (_reportData['row_keys'] as List?)?.cast<String>() ?? [];
    final rawRows = (_reportData['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final filteredRows = rawRows.where((row) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return row.values.any((val) => val.toString().toLowerCase().contains(q));
    }).toList();

    return TexoraCard(
      title: 'Detailed Records (${filteredRows.length} of ${rawRows.length})',
      subtitle: 'Verified database-backed records matching applied filters.',
      trailing: SizedBox(
        width: 220,
        height: 34,
        child: TextField(
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Filter records...',
            hintStyle: const TextStyle(fontSize: 12, color: TexoraColors.textMuted),
            prefixIcon: const Icon(Icons.search, size: 16, color: TexoraColors.textMuted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
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
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
      ),
      child: filteredRows.isEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: const [
                  Icon(Icons.folder_open_rounded, color: TexoraColors.textMuted, size: 40),
                  SizedBox(height: 10),
                  Text(
                    'No records found matching the criteria.',
                    style: TextStyle(color: TexoraColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 46,
                dataRowMaxHeight: 52,
                headingTextStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: TexoraColors.textMuted,
                  letterSpacing: 0.4,
                ),
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                columns: columns.map((col) => DataColumn(label: Text(col))).toList(),
                rows: filteredRows.map((row) {
                  return DataRow(
                    cells: rowKeys.map((key) {
                      final val = row[key]?.toString() ?? '-';
                      final isStatus = key.toLowerCase().contains('status');

                      if (isStatus) {
                        final vUpper = val.toUpperCase();
                        final isGood = vUpper == 'PASSED' || vUpper == 'NORMAL' || vUpper == 'OPERATIONAL' || vUpper == 'COMPLETED';
                        final isWarn = vUpper.contains('CONDITIONAL') || vUpper.contains('WARNING') || vUpper.contains('LOW');
                        return DataCell(
                          TexoraStatusBadge(
                            label: val,
                            variant: isGood
                                ? TexoraBadgeVariant.running
                                : (isWarn ? TexoraBadgeVariant.attention : TexoraBadgeVariant.critical),
                          ),
                        );
                      }

                      return DataCell(
                        Text(
                          val,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: key == rowKeys.first ? FontWeight.w600 : FontWeight.w400,
                            color: key == rowKeys.first ? TexoraColors.textPrimary : TexoraColors.textSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
    );
  }
}
