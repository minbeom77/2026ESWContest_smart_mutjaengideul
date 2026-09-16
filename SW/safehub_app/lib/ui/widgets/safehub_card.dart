import 'package:flutter/material.dart';

class SafeHubCard extends StatelessWidget {
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;

  const SafeHubCard({
    super.key,
    required this.child,
    this.height,
    this.padding = const EdgeInsets.all(30),
    this.backgroundColor = const Color(0xF7FFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x07000000),
            blurRadius: 22,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}
