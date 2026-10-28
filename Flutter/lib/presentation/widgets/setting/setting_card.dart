import 'package:flutter/material.dart';
import 'package:money/core/core.dart';

class SettingCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool wrap;

  const SettingCard({
    super.key,
    required this.title,
    required this.children,
    this.wrap = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: AppDimensions.margin * 0.70),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AppDimensions.padding * 0.85),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          SizedBox(height: 10),
          Material(
            color: wrap ? Colors.transparent : context.colors.surface,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: wrap ? Wrap(children: children) : Column(children: children),
          ),
        ],
      ),
    );
  }
}
