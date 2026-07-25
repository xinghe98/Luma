T requiredValue<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException('Expected $key to be $T');
}

T? nullableValue<T>(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field $key');
  }
  final value = json[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('Expected $key to be $T or null');
}

T? optionalValue<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is T) return value as T?;
  throw FormatException('Expected $key to be $T or null');
}

DateTime requiredDate(Map<String, dynamic> json, String key) =>
    DateTime.parse(requiredValue<String>(json, key));

DateTime? nullableDate(Map<String, dynamic> json, String key) {
  final value = nullableValue<String>(json, key);
  return value == null ? null : DateTime.parse(value);
}

DateTime? optionalDate(Map<String, dynamic> json, String key) {
  final value = optionalValue<String>(json, key);
  return value == null ? null : DateTime.parse(value);
}

Map<String, dynamic> objectValue(Object? value, String name) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('Expected $name to be a JSON object');
}

List<Object?> listValue(Map<String, dynamic> json, String key) =>
    requiredValue<List<Object?>>(json, key);
