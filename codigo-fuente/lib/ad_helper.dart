import 'package:flutter/foundation.dart';

class AdHelper {
  static String get bannerAdUnitId {
    if (kIsWeb) {
      return ''; // No ads on web for now or use a different system
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'ca-app-pub-3163714257793874/8783892749'; // Real ID
      case TargetPlatform.iOS:
        return 'ca-app-pub-3940256099942544/2934735716'; // Test ID
      default:
        return '';
    }
  }
}
