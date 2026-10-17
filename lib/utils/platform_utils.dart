import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

bool get isWeb => kIsWeb;
bool get isAndroid => !kIsWeb && Platform.isAndroid;
bool get isIOS => !kIsWeb && Platform.isIOS;
bool get isMacOS => !kIsWeb && Platform.isMacOS;
bool get isWindows => !kIsWeb && Platform.isWindows;
bool get isLinux => !kIsWeb && Platform.isLinux;
bool get isDesktop => isMacOS || isWindows || isLinux;
bool get isMobile => isAndroid || isIOS;
