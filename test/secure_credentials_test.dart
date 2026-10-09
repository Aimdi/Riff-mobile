import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/secure_credentials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late int readAlls;

  void answer(Object? Function() readAll) {
    readAlls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readAll') {
        readAlls++;
        return readAll();
      }
      return null;
    });
  }

  setUp(SecureCredentials.resetForTest);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    SecureCredentials.resetForTest();
  });

  test('a prefetched read is the one init uses', () async {
    answer(() => {'listenBrainzToken': 'tok', 'unrelated': 'x'});
    SecureCredentials.prefetch();
    SecureCredentials.prefetch(); // a second call starts nothing new
    await SecureCredentials.init();
    expect(readAlls, 1);
    expect(SecureCredentials.ready, isTrue);
    expect(SecureCredentials.get('listenBrainzToken'), 'tok');
    expect(SecureCredentials.get('unrelated'), isNull);
  });

  test('init still reads by itself without a prefetch', () async {
    answer(() => {'webdavSync.password': 'pw'});
    await SecureCredentials.init();
    expect(readAlls, 1);
    expect(SecureCredentials.nested('webdavSync', 'password'), 'pw');
  });

  test('a failed prefetch is handled in init, not thrown', () async {
    answer(() => throw PlatformException(code: 'keystore'));
    SecureCredentials.prefetch();
    // Let the failure land before anyone awaits it.
    await Future<void>.delayed(Duration.zero);
    await SecureCredentials.init();
    expect(SecureCredentials.ready, isTrue);
    expect(SecureCredentials.get('listenBrainzToken'), isNull);
  });
}
