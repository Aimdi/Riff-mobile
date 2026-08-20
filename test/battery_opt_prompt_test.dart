import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Settings/battery_opt_prompt.dart';

void main() {
  test('battery prompt only on Android when not granted and not shown', () {
    expect(
      shouldPromptBatteryOptimization(
        isAndroid: true,
        alreadyGranted: false,
        alreadyShown: false,
      ),
      isTrue,
    );
    expect(
      shouldPromptBatteryOptimization(
        isAndroid: false,
        alreadyGranted: false,
        alreadyShown: false,
      ),
      isFalse,
    );
    expect(
      shouldPromptBatteryOptimization(
        isAndroid: true,
        alreadyGranted: true,
        alreadyShown: false,
      ),
      isFalse,
    );
    expect(
      shouldPromptBatteryOptimization(
        isAndroid: true,
        alreadyGranted: false,
        alreadyShown: true,
      ),
      isFalse,
    );
  });
}
