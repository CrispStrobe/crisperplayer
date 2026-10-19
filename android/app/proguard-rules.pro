# Pigeon JNI looks up Kotlin suspend methods and runtime classes by literal
# JVM names. Java reachability and @Keep on plugin registrars cannot protect
# these Dart-side lookups. Preserve both descriptors and the coroutine helpers.
-keep,includedescriptorclasses class kotlin.coroutines.** { *; }
-keep,includedescriptorclasses interface kotlin.coroutines.** { *; }
-keep,includedescriptorclasses class kotlin.Result** { *; }
-keep,includedescriptorclasses class kotlin.Unit { *; }
-keep,includedescriptorclasses class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.** { *; }
-keep,includedescriptorclasses class io.flutter.plugins.pathprovider.** { *; }
