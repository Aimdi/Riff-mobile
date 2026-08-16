/// Skip must close video mode first so the audio pipeline owns the next track.
bool shouldHandoffVideoBeforeSkip(bool videoActive) => videoActive;

/// A failed video enable must restart audio when we paused it for the switch
/// (or a prior disable(resume: false) already paused a playing session).
bool shouldResumeAudioAfterVideoEnableFailed({
  required bool videoActive,
  required bool wasPlayingBeforeAttempt,
}) =>
    !videoActive && wasPlayingBeforeAttempt;

/// Skip-next advanced when the target index is a different track.
bool skipNextDidAdvance({
  required int fromIndex,
  required int toIndex,
}) =>
    toIndex != fromIndex;
