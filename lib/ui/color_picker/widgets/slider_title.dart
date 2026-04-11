import 'package:flutter/material.dart';

class SliderTitle extends StatelessWidget {
  const SliderTitle(
    this.title,
    this.text, {
    super.key,
  });

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.bottomCenter,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8B92A5),
            ),
          ),
          const Spacer(),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF60A5FA),
            ),
          ),
        ],
      ),
    );
  }
}
