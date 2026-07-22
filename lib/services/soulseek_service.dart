import 'dart:io';

import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'soulseek/soulseek_client.dart';

export 'soulseek/soulseek_client.dart'
    show SoulseekFile, SoulseekException, SoulseekClient;

/// In-app Soulseek client (like Seeker): login with your Soulseek account,
/// search the network, download to device storage. No remote slskd required.
class SoulseekService extends GetxController {
  SoulseekClient? _client;

  static const _userKey = 'soulseekUser';
  static const _passKey = 'soulseekPass';

  final isLoggedIn = false.obs;
  final username = ''.obs;
  final statusMessage = ''.obs;
  final isBusy = false.obs;

  Box get _prefs => Hive.box('AppPrefs');

  @override
  void onInit() {
    super.onInit();
    final user = (_prefs.get(_userKey) ?? '').toString();
    if (user.isNotEmpty) {
      username.value = user;
      // Auto-reconnect with stored credentials (best-effort).
      final pass = (_prefs.get(_passKey) ?? '').toString();
      if (pass.isNotEmpty) {
        login(user: user, pass: pass).catchError((_) {});
      }
    }
  }

  @override
  void onClose() {
    _client?.disconnect();
    super.onClose();
  }

  Future<void> login({required String user, required String pass}) async {
    isBusy.value = true;
    statusMessage.value = '';
    try {
      final client = SoulseekClient();
      await client.connectAndLogin(user: user, pass: pass);
      await _client?.disconnect();
      _client = client;
      username.value = user.trim();
      isLoggedIn.value = true;
      await _prefs.put(_userKey, user.trim());
      await _prefs.put(_passKey, pass);
      statusMessage.value = '';
    } on SoulseekException catch (e) {
      isLoggedIn.value = false;
      statusMessage.value = e.message;
      rethrow;
    } catch (_) {
      isLoggedIn.value = false;
      statusMessage.value = 'soulseekLoginFailed'.tr;
      rethrow;
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> logout() async {
    await _client?.disconnect();
    _client = null;
    isLoggedIn.value = false;
    await _prefs.delete(_passKey);
    // Keep username for convenience.
  }

  Future<List<SoulseekFile>> search(String query) async {
    final c = _client;
    if (c == null || !c.loggedIn) {
      throw SoulseekException('soulseekNotLoggedIn');
    }
    return c.search(query);
  }

  Future<File> download(SoulseekFile file) async {
    final c = _client;
    if (c == null || !c.loggedIn) {
      throw SoulseekException('soulseekNotLoggedIn');
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/soulseek');
    return c.download(file, saveDirectory: dir.path);
  }
}
