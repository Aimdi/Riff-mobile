import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/widgets/cover_hero.dart';

const _cardCover = ValueKey('cardCover');
const _pageCover = ValueKey('pageCover');

/// A card on a shelf: its cover tagged with the card itself; a tap hands
/// the tag on and opens the page.
class _Card extends StatelessWidget {
  const _Card({required this.coverKey, this.root = false});
  final Key coverKey;

  /// Opens the page on the app's own navigator, over the one it's in.
  final bool root;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          CoverHero.launch(context);
          Navigator.of(context, rootNavigator: root)
              .push(MaterialPageRoute<void>(builder: (_) => const _Page()));
        },
        child: CoverHero(
          tag: context,
          child: SizedBox.square(
              key: coverKey,
              dimension: 150,
              child: const ColoredBox(color: Colors.teal)),
        ),
      );
}

/// The page: its cover takes the tag of the card that opened it.
class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final Object? _hero = CoverHero.take();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: CoverHero(
            tag: _hero,
            child: const SizedBox.square(
                key: _pageCover,
                dimension: 96,
                child: ColoredBox(color: Colors.teal)),
          ),
        ),
      );
}

void main() {
  testWidgets('the tapped cover flies to the page, between the two places',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          _Card(coverKey: _cardCover),
          // The same album on another shelf: its own tag, no clash.
          _Card(coverKey: ValueKey('otherCover')),
        ]),
      ),
    ));
    final from = tester.getRect(find.byKey(_cardCover));

    await tester.tap(find.byKey(_cardCover));
    await tester.pump(); // the page is built and the flight starts
    await tester.pump(const Duration(milliseconds: 150));

    // Mid-flight the cover is neither on the card nor on the page yet.
    final flying = tester.getRect(find.byKey(_pageCover));
    expect(flying, isNot(from));
    expect(flying.width, inExclusiveRange(96, 150));

    await tester.pumpAndSettle();
    final landed = tester.getRect(find.byKey(_pageCover));
    expect(landed.size, const Size.square(96));
    expect(
        landed.bottomRight, tester.getBottomRight(find.byType(Scaffold).last));
    // Taken once: a page opened later some other way gets no cover.
    expect(CoverHero.take(), isNull);
  });

  testWidgets('a cover in the page navigator flies to a page over it',
      (tester) async {
    // Shows and books open over the whole app (Get.to) from a tab that
    // lives in the page navigator.
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: _Card(coverKey: _cardCover, root: true)),
        ),
      ),
    ));
    await tester.tap(find.byKey(_cardCover));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getRect(find.byKey(_pageCover)).width,
        inExclusiveRange(96, 150));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(_pageCover)), const Size.square(96));
  });

  testWidgets('a page opened without a card has no flying cover',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const _Page())),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Hero), findsNothing);
    expect(find.byKey(_pageCover), findsOneWidget);
  });

  testWidgets('a handed-on cover is forgotten after the frame', (tester) async {
    await tester.pumpWidget(const SizedBox());
    CoverHero.launch(Object());
    await tester.pump();
    expect(CoverHero.take(), isNull);
  });
}
