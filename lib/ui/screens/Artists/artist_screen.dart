import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'artist_screen_controller.dart';
import 'spotify_artist_view.dart';

class ArtistScreen extends StatelessWidget {
  const ArtistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tag = key.hashCode.toString();
    final ArtistScreenController artistScreenController =
        Get.isRegistered<ArtistScreenController>(tag: tag)
            ? Get.find<ArtistScreenController>(tag: tag)
            : Get.put(ArtistScreenController(), tag: tag);
    // Radio lives in the artist page's own menu (no floating button).
    return Scaffold(
      body: SpotifyArtistView(controller: artistScreenController, tag: tag),
    );
  }
}
