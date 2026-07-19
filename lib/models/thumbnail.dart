import 'package:get/get.dart';

class Thumbnail {
  Thumbnail(this._url);
  final String _url;
  String sizewith(int size) => (_url.contains("-rj"))
      ? "${_url.split("=")[0]}=w$size-h$size-l90-rj"
      : (_url.contains("=s"))
          ? "${_url.split("=s")[0]}=s$size"
          : (_url.contains("i.yti") && size >= 600)
              ? url.replaceFirst("sddefault", "maxresdefault")
              : url;
  String get url => _url;
  String get high => sizewith(544); // was 400 — list tiles / medium art
  String get medium => sizewith(250); //350
  String get low => sizewith(150);
  /// Full-screen player, notification, and primary artwork.
  String get extraHigh =>
      GetPlatform.isDesktop ? sizewith(1200) : sizewith(800);
}
