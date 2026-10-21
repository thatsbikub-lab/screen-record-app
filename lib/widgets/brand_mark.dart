import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .31),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xff53E3C2), Color(0xff6088FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.radio_button_checked_rounded,
          size: size * .53, color: const Color(0xff08111E)),
    );
  }
}


