import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/components/up_next_card.dart';
import 'package:harmonymusic/ui/theme/riff_spacing.dart';
import 'package:harmonymusic/ui/theme/riff_theme.dart';
import 'package:harmonymusic/ui/theme/riff_tokens.dart';
import 'package:harmonymusic/ui/widgets/sliding_up_panel.dart';

const _inset = 24.0;
const _phone = Size(411, 914);

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _app(Widget body) => MaterialApp(
      theme: RiffTheme.dark(const Color(0xFF1DB954)),
      home: Scaffold(body: body),
    );

Widget _card({VoidCallback? onTap, String preview = 'Dreams · 10 more'}) =>
    _app(Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        height: UpNextCard.extent + _inset,
        child: UpNextCard(
            preview: preview, bottomInset: _inset, onTap: onTap ?? () {}),
      ),
    ));

final _cardSurface = find.descendant(
    of: find.byType(UpNextCard), matching: find.byType(Material));

/// The fade around the panel's own content, if the panel has one.
final _panelFade = find.ancestor(
    of: find.text('queue'),
    matching: find.descendant(
        of: find.byType(SlidingUpPanel),
        matching: find.byType(FadeTransition)));

void main() {
  testWidgets('a slim tab standing on the bottom edge, rounded on top',
      (tester) async {
    _screen(tester, _phone);
    await tester.pumpWidget(_card());

    final rect = tester.getRect(_cardSurface);
    expect(rect.height, RiffComponentSizes.queueCard + _inset);
    expect(rect.left, RiffSpacing.xxl);
    expect(rect.right, _phone.width - RiffSpacing.xxl);
    expect(rect.bottom, _phone.height);
    // The label stays clear of the system inset.
    expect(tester.getRect(find.text('upNext · Dreams · 10 more')).bottom,
        lessThanOrEqualTo(_phone.height - _inset));

    final shape =
        tester.widget<Material>(_cardSurface).shape! as RoundedRectangleBorder;
    expect(shape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(RiffRadii.lg)));
  });

  testWidgets('label and next song share one line', (tester) async {
    _screen(tester, _phone);
    await tester.pumpWidget(_card());
    // No translations loaded here, so the label shows its key.
    expect(find.text('upNext · Dreams · 10 more'), findsOneWidget);

    await tester.pumpWidget(_card(preview: ''));
    expect(find.text('upNext'), findsOneWidget);
  });

  testWidgets('the tab and the gap beside it open the queue', (tester) async {
    _screen(tester, _phone);
    var taps = 0;
    await tester.pumpWidget(_card(onTap: () => taps++));

    await tester.tap(find.text('upNext · Dreams · 10 more'));
    final rect = tester.getRect(_cardSurface);
    await tester.tapAt(Offset(RiffSpacing.xxl / 2, rect.center.dy));
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - _inset / 2));
    expect(taps, 3);
  });

  testWidgets('stays card-sized on a tablet', (tester) async {
    const tablet = Size(1280, 800);
    _screen(tester, tablet);
    await tester.pumpWidget(_card());

    final rect = tester.getRect(_cardSurface);
    expect(rect.width, RiffComponentSizes.queueCardMaxWidth);
    expect(rect.center.dx, tablet.width / 2);
  });

  testWidgets('a fading panel stays hidden behind the collapsed card',
      (tester) async {
    _screen(tester, _phone);
    final controller = PanelController();
    var queueTaps = 0;
    var cardTaps = 0;
    await tester.pumpWidget(_app(SlidingUpPanel(
      controller: controller,
      renderPanelSheet: false,
      fadePanelWhenCollapsed: true,
      minHeight: UpNextCard.extent + _inset,
      maxHeight: _phone.height,
      body: const SizedBox.expand(),
      panel: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => queueTaps++,
        child: const Center(child: Text('queue')),
      ),
      collapsed: UpNextCard(
          preview: 'Dreams', bottomInset: _inset, onTap: () => cardTaps++),
    )));

    double opacity() => tester.widget<FadeTransition>(_panelFade).opacity.value;
    expect(opacity(), 0);

    // A tap beside the card never lands on the hidden queue.
    await tester.tapAt(
        Offset(RiffSpacing.xxl / 2, tester.getRect(_cardSurface).center.dy));
    expect(cardTaps, 1);
    expect(queueTaps, 0);

    controller.open();
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await tester.tap(find.text('queue'));
    expect(queueTaps, 1);
  });

  testWidgets('panels without the flag are not faded', (tester) async {
    _screen(tester, _phone);
    await tester.pumpWidget(_app(const SlidingUpPanel(
      minHeight: 60,
      maxHeight: 600,
      body: SizedBox.expand(),
      panel: Center(child: Text('queue')),
    )));
    expect(_panelFade, findsNothing);
  });
}
