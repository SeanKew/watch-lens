import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/watch_record.dart';

/// 本地 SQLite 管理类。只存文字字段与时间戳，不存任何图片 / Base64。
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _dbName = 'watchlens.db';
  static const _dbVersion = 1;
  static const table = 'watch_records';

  /// 参与模糊查询的列
  static const _searchColumns = [
    'brand',
    'series',
    'reference_number',
    'movement',
    'case_diameter',
    'release_year',
    'summary',
  ];

  Future<Database>? _opening;

  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ref_key TEXT NOT NULL,
        brand TEXT NOT NULL DEFAULT '',
        series TEXT NOT NULL DEFAULT '',
        reference_number TEXT NOT NULL DEFAULT '',
        movement TEXT NOT NULL DEFAULT '',
        case_diameter TEXT NOT NULL DEFAULT '',
        water_resistance TEXT NOT NULL DEFAULT '',
        release_year TEXT NOT NULL DEFAULT '',
        estimated_price TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        image_search_query TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_watch_ref_key ON $table(ref_key)');
    await db.execute('CREATE INDEX idx_watch_updated ON $table(updated_at DESC)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 预留：后续版本在此做迁移。
  }

  // ───────────────────────── 写入 ─────────────────────────

  /// 新增记录，返回新行 id。
  Future<int> insert(WatchRecord record) async {
    final db = await database;
    final now = DateTime.now();
    final map = record.copyWith(createdAt: now, updatedAt: now).toMap()
      ..remove('id');
    return db.insert(table, map);
  }

  /// 覆盖已有记录（保留原 created_at，刷新 updated_at）。
  Future<void> overwrite(int id, WatchRecord record) async {
    final db = await database;
    final map = record.copyWith(updatedAt: DateTime.now()).toMap()
      ..remove('id')
      ..remove('created_at');
    await db.update(table, map, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteById(int id) async {
    final db = await database;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  // ───────────────────────── 查询 ─────────────────────────

  /// 查找同型号已有记录（用于"数据库已有记录"提示）。
  Future<WatchRecord?> findDuplicate(WatchRecord record) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: 'ref_key = ?',
      whereArgs: [record.refKey],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WatchRecord.fromMap(rows.first);
  }

  Future<WatchRecord?> getById(int id) async {
    final db = await database;
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : WatchRecord.fromMap(rows.first);
  }

  Future<List<WatchRecord>> getAll({int limit = 200, int offset = 0}) async {
    final db = await database;
    final rows = await db.query(
      table,
      orderBy: 'updated_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(WatchRecord.fromMap).toList();
  }

  Future<int> count() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table'),
        ) ??
        0;
  }

  /// 多关键词模糊搜索：空格分隔的每个词都必须命中（AND），
  /// 每个词可命中任一列（OR）。同时用归一化键匹配 "126610-LN" 这类写法。
  Future<List<WatchRecord>> search(String query, {int limit = 200}) async {
    final tokens = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return getAll(limit: limit);

    final where = <String>[];
    final args = <Object?>[];
    for (final token in tokens) {
      final pattern = '%${_escapeLike(token)}%';
      final keyPattern = '%${_escapeLike(WatchRecord.normalize(token))}%';
      final ors = [
        for (final c in _searchColumns) "$c LIKE ? ESCAPE '\\'",
        "ref_key LIKE ? ESCAPE '\\'",
      ];
      where.add('(${ors.join(' OR ')})');
      args
        ..addAll(List.filled(_searchColumns.length, pattern))
        ..add(keyPattern);
    }

    final db = await database;
    final rows = await db.query(
      table,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map(WatchRecord.fromMap).toList();
  }

  static String _escapeLike(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  Future<void> close() async {
    final db = await _opening;
    await db?.close();
    _opening = null;
  }
}
