import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/watch_record.dart';

/// 首页的本地图库状态：列表、搜索、增删改。
class LibraryProvider extends ChangeNotifier {
  LibraryProvider([DatabaseHelper? db]) : _db = db ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  List<WatchRecord> records = const [];
  String query = '';
  bool loading = false;
  int total = 0;

  Timer? _debounce;
  int _seq = 0; // 丢弃过期的查询结果
  bool _disposed = false;

  Future<void> load() => _refresh();

  void setQuery(String q) {
    query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _refresh);
  }

  Future<void> _refresh() async {
    final seq = ++_seq;
    loading = true;
    _notify();

    final rows = query.trim().isEmpty ? await _db.getAll() : await _db.search(query);
    final count = await _db.count();
    if (seq != _seq) return;

    records = rows;
    total = count;
    loading = false;
    _notify();
  }

  Future<WatchRecord?> findDuplicate(WatchRecord r) => _db.findDuplicate(r);

  Future<WatchRecord> insert(WatchRecord r) async {
    final id = await _db.insert(r);
    await _refresh();
    return (await _db.getById(id))!;
  }

  Future<WatchRecord> overwrite(int id, WatchRecord r) async {
    await _db.overwrite(id, r);
    await _refresh();
    return (await _db.getById(id))!;
  }

  Future<void> delete(int id) async {
    // 先同步移除本地列表（Dismissible 要求）
    records = records.where((e) => e.id != id).toList();
    if (total > 0) total--;
    _notify();
    await _db.deleteById(id);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
