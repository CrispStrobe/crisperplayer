# Native JNI entry points use these class and method names. Keep them in R8
# release builds; renaming would break only the opt-in DSP loading path.
-keep class com.ryanheise.just_audio.JniCrisperDspEngine { *; }
