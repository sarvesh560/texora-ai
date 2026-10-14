/// Enterprise-grade, type-safe numeric parser for industrial telemetry,
/// financial values (DecimalField strings), durations, and sensor thresholds.
class NumericParser {
  /// Safely parses an optional double from num, String ("0.00", "5.2"), or null.
  /// Returns null if [value] is null or an empty string.
  /// Throws [FormatException] if [value] is a malformed non-empty string or invalid type.
  static double? parseNullableDouble(dynamic value, {String? fieldName}) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final parsed = double.tryParse(trimmed);
      if (parsed != null) return parsed;
      throw FormatException(
        "Invalid numeric string for ${fieldName ?? 'field'}: '$value'",
      );
    }
    throw FormatException(
      "Expected number or numeric string for ${fieldName ?? 'field'}, got ${value.runtimeType}: '$value'",
    );
  }

  /// Parses a required double.
  /// If [value] is null and [defaultValue] is provided, returns [defaultValue].
  /// Otherwise throws [FormatException] if null, invalid string, or invalid type.
  static double parseRequiredDouble(
    dynamic value, {
    required String fieldName,
    double? defaultValue,
  }) {
    if (value == null) {
      if (defaultValue != null) return defaultValue;
      throw FormatException("Missing required numeric field: '$fieldName'");
    }
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        if (defaultValue != null) return defaultValue;
        throw FormatException("Empty string for required numeric field: '$fieldName'");
      }
      final parsed = double.tryParse(trimmed);
      if (parsed != null) return parsed;
      throw FormatException(
        "Invalid numeric string for required field '$fieldName': '$value'",
      );
    }
    throw FormatException(
      "Expected number or numeric string for required field '$fieldName', got ${value.runtimeType}: '$value'",
    );
  }

  /// Parses a double with a safe fallback default if [value] is null or empty string.
  /// Throws [FormatException] if [value] is a malformed string or invalid type.
  static double parseDoubleWithFallback(
    dynamic value,
    double fallback, {
    String? fieldName,
  }) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return fallback;
      final parsed = double.tryParse(trimmed);
      if (parsed != null) return parsed;
      throw FormatException(
        "Invalid numeric string for ${fieldName ?? 'field'}: '$value'",
      );
    }
    throw FormatException(
      "Expected number or numeric string for ${fieldName ?? 'field'}, got ${value.runtimeType}: '$value'",
    );
  }

  /// Safely parses an optional int from num, String ("5", "5.0"), or null.
  /// Returns null if [value] is null or empty string.
  /// Throws [FormatException] if [value] is an invalid string or invalid type.
  static int? parseNullableInt(dynamic value, {String? fieldName}) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final parsedInt = int.tryParse(trimmed);
      if (parsedInt != null) return parsedInt;
      final parsedDouble = double.tryParse(trimmed);
      if (parsedDouble != null) return parsedDouble.toInt();
      throw FormatException(
        "Invalid integer string for ${fieldName ?? 'field'}: '$value'",
      );
    }
    throw FormatException(
      "Expected integer or numeric string for ${fieldName ?? 'field'}, got ${value.runtimeType}: '$value'",
    );
  }

  /// Parses a required int.
  /// If [value] is null and [defaultValue] is provided, returns [defaultValue].
  /// Otherwise throws [FormatException] if null, invalid string, or invalid type.
  static int parseRequiredInt(
    dynamic value, {
    required String fieldName,
    int? defaultValue,
  }) {
    if (value == null) {
      if (defaultValue != null) return defaultValue;
      throw FormatException("Missing required integer field: '$fieldName'");
    }
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        if (defaultValue != null) return defaultValue;
        throw FormatException("Empty string for required integer field: '$fieldName'");
      }
      final parsedInt = int.tryParse(trimmed);
      if (parsedInt != null) return parsedInt;
      final parsedDouble = double.tryParse(trimmed);
      if (parsedDouble != null) return parsedDouble.toInt();
      throw FormatException(
        "Invalid integer string for required field '$fieldName': '$value'",
      );
    }
    throw FormatException(
      "Expected integer or numeric string for required field '$fieldName', got ${value.runtimeType}: '$value'",
    );
  }

  /// Parses an int with a safe fallback default if [value] is null or empty string.
  /// Throws [FormatException] if [value] is a malformed string or invalid type.
  static int parseIntWithFallback(
    dynamic value,
    int fallback, {
    String? fieldName,
  }) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return fallback;
      final parsedInt = int.tryParse(trimmed);
      if (parsedInt != null) return parsedInt;
      final parsedDouble = double.tryParse(trimmed);
      if (parsedDouble != null) return parsedDouble.toInt();
      throw FormatException(
        "Invalid integer string for ${fieldName ?? 'field'}: '$value'",
      );
    }
    throw FormatException(
      "Expected integer or numeric string for ${fieldName ?? 'field'}, got ${value.runtimeType}: '$value'",
    );
  }
}

// Top-level convenience aliases
double? parseNullableDouble(dynamic value, {String? fieldName}) =>
    NumericParser.parseNullableDouble(value, fieldName: fieldName);

double parseRequiredDouble(
  dynamic value, {
  required String fieldName,
  double? defaultValue,
}) =>
    NumericParser.parseRequiredDouble(
      value,
      fieldName: fieldName,
      defaultValue: defaultValue,
    );

double parseDoubleWithFallback(
  dynamic value,
  double fallback, {
  String? fieldName,
}) =>
    NumericParser.parseDoubleWithFallback(
      value,
      fallback,
      fieldName: fieldName,
    );

int? parseNullableInt(dynamic value, {String? fieldName}) =>
    NumericParser.parseNullableInt(value, fieldName: fieldName);

int parseRequiredInt(
  dynamic value, {
  required String fieldName,
  int? defaultValue,
}) =>
    NumericParser.parseRequiredInt(
      value,
      fieldName: fieldName,
      defaultValue: defaultValue,
    );

int parseIntWithFallback(
  dynamic value,
  int fallback, {
  String? fieldName,
}) =>
    NumericParser.parseIntWithFallback(
      value,
      fallback,
      fieldName: fieldName,
    );
