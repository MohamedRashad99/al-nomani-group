import 'package:flutter/widgets.dart';

enum AppFormFactor { phone, tablet, desktop, largeDesktop }

class Breakpoints {
  static AppFormFactor of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (isPhoneSize(size)) return AppFormFactor.phone;
    if (size.width < 1024) return AppFormFactor.tablet;
    if (size.width < 1440) return AppFormFactor.desktop;
    return AppFormFactor.largeDesktop;
  }

  static bool isPhoneSize(Size size) =>
      size.shortestSide < 600 || size.width < 720;

  static bool isPhone(BuildContext context) =>
      isPhoneSize(MediaQuery.sizeOf(context));
}
