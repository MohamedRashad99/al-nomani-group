import 'package:flutter/material.dart';

class ReportBusyBarrier extends StatelessWidget {
  const ReportBusyBarrier({
    super.key,
    required this.busy,
    required this.child,
  });

  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66F4F1EA),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
