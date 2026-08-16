import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/ban_service.dart';

void main() {
  test('ban writes require an open Hive box', () {
    expect(BanService.canWriteBan(null), isFalse);
  });
}
