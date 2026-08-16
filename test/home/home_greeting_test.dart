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

  test('homeFeedTopPadding stays tight on phones', () {
    expect(
      homeFeedTopPadding(isDesktop: false, isLandscape: false, statusBar: 48),
      60,
    );
    expect(
      homeFeedTopPadding(isDesktop: false, isLandscape: true, statusBar: 24),
      32,
    );
    expect(
      homeFeedTopPadding(isDesktop: true, isLandscape: false, statusBar: 0),
      85,
    );
  });

  test('homeGreetingFontSize is large on phones and larger on desktop', () {
    expect(homeGreetingFontSize(isDesktop: false), 28);
    expect(homeGreetingFontSize(isDesktop: true), 32);
  });

  test('jumpBackInGridCount caps at six recents', () {
    expect(jumpBackInGridCount(0), 0);
    expect(jumpBackInGridCount(1), 1);
    expect(jumpBackInGridCount(5), 5);
    expect(jumpBackInGridCount(6), 6);
    expect(jumpBackInGridCount(20), 6);
  });

  test('discovery shelf cards are large enough to read as covers', () {
    expect(discoveryShelfCardSize(isDailyMix: true), 148);
    expect(discoveryShelfCardSize(isDailyMix: false), 136);
    expect(discoveryShelfRowHeight(isDailyMix: true), 200);
    expect(discoveryShelfRowHeight(isDailyMix: false), 186);
  });
}
