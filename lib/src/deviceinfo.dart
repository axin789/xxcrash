import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

Future<Map<String, dynamic>> getDeviceInfo() async {
  final deviceInfo = DeviceInfoPlugin();

  if (Platform.isAndroid) {
    final info = await deviceInfo.androidInfo;
    return {
      'platform': 'android',
      'brand': info.brand,
      'model': info.model,
      'sdkInt': info.version.sdkInt,
      'release': info.version.release,
      'isPhysicalDevice': info.isPhysicalDevice,
    };
  }

  if (Platform.isIOS) {
    final info = await deviceInfo.iosInfo;
    return {
      'platform': 'ios',
      'name': info.name,
      'model': info.model,
      'systemVersion': info.systemVersion,
      'isPhysicalDevice': info.isPhysicalDevice,
    };
  }

  return {
    'platform': Platform.operatingSystem,
  };
}
