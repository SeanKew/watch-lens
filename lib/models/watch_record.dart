/// 手表识别记录 —— 仅保存结构化文字，不含任何图片数据。
class WatchRecord {
  final int? id;
  final String brand;
  final String series;
  final String referenceNumber;
  final String movement;
  final String caseDiameter;
  final String waterResistance;
  final String releaseYear;
  final String estimatedPrice;
  final String summary;
  final String imageSearchQuery;
  final DateTime createdAt;
  final DateTime updatedAt;

  const WatchRecord({
    this.id,
    required this.brand,
    required this.series,
    required this.referenceNumber,
    required this.movement,
    required this.caseDiameter,
    required this.waterResistance,
    required this.releaseYear,
    required this.estimatedPrice,
    required this.summary,
    required this.imageSearchQuery,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 用于判重的归一化键：优先参考型号，其次品牌+系列。
  String get refKey => buildKey(
        referenceNumber: referenceNumber,
        brand: brand,
        series: series,
      );

  static const _unknownTokens = {'unknown', '未知', 'na', 'null', '无', '不详'};

  static String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s\-_./·]'), '');

  static String buildKey({
    required String referenceNumber,
    required String brand,
    required String series,
  }) {
    final ref = normalize(referenceNumber);
    if (ref.isNotEmpty && !_unknownTokens.contains(ref)) return 'ref:$ref';
    return 'bs:${normalize(brand)}|${normalize(series)}';
  }

  /// 由 Gemini 返回的 JSON 构造（容错：缺字段/数字类型均转为字符串）。
  factory WatchRecord.fromGeminiJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString().trim();
    final now = DateTime.now();
    return WatchRecord(
      brand: s('brand'),
      series: s('series'),
      referenceNumber: s('reference_number'),
      movement: s('movement'),
      caseDiameter: s('case_diameter'),
      waterResistance: s('water_resistance'),
      releaseYear: s('release_year'),
      estimatedPrice: s('estimated_price'),
      summary: s('summary'),
      imageSearchQuery: s('image_search_query'),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory WatchRecord.fromMap(Map<String, Object?> m) {
    String s(String key) => (m[key] ?? '').toString();
    return WatchRecord(
      id: m['id'] as int?,
      brand: s('brand'),
      series: s('series'),
      referenceNumber: s('reference_number'),
      movement: s('movement'),
      caseDiameter: s('case_diameter'),
      waterResistance: s('water_resistance'),
      releaseYear: s('release_year'),
      estimatedPrice: s('estimated_price'),
      summary: s('summary'),
      imageSearchQuery: s('image_search_query'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'ref_key': refKey,
        'brand': brand,
        'series': series,
        'reference_number': referenceNumber,
        'movement': movement,
        'case_diameter': caseDiameter,
        'water_resistance': waterResistance,
        'release_year': releaseYear,
        'estimated_price': estimatedPrice,
        'summary': summary,
        'image_search_query': imageSearchQuery,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  WatchRecord copyWith({
    int? id,
    String? brand,
    String? series,
    String? referenceNumber,
    String? movement,
    String? caseDiameter,
    String? waterResistance,
    String? releaseYear,
    String? estimatedPrice,
    String? summary,
    String? imageSearchQuery,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WatchRecord(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      series: series ?? this.series,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      movement: movement ?? this.movement,
      caseDiameter: caseDiameter ?? this.caseDiameter,
      waterResistance: waterResistance ?? this.waterResistance,
      releaseYear: releaseYear ?? this.releaseYear,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      summary: summary ?? this.summary,
      imageSearchQuery: imageSearchQuery ?? this.imageSearchQuery,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 列表页标题，如 "Rolex 劳力士 · Submariner · 126610LN"
  String get displayTitle {
    final parts = [brand, series, referenceNumber]
        .where((e) => e.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? '未知手表' : parts.join(' · ');
  }
}
