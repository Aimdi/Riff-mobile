import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/utils/app_link_controller.dart' show ProcessLink;
import '/services/music_service.dart';

class SearchScreenController extends GetxController with ProcessLink {
  final textInputController = TextEditingController();
  final musicServices = Get.find<MusicServices>();
  final suggestionList = [].obs;
  final historyQuerylist = [].obs;
  late Box<dynamic> queryBox;
  final urlPasted = false.obs;

  // Desktop search bar related
  final focusNode = FocusNode();
  final isSearchBarInFocus = false.obs;

  Timer? _suggestionDebounce;
  int _suggestionGen = 0;

  @override
  onInit() {
    _init();
    super.onInit();
  }

  _init() async {
    if(GetPlatform.isDesktop){
      focusNode.addListener((){
        isSearchBarInFocus.value = focusNode.hasFocus;
      });
    }
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
      return;
    }
    _suggestionDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_fetchSuggestions(text));
    });
  }

  Future<void> _fetchSuggestions(String text) async {
    final gen = ++_suggestionGen;
    final results = await musicServices.getSearchSuggestion(text);
    if (gen != _suggestionGen) return;
    if (textInputController.text != text) return;
    suggestionList.value = results;
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
    if (historyQuerylist.length > 9) {
      final queryForRemoval = queryBox.getAt(0);
      await queryBox.deleteAt(0);
      historyQuerylist.removeWhere((element) => element == queryForRemoval);
    }
    if (!historyQuerylist.contains(txt)) {
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
  }

  Future<void> removeQueryFromHistory(String txt) async {
    final index = queryBox.values.toList().indexOf(txt);
    await queryBox.deleteAt(index);
    historyQuerylist.remove(txt);
  }

  Future<void> clearHistory() async {
    await queryBox.clear();
    historyQuerylist.clear();
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    focusNode.dispose();
    textInputController.dispose();
    queryBox.close();
    super.dispose();
  }
}
