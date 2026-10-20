import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/utils/app_link_controller.dart' show ProcessLink;
import '/utils/helper.dart' show printERROR;
import '/services/explicit_content.dart';
import '/services/music_service.dart';
import '/services/search_recents.dart';
import '/services/search_suggestions.dart';
import '/ui/theme/riff_tokens.dart' show RiffDurations;

class SearchScreenController extends GetxController with ProcessLink {
  final textInputController = TextEditingController();
  final musicServices = Get.find<MusicServices>();
  final suggestionList = [].obs;

  /// The songs, artists, albums and playlists YouTube Music suggests for
  /// what's typed, to play or open straight away.
  final suggestedItems = <Object>[].obs;
  final historyQuerylist = [].obs;
  late Box<dynamic> queryBox;
  final urlPasted = false.obs;

  Timer? _suggestionDebounce;
  int _suggestionGen = 0;

  @override
  onInit() {
    _init();
    super.onInit();
  }

  _init() async {
    queryBox = await Hive.openBox("searchQuery");
    historyQuerylist.value = queryBox.values.toList().reversed.toList();
  }

  Future<void> onChanged(String text) async {
    if(text.contains("https://")){
      urlPasted.value = true;
      _suggestionDebounce?.cancel();
      return;
    }
    urlPasted.value = false;
    _suggestionDebounce?.cancel();
    if (text.isEmpty) {
      suggestionList.clear();
      suggestedItems.clear();
      return;
    }
    _suggestionDebounce = Timer(RiffDurations.typingPause, () {
      unawaited(_fetchSuggestions(text));
    });
  }

  Future<void> _fetchSuggestions(String text) async {
    final gen = ++_suggestionGen;
    final SearchSuggestions results;
    try {
      results = await musicServices.getSearchSuggestions(text);
    } catch (e) {
      // Offline or a bad reply: keep what is shown. This runs from a timer,
      // so a throw here was an uncaught error on every debounced keystroke.
      printERROR('Search suggestions for "$text" failed: $e');
      return;
    }
    if (isClosed || gen != _suggestionGen) return;
    if (textInputController.text != text) return;
    // Copies: clearing them later mustn't empty (or, for a const list,
    // throw on) the answer's own lists. Explicit songs left out when
    // explicit content is off, as suggestions leave them out.
    suggestionList.value = List.of(results.queries);
    suggestedItems.value = ExplicitContent.filter(List.of(results.items));
  }

  Future<void> suggestionInput(String txt) async {
    textInputController.text = txt;
    textInputController.selection =
        TextSelection.collapsed(offset: textInputController.text.length);
    _suggestionDebounce?.cancel();
    urlPasted.value = false;
    await _fetchSuggestions(txt);
  }

  Future<void> addToHistryQueryList(String txt) async {
    // Search history paused: nothing kept (the field still resets).
    if (!SearchRecents.paused.value) {
      // Searched again: back to the top, not kept twice.
      final i = queryBox.values.toList().lastIndexOf(txt);
      if (i >= 0) await queryBox.deleteAt(i);
      historyQuerylist.remove(txt);
      if (queryBox.length > 9) {
        final queryForRemoval = queryBox.getAt(0);
        await queryBox.deleteAt(0);
        historyQuerylist.removeWhere((element) => element == queryForRemoval);
      }
      await queryBox.add(txt);
      historyQuerylist.insert(0, txt);
    }

    //reset current query and suggestionlist
    reset();
  }

  void reset() {
    _suggestionDebounce?.cancel();
    urlPasted.value = false;
    textInputController.text = "";
    suggestionList.clear();
    suggestedItems.clear();
  }

  Future<void> removeQueryFromHistory(String txt) async {
    final index = queryBox.values.toList().indexOf(txt);
    if (index >= 0) await queryBox.deleteAt(index);
    historyQuerylist.remove(txt);
  }

  Future<void> clearHistory() async {
    await queryBox.clear();
    historyQuerylist.clear();
  }

  // GetX calls onClose (not dispose) when the Search route is removed.
  // The small "searchQuery" box stays open: the next visit's controller
  // would otherwise race this close and get the same, now-closed instance.
  @override
  void onClose() {
    _suggestionDebounce?.cancel();
    textInputController.dispose();
    super.onClose();
  }
}
