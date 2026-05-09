import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// 取当前运行环境的设备信息快照。
///
/// 用 `defaultTargetPlatform` + `kIsWeb` 而不是 `dart:io` 的 `Platform`，
/// 这样文件在 Flutter web 上也能编译。
Future<Map<String, dynamic>> getDeviceInfo() async {
  final deviceInfo = DeviceInfoPlugin();

  if (kIsWeb) {
    try {
      final info = await deviceInfo.webBrowserInfo;
      return {
        'platform': 'web',
        'browserName': info.browserName.name,
        'userAgent': info.userAgent ?? '',
        'appName': info.appName ?? '',
        'appVersion': info.appVersion ?? '',
      };
    } catch (_) {
      return const {'platform': 'web'};
    }
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      final info = await deviceInfo.androidInfo;
      return {
        'platform': 'android',
        'brand': info.brand,
        'model': info.model,
        'sdkInt': info.version.sdkInt,
        'release': info.version.release,
        'isPhysicalDevice': info.isPhysicalDevice,
      };
    case TargetPlatform.iOS:
      final info = await deviceInfo.iosInfo;
      return {
        'platform': 'ios',
        'name': info.name,
        'model': info.model,
        'systemVersion': info.systemVersion,
        'isPhysicalDevice': info.isPhysicalDevice,
      };
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      // 小写化与 android/ios 分支的硬编码字符串保持一致，
      // 也对齐 `_seedDeviceData()` 里的小写口径。
      return {'platform': defaultTargetPlatform.name.toLowerCase()};
  }
}
