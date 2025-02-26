import 'package:flutter/material.dart';

extension WidgetExtension on Widget {
  Widget asButton({required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: this,
      ),
    );
  }

  Widget paddingLeft(double value) {
    return Padding(
      padding: EdgeInsets.only(left: value),
      child: this,
    );
  }
} 