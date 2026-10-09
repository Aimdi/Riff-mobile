import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/services/soulseek_service.dart';
import 'package:harmonymusic/ui/screens/Plugins/seeker_screen.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';

class _FakeSoulseek extends GetxController implements SoulseekService {
  @override
  final isLoggedIn = true.obs;
  @override
  final username = 'me'.obs;
  @override
  final statusMessage = ''.obs;
  @override
  final isBusy = false.obs;

  void Function(SoulseekFile hit)? onHit;
  // Made by the search (inside the test's fake-async zone).
  late Completer<List<SoulseekFile>> done;

  @override
  Future<List<SoulseekFile>> search(
    String query, {
    void Function(SoulseekFile hit)? onHit,
    Duration timeout = const Duration(seconds: 8),
  }) {
    this.onHit = onHit;
    done = Completer<List<SoulseekFile>>();
    return done.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTheme extends GetxController implements ThemeController {
  @override
  final accentColor = const Color(0xFF1DB954).obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SoulseekFile _file(int i) => SoulseekFile(
      username: 'peer$i',
      filename: '@@music\\Artist\\Album\\Track $i.flac',
      size: 1000 + i,
      hasFreeSlot: true,
      speed: 0,
    );

void main() {
  late _FakeSoulseek soulseek;

  setUp(() {
    Get.reset();
    soulseek = Get.put<SoulseekService>(_FakeSoulseek()) as _FakeSoulseek;
    Get.put<ThemeController>(_FakeTheme());
  });
  tearDown(Get.reset);

  testWidgets('live hits are ranked and shown in batches, then the final list',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SeekerScreen(embedded: true, initialQuery: 'Track'),
      ),
    ));
    await tester.pump(); // the search starts after the first frame
    expect(soulseek.onHit, isNotNull);

    for (var i = 0; i < 3; i++) {
      soulseek.onHit!(_file(i));
    }
    // A burst of hits is not ranked hit by hit...
    await tester.pump();
    expect(find.text('Track 0.flac'), findsNothing);
    // ...but shortly after, all at once.
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 3; i++) {
      expect(find.text('Track $i.flac'), findsOneWidget);
    }

    soulseek.done.complete([for (var i = 0; i < 4; i++) _file(i)]);
    await tester.pump();
    expect(find.text('Track 3.flac'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Let the cover lookups (no network in tests) settle.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  });
}
