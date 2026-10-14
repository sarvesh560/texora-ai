import '../../core/utils/numeric_parser.dart';

class InventoryItemModel {
  final int id;
  final String itemCode;
  final String name;
  final String category;
  final double currentStock;
  final double minimumSafetyStock;
  final double reorderPoint;
  final String unit;
  final double unitCost;
  final String locationShelf;
  final bool isActive;
  final bool isLowStock;
  final String createdAt;
  final String updatedAt;

  InventoryItemModel({
    required this.id,
    required this.itemCode,
    required this.name,
    required this.category,
    required this.currentStock,
    required this.minimumSafetyStock,
    required this.reorderPoint,
    required this.unit,
    required this.unitCost,
    this.locationShelf = '',
    this.isActive = true,
    this.isLowStock = false,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory InventoryItemModel.fromJson(Map<String, dynamic> json) {
    final currentStock = parseDoubleWithFallback(json['current_stock'], 0.0, fieldName: 'current_stock');
    final reorderPoint = parseDoubleWithFallback(json['reorder_point'], 0.0, fieldName: 'reorder_point');
    final isLowStockExplicit = json['is_low_stock'];

    return InventoryItemModel(
      id: parseIntWithFallback(json['id'], 0, fieldName: 'id'),
      itemCode: (json['item_code'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? 'SPARE_PARTS').toString(),
      currentStock: currentStock,
      minimumSafetyStock: parseDoubleWithFallback(json['minimum_safety_stock'], 0.0, fieldName: 'minimum_safety_stock'),
      reorderPoint: reorderPoint,
      unit: (json['unit'] ?? 'units').toString(),
      unitCost: parseDoubleWithFallback(json['unit_cost'], 0.0, fieldName: 'unit_cost'),
      locationShelf: (json['location_shelf'] ?? '').toString(),
      isActive: json['is_active'] as bool? ?? true,
      isLowStock: isLowStockExplicit is bool ? isLowStockExplicit : currentStock <= reorderPoint,
      createdAt: (json['created_at'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'item_code': itemCode,
    'name': name,
    'category': category,
    'current_stock': currentStock,
    'minimum_safety_stock': minimumSafetyStock,
    'reorder_point': reorderPoint,
    'unit': unit,
    'unit_cost': unitCost,
    'location_shelf': locationShelf,
    'is_active': isActive,
    'is_low_stock': isLowStock,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

class InventoryTransactionModel {
  final int id;
  final String itemCode;
  final String itemName;
  final String transactionType;
  final double quantity;
  final String referenceNumber;
  final String notes;
  final String timestamp;

  InventoryTransactionModel({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.transactionType,
    required this.quantity,
    this.referenceNumber = '',
    this.notes = '',
    this.timestamp = '',
  });

  factory InventoryTransactionModel.fromJson(Map<String, dynamic> json) {
    return InventoryTransactionModel(
      id: parseIntWithFallback(json['id'], 0, fieldName: 'id'),
      itemCode: (json['item_code'] ?? '').toString(),
      itemName: (json['item_name'] ?? 'Part').toString(),
      transactionType: (json['transaction_type'] ?? 'CONSUMPTION').toString(),
      quantity: parseDoubleWithFallback(json['quantity'], 0.0, fieldName: 'quantity'),
      referenceNumber: (json['reference_number'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      timestamp: (json['timestamp'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'item_code': itemCode,
    'item_name': itemName,
    'transaction_type': transactionType,
    'quantity': quantity,
    'reference_number': referenceNumber,
    'notes': notes,
    'timestamp': timestamp,
  };
}

class InventorySummaryModel {
  final int totalItems;
  final double totalInventoryValueInr;
  final int lowStockCount;
  final int criticalShortageCount;
  final List<Map<String, dynamic>> categoryBreakdown;
  final List<InventoryTransactionModel> recentTransactions;
  final List<Map<String, dynamic>> aiRecommendations;

  InventorySummaryModel({
    required this.totalItems,
    required this.totalInventoryValueInr,
    required this.lowStockCount,
    required this.criticalShortageCount,
    required this.categoryBreakdown,
    required this.recentTransactions,
    required this.aiRecommendations,
  });

  factory InventorySummaryModel.fromJson(Map<String, dynamic> json) {
    final rawTxs = json['recent_transactions'] as List? ?? [];
    final txs = rawTxs
        .whereType<Map<String, dynamic>>()
        .map((t) => InventoryTransactionModel.fromJson(t))
        .toList();

    final rawRecs = json['ai_recommendations'] as List? ?? [];
    final recs = rawRecs.whereType<Map<String, dynamic>>().toList();

    final rawCats = (json['category_breakdown'] ?? json['categories_breakdown']) as List? ?? [];
    final cats = rawCats.whereType<Map<String, dynamic>>().toList();

    return InventorySummaryModel(
      totalItems: parseIntWithFallback(json['total_items'], 0, fieldName: 'total_items'),
      totalInventoryValueInr: parseDoubleWithFallback(
        json['total_inventory_value_inr'] ?? json['total_inventory_valuation'],
        0.0,
        fieldName: 'total_inventory_value_inr',
      ),
      lowStockCount: parseIntWithFallback(json['low_stock_count'], 0, fieldName: 'low_stock_count'),
      criticalShortageCount: parseIntWithFallback(
        json['critical_shortage_count'] ?? json['critical_outage_count'],
        0,
        fieldName: 'critical_shortage_count',
      ),
      categoryBreakdown: cats,
      recentTransactions: txs,
      aiRecommendations: recs,
    );
  }
}
