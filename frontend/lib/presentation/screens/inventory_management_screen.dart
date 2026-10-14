import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../core/utils/numeric_parser.dart';
import '../../data/services/api_service.dart';
import '../widgets/design_system/design_system.dart';

class InventoryManagementScreen extends StatefulWidget {
  final ApiService? apiService;

  const InventoryManagementScreen({super.key, this.apiService});

  @override
  State<InventoryManagementScreen> createState() => _InventoryManagementScreenState();
}

class _InventoryManagementScreenState extends State<InventoryManagementScreen> {
  late final ApiService _apiService;

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _transactions = [];
  String _selectedCategoryFilter = 'ALL';
  String _searchQuery = '';
  Map<String, dynamic>? _selectedItem;

  static const _filterKeys = ['ALL', 'SPARE_PARTS', 'RAW_MATERIAL', 'CHEMICALS', 'CONSUMABLES'];
  static const _filterLabels = ['All SKUs', 'Spare Parts', 'Raw Materials', 'Dyes & Chemicals', 'Consumables'];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadInventoryData();
  }

  Future<void> _loadInventoryData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _apiService.getInventorySummary(),
        _apiService.getInventoryItems(category: _selectedCategoryFilter),
        _apiService.getInventoryTransactions(),
      ]);

      if (mounted) {
        setState(() {
          _summary = results[0] as Map<String, dynamic>? ?? {};
          _items = results[1] as List<Map<String, dynamic>>? ?? [];
          _transactions = results[2] as List<Map<String, dynamic>>? ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load inventory data: $e';
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
              onPressed: () => _loadInventoryData(),
            ),
          ],
        ),
      );
    }

    final totalItems = parseIntWithFallback(
      _summary['total_items'],
      _items.length,
      fieldName: 'total_items',
    );
    final totalVal = parseDoubleWithFallback(
      _summary['total_inventory_value_inr'] ?? _summary['total_inventory_valuation'],
      384000.0,
      fieldName: 'total_inventory_value_inr',
    );
    final lowStock = parseIntWithFallback(
      _summary['low_stock_count'],
      2,
      fieldName: 'low_stock_count',
    );
    final criticalCount = parseIntWithFallback(
      _summary['critical_shortage_count'] ?? _summary['critical_outage_count'],
      0,
      fieldName: 'critical_shortage_count',
    );
    final recommendations = (_summary['ai_recommendations'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final filtered = _items.where((it) {
      final code = (it['item_code'] ?? '').toString().toLowerCase();
      final name = (it['name'] ?? '').toString().toLowerCase();
      final cat = (it['category'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return code.contains(q) || name.contains(q) || cat.contains(q);
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
                  // Screen Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Warehouse Inventory & Spare Parts',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: TexoraColors.textPrimary,
                                letterSpacing: -0.4,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Real-time plant stock, automated AI reorder requisitions, and maintenance reservation tracking.',
                              style: TextStyle(fontSize: 12, color: TexoraColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      TexoraActionButton(
                        label: 'Sync Warehouse',
                        icon: Icons.sync_rounded,
                        variant: TexoraButtonVariant.outline,
                        onPressed: () => _loadInventoryData(),
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
                          label: 'TOTAL CATALOGUED SKUS',
                          value: '$totalItems Items',
                          subtitle: 'Active textile parts & raw materials',
                          icon: Icons.inventory_2_rounded,
                          iconColor: TexoraColors.primaryBlue,
                        ),
                        TexoraKpiCard(
                          label: 'INVENTORY VALUATION',
                          value: '₹${totalVal.toInt()}',
                          subtitle: 'Current book value in stock',
                          icon: Icons.account_balance_wallet_rounded,
                          iconColor: const Color(0xFF0D9488),
                        ),
                        TexoraKpiCard(
                          label: 'BELOW REORDER POINT',
                          value: '$lowStock SKUs',
                          subtitle: 'Reorder requisitions generated',
                          isPositive: lowStock == 0,
                          icon: Icons.low_priority_rounded,
                          iconColor: TexoraColors.warning,
                        ),
                        TexoraKpiCard(
                          label: 'CRITICAL SHORTAGES',
                          value: '$criticalCount Outages',
                          subtitle: 'Zero stock impact on looms',
                          isPositive: criticalCount == 0,
                          icon: Icons.report_problem_rounded,
                          iconColor: TexoraColors.critical,
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

                  // AI Inventory Recommendations & Category Breakdown
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // AI Inventory Recommendations
                      Expanded(
                        flex: 6,
                        child: TexoraCard(
                          title: 'AI Inventory Agent Requisitions',
                          subtitle: 'Automated buffer replenishment based on mean-time-between-failures',
                          child: Column(
                            children: recommendations.isNotEmpty
                                ? recommendations.map((rec) {
                                    final isHigh = rec['urgency'] == 'HIGH';
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isHigh ? TexoraColors.criticalBg : TexoraColors.workspaceBg,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isHigh ? TexoraColors.criticalBorder : TexoraColors.cardBorder,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            isHigh ? Icons.warning_rounded : Icons.info_outline_rounded,
                                            color: isHigh ? TexoraColors.critical : TexoraColors.primaryBlue,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Text(
                                                      rec['name'] ?? 'Part',
                                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary),
                                                    ),
                                                    TexoraStatusBadge(
                                                      label: rec['urgency'] ?? 'NORMAL',
                                                      variant: isHigh ? TexoraBadgeVariant.critical : TexoraBadgeVariant.attention,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(rec['reason'] ?? '', style: const TextStyle(fontSize: 11, color: TexoraColors.textSecondary)),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Recommended Order: ${rec['recommended_order_quantity']} units • Est Cost: ₹${rec['estimated_cost_inr']}',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TexoraColors.primaryBlue),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList()
                                : [
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                        child: Text(
                                          'All spare parts and materials are operating above safety stock thresholds.',
                                          style: TextStyle(fontSize: 12, color: TexoraColors.textSecondary),
                                        ),
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Recent Movement / Transactions
                      Expanded(
                        flex: 5,
                        child: TexoraCard(
                          title: 'Recent Stock Movement Log',
                          subtitle: 'Maintenance allocations & verified receipts',
                          child: Column(
                            children: _transactions.take(4).map((tx) {
                              final type = tx['transaction_type'] as String? ?? 'CONSUMPTION';
                              final isOut = type == 'CONSUMPTION' || type == 'SCRAPPED';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: TexoraColors.workspaceBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: TexoraColors.cardBorder),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isOut ? Icons.arrow_outward_rounded : Icons.arrow_downward_rounded,
                                      color: isOut ? TexoraColors.warning : TexoraColors.success,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tx['item_name'] ?? 'Spare Part',
                                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${tx['quantity']} units • ${tx['notes'] ?? type}',
                                            style: const TextStyle(fontSize: 10.5, color: TexoraColors.textSecondary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      (tx['timestamp'] ?? '').toString().split('T').first,
                                      style: const TextStyle(fontSize: 10, color: TexoraColors.textMuted),
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

                  // Inventory Table
                  TexoraCard(
                    title: 'Spare Parts & Materials Catalog',
                    subtitle: 'Current physical inventory vs reorder trigger points',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Filters and search
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: TexoraFilterTabs(
                                  tabs: _filterLabels,
                                  selectedIndex: _filterKeys.contains(_selectedCategoryFilter)
                                      ? _filterKeys.indexOf(_selectedCategoryFilter)
                                      : 0,
                                  onTabSelected: (index) {
                                    setState(() => _selectedCategoryFilter = _filterKeys[index]);
                                    _loadInventoryData(silent: true);
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
                                  hintText: 'Search SKU code, name...',
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

                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: Text('No inventory items found matching your filters.', style: TextStyle(color: TexoraColors.textSecondary)),
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
                                  0: FlexColumnWidth(1.6),
                                  1: FlexColumnWidth(2.6),
                                  2: FlexColumnWidth(1.6),
                                  3: FlexColumnWidth(1.8),
                                  4: FlexColumnWidth(1.4),
                                  5: FlexColumnWidth(1.4),
                                  6: FlexColumnWidth(1.2),
                                },
                                children: [
                                  TableRow(
                                    decoration: const BoxDecoration(color: TexoraColors.workspaceBg),
                                    children: [
                                      _tableHeaderCell('SKU CODE'),
                                      _tableHeaderCell('ITEM DESCRIPTION'),
                                      _tableHeaderCell('CATEGORY'),
                                      _tableHeaderCell('STOCK LEVEL'),
                                      _tableHeaderCell('REORDER PT'),
                                      _tableHeaderCell('UNIT COST'),
                                      _tableHeaderCell('ACTION'),
                                    ],
                                  ),
                                  ...filtered.map((item) {
                                    final currentStock = parseDoubleWithFallback(item['current_stock'], 0.0, fieldName: 'current_stock');
                                    final reorderPoint = parseDoubleWithFallback(item['reorder_point'], 10.0, fieldName: 'reorder_point');
                                    final unit = (item['unit'] ?? 'units').toString();
                                    final cost = parseDoubleWithFallback(item['unit_cost'], 0.0, fieldName: 'unit_cost');
                                    final isLow = currentStock <= reorderPoint;

                                    return TableRow(
                                      decoration: const BoxDecoration(
                                        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder, width: 0.8)),
                                      ),
                                      children: [
                                        _tableBodyCell(item['item_code'] ?? '-', isBold: true),
                                        _tableBodyCell(item['name'] ?? '-'),
                                        _tableBodyCell(item['category'] ?? '-'),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  '$currentStock $unit',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: isLow ? TexoraColors.critical : TexoraColors.textPrimary,
                                                    fontFamily: 'monospace',
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              if (isLow)
                                                const Icon(Icons.arrow_drop_down_rounded, color: TexoraColors.critical, size: 18),
                                            ],
                                          ),
                                        ),
                                        _tableBodyCell('$reorderPoint $unit', isMonospace: true),
                                        _tableBodyCell('₹$cost', isMonospace: true),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                          child: TextButton(
                                            onPressed: () {
                                              setState(() => _selectedItem = item);
                                            },
                                            child: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TexoraColors.primaryBlue)),
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
          if (_selectedItem != null)
            _buildItemDetailDrawer(_selectedItem!),
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

  Widget _buildItemDetailDrawer(Map<String, dynamic> item) {
    final currentStock = (item['current_stock'] as num?)?.toDouble() ?? 0.0;
    final reorderPoint = (item['reorder_point'] as num?)?.toDouble() ?? 0.0;
    final safetyStock = (item['minimum_safety_stock'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (item['unit_cost'] as num?)?.toDouble() ?? 0.0;
    final unit = item['unit'] ?? 'units';
    final isLow = currentStock <= reorderPoint;

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
                    'SKU Inventory Details',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedItem = null),
                  icon: const Icon(Icons.close_rounded, size: 18, color: TexoraColors.textMuted),
                ),
              ],
            ),
            const Divider(color: TexoraColors.cardBorder, height: 24),

            Text(item['item_code'] ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: TexoraColors.textPrimary)),
            const SizedBox(height: 4),
            Text(item['name'] ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: TexoraColors.textSecondary)),
            const SizedBox(height: 12),
            TexoraStatusBadge(
              label: isLow ? 'LOW STOCK ALERT' : 'OPTIMAL STOCK',
              variant: isLow ? TexoraBadgeVariant.critical : TexoraBadgeVariant.running,
              showDot: true,
            ),
            const SizedBox(height: 18),

            // Stock Breakdown Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TexoraColors.workspaceBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TexoraColors.cardBorder),
              ),
              child: Column(
                children: [
                  _detailRow('Warehouse Shelf Location', item['location_shelf'] ?? 'Bay 2 - Rack A3'),
                  const SizedBox(height: 6),
                  _detailRow('Current Stock Available', '$currentStock $unit', isBold: true, color: isLow ? TexoraColors.critical : TexoraColors.success),
                  const SizedBox(height: 6),
                  _detailRow('Reorder Threshold', '$reorderPoint $unit'),
                  const SizedBox(height: 6),
                  _detailRow('Minimum Safety Stock', '$safetyStock $unit'),
                  const SizedBox(height: 6),
                  _detailRow('Unit Replacement Cost', '₹$unitCost / $unit', isBold: true),
                  const SizedBox(height: 6),
                  _detailRow('Total Inventory Value', '₹${(currentStock * unitCost).toInt()}', isBold: true, color: TexoraColors.primaryBlue),
                ],
              ),
            ),
            const SizedBox(height: 18),

            const Text('Linked Machine Compatibilities', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'Compatible with Picanol OmniPlus-i Air Jet Loom, Itema R9500-2 Rapier, and Rieter G 38 Compact spinning frames.',
              style: const TextStyle(fontSize: 11.5, color: TexoraColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: TexoraColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
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
