import 'package:flutter/widgets.dart';
import '../../crash_sdk.dart';

/// 自动把页面跳转写成面包屑。
///
/// 用法：
/// ```dart
/// MaterialApp(
///   navigatorObservers: [BreadcrumbNavigatorObserver()],
///   ...
/// );
/// ```
class BreadcrumbNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    XCrashSDK.leaveBreadcrumb(
      category: 'navigation',
      message: 'push ${_name(route)}',
      data: {
        'to': _name(route),
        'from': _name(previousRoute),
      },
    );
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    XCrashSDK.leaveBreadcrumb(
      category: 'navigation',
      message: 'pop ${_name(route)}',
      data: {
        'from': _name(route),
        'to': _name(previousRoute),
      },
    );
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    XCrashSDK.leaveBreadcrumb(
      category: 'navigation',
      message: 'replace ${_name(oldRoute)} -> ${_name(newRoute)}',
      data: {
        'from': _name(oldRoute),
        'to': _name(newRoute),
      },
    );
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    XCrashSDK.leaveBreadcrumb(
      category: 'navigation',
      message: 'remove ${_name(route)}',
    );
  }

  String? _name(Route? r) =>
      r?.settings.name ?? r?.runtimeType.toString();
}
