import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/screens/Home/home_greeting.dart';

void main() {
  test('homeGreetingKey follows morning / afternoon / evening', () {
    expect(homeGreetingKey(DateTime(2026, 8, 16, 0)), 'goodMorning');
    expect(homeGreetingKey(DateTime(2026, 8, 16, 11)), 'goodMorning');
    expect(homeGreetingKey(DateTime(2026, 8, 16, 12)), 'goodAfternoon');
    expect(homeGreetingKey(DateTime(2026, 8, 16, 16)), 'goodAfternoon');
    expect(homeGreetingKey(DateTime(2026, 8, 16, 17)), 'goodEvening');
    expect(homeGreetingKey(DateTime(2026, 8, 16, 23)), 'goodEvening');
  });
}
