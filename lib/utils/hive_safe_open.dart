import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Open a Hive box; on corruption quarantine the on-disk files and reopen empty
/// so a bad box cannot brick cold start.
Future<Box<E>> safeOpenBox<E>(String name) async {
  try {
    return await Hive.openBox<E>(name);
  } catch (e, st) {
    debugPrint('Hive open failed for "$name": $e\n$st');
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (deleteErr) {
      debugPrint('Hive deleteBoxFromDisk("$name") failed: $deleteErr');
    }
    try {
      return await Hive.openBox<E>(name);
    } catch (e2, st2) {
      debugPrint('Hive reopen failed for "$name": $e2\n$st2');
      rethrow;
    }
  }
}
