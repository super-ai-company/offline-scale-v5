import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import '../models/menu_item.dart';

class DbService {
  static final DbService _instance = DbService._();
  factory DbService() => _instance;
  DbService._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'cashier.db');
    return openAt(path);
  }

  static Future<Database> openAt(String path) {
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE menu_items (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name_en    TEXT NOT NULL DEFAULT '',
            name_th    TEXT NOT NULL,
            name_cn    TEXT DEFAULT '',
            price      REAL NOT NULL,
            is_by_weight INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await _seedDefaultMenuIfEmpty(db);
        await _createVisualSamples(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE menu_items ADD COLUMN name_en TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 3) {
          await _seedDefaultMenuIfEmpty(db);
        }
        if (oldVersion < 4) {
          await _createVisualSamples(db);
        }
      },
    );
  }

  static Future<void> _seedDefaultMenuIfEmpty(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM menu_items'),
    );
    if (count != 0) return;
    await db.insert('menu_items', MenuItem.quickWeigh.toMap()..remove('id'));
  }

  static Future<void> _createVisualSamples(Database db) async {
    await db.execute('''
      CREATE TABLE visual_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_item_id INTEGER NOT NULL,
        model TEXT NOT NULL,
        embedding TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX visual_samples_item_idx ON visual_samples(menu_item_id)',
    );
  }

  // ── 菜单 CRUD ─────────────────────────────────────────────

  Future<List<MenuItem>> getMenuItems() async {
    final rows = await (await db).query('menu_items', orderBy: 'id ASC');
    return rows.map(MenuItem.fromMap).toList();
  }

  Future<MenuItem> insertMenuItem(MenuItem item) async {
    final id = await (await db).insert(
      'menu_items',
      item.toMap()..remove('id'),
    );
    return item.copyWith(id: id);
  }

  Future<void> updateMenuItem(MenuItem item) async {
    await (await db).update(
      'menu_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteMenuItem(int id) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'visual_samples',
        where: 'menu_item_id = ?',
        whereArgs: [id],
      );
      await txn.delete('menu_items', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<String> _visualModel() async {
    final camera = (await SharedPreferences.getInstance()).getString(
      'produce_camera_name',
    );
    return camera == null
        ? 'mobilenet_v3_small_v1'
        : 'mobilenet_v3_small_v1:camera:$camera';
  }

  Future<void> addVisualSample(int itemId, List<double> embedding) async {
    if (embedding.isEmpty || embedding.any((value) => !value.isFinite)) {
      throw ArgumentError('Invalid image embedding');
    }
    await (await db).insert('visual_samples', {
      'menu_item_id': itemId,
      'model': await _visualModel(),
      'embedding': jsonEncode(embedding),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<Map<int, int>> visualSampleCounts() async {
    final rows = await (await db).rawQuery(
      'SELECT menu_item_id, COUNT(*) AS count FROM visual_samples '
      'WHERE model = ? GROUP BY menu_item_id',
      [await _visualModel()],
    );
    return {
      for (final row in rows) row['menu_item_id'] as int: row['count'] as int,
    };
  }

  Future<List<(int, List<double>)>> visualSamples() async {
    final rows = await (await db).query(
      'visual_samples',
      columns: ['menu_item_id', 'embedding'],
      where: 'model = ?',
      whereArgs: [await _visualModel()],
    );
    return rows
        .map(
          (row) => (
            row['menu_item_id'] as int,
            (jsonDecode(row['embedding'] as String) as List)
                .map((value) => (value as num).toDouble())
                .toList(),
          ),
        )
        .toList();
  }

  Future<void> clearVisualSamples(int itemId) async {
    await (await db).delete(
      'visual_samples',
      where: 'menu_item_id = ?',
      whereArgs: [itemId],
    );
  }
}
