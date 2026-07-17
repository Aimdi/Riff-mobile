# NewPipeExtractor dependencies reference optional desktop-only classes
# that do not exist on Android; safe to ignore (same rules as the
# NewPipe app itself).
-dontwarn com.google.re2j.**
-dontwarn java.beans.**
-dontwarn javax.script.**

# Rhino (the JS engine NewPipeExtractor uses to solve YouTube's player
# challenges) constructs classes reflectively - keep it intact.
-keep class org.mozilla.javascript.** { *; }
-dontwarn org.mozilla.javascript.**

# NewPipeExtractor itself is reflection-heavy in places; keep it whole
# (a few hundred KB, worth the safety).
-keep class org.schabi.newpipe.extractor.** { *; }
-dontwarn org.schabi.newpipe.extractor.**
