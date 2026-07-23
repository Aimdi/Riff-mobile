import 'package:harmonymusic/services/stream_service.dart'show Audio;

class HMStreamingData {
  final bool playable;
  final String statusMSG;
  final Audio? lowQualityAudio;
  final Audio? highQualityAudio;
  int qualityIndex = 1;
  HMStreamingData({
    required this.playable,
    required this.statusMSG,
    this.lowQualityAudio,
    this.highQualityAudio,
  });

  setQualityIndex(int index) {
    qualityIndex = index;
  }

  Audio? get audio => qualityIndex == 0 ? lowQualityAudio : highQualityAudio;

  factory HMStreamingData.fromJson(json) {
    final playable = json['playable'] == true;
    final statusMSG = (json['statusMSG'] ?? '').toString();
    if (!playable) {
      return HMStreamingData(
        playable: false,
        statusMSG: statusMSG.isEmpty ? "streamLoadFailed" : statusMSG,
      );
    }
    final lowRaw = json['lowQualityAudio'];
    final highRaw = json['highQualityAudio'];
    // Prefer whichever quality parsed; fall back so a partial payload
    // still plays instead of throwing into streamLoadFailed.
    Audio? low;
    Audio? high;
    try {
      if (lowRaw != null) low = Audio.fromJson(lowRaw);
    } catch (_) {}
    try {
      if (highRaw != null) high = Audio.fromJson(highRaw);
    } catch (_) {}
    low ??= high;
    high ??= low;
    if (low == null || high == null) {
      return HMStreamingData(
        playable: false,
        statusMSG: statusMSG.isEmpty ? "streamLoadFailed" : statusMSG,
      );
    }
    return HMStreamingData(
        playable: true,
        statusMSG: statusMSG.isEmpty ? "OK" : statusMSG,
        lowQualityAudio: low,
        highQualityAudio: high);
  }

  Map<String, dynamic> toJson() => {
        "playable": playable,
        "statusMSG": statusMSG,
        "lowQualityAudio": lowQualityAudio?.toJson(),
        "highQualityAudio": highQualityAudio?.toJson(),
      };
}
