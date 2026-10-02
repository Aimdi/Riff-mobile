import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/navigator.dart';
import 'package:harmonymusic/ui/widgets/riff_tab_bar.dart';

void main() {
  setUpAll(() => RiffShell.desktopOverride = false);
  tearDownAll(() => RiffShell.desktopOverride = null);

  test('library tab covers songs, playlists, albums and artists', () {
    for (final i in [1, 4, 5, 6]) {
      expect(selectedRiffTab(i, null), 'library');
    }
    expect(selectedRiffTab(0, null), 'home');
    expect(selectedRiffTab(2, null), 'podcasts');
    expect(selectedRiffTab(3, null), 'audiobooks');
    expect(selectedRiffTab(7, null), isNull, reason: 'settings lights nothing');
  });

  test('search on top lights the search button whatever the tab', () {
    expect(selectedRiffTab(2, ScreenNavigationSetup.searchScreen), 'search');
    expect(selectedRiffTab(0, ScreenNavigationSetup.searchResultScreen),
        'search');
    expect(selectedRiffTab(0, ScreenNavigationSetup.artistScreen), 'home');
  });

  test('panel height: dock on phones, mini player only when a song exists',
      () {
    final dock = RiffShell.dockHeight(400, 24);
    expect(dock, RiffShell.tabBarHeight + RiffShell.tabBarGap + 24);
    expect(
        RiffShell.panelMinHeight(width: 400, bottomInset: 24, hasSong: false),
        dock);
    expect(
        RiffShell.panelMinHeight(width: 400, bottomInset: 24, hasSong: true),
        dock + RiffShell.miniPlayerHeight);
    // Tablets keep the rail and the old mini player strip.
    expect(RiffShell.dockHeight(900, 24), 0);
    expect(
        RiffShell.panelMinHeight(width: 900, bottomInset: 24, hasSong: false),
        0);
    expect(
        RiffShell.panelMinHeight(width: 900, bottomInset: 24, hasSong: true),
        105 + 24);
  });
}
