import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/widgets/sort_widget.dart';

void main() {
  tearDown(Get.reset);

  test('deleting a sort row controller disposes its search field controller',
      () async {
    final c = Get.put(SortWidgetController(), tag: 'MPREalbum');
    c.textEditingController.text = 'query';
    expect(await Get.delete<SortWidgetController>(tag: 'MPREalbum'), isTrue);
    // A disposed ChangeNotifier refuses new listeners (debug check).
    expect(() => c.textEditingController.addListener(() {}),
        throwsA(isA<FlutterError>()));
  });
}
