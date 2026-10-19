# Pigeon JNI looks up Kotlin suspend methods with literal JVM descriptors.
# @Keep on plugin registrars preserves the method but not its parameter types:
# renaming Continuation breaks SharedPreferences.getInstance() at startup.
# Preserve descriptor types as well, while leaving the rest of R8 enabled.
-keep,includedescriptorclasses interface kotlin.coroutines.Continuation { *; }
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.** { *; }
-keep,includedescriptorclasses class io.flutter.plugins.pathprovider.** { *; }
