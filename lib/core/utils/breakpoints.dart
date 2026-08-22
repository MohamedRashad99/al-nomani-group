import 'package:flutter/widgets.dart';

enum AppFormFactor { phone, tablet, desktop, largeDesktop }

class Breakpoints {
  static AppFormFactor of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return AppFormFactor.phone;
    if (width < 1024) return AppFormFactor.tablet;
    if (width < 1440) return AppFormFactor.desktop;
    return AppFormFactor.largeDesktop;
  }

  static bool isPhone(BuildContext context) =>
      of(context) == AppFormFactor.phone;
}
