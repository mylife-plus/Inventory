import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Chrome/web: route [openDatabase] through wasm + IndexedDB.
void initWebSqlite() {
  if (!kIsWeb) return;
  databaseFactory = databaseFactoryFfiWeb;
}
