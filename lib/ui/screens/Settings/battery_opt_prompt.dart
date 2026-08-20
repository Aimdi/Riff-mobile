/// One-time Android prompt so background radio / downloads are not killed.
bool shouldPromptBatteryOptimization({
  required bool isAndroid,
  required bool alreadyGranted,
  required bool alreadyShown,
}) =>
    isAndroid && !alreadyGranted && !alreadyShown;
