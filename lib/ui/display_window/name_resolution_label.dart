import 'package:flutter/material.dart';

/// Bottom-right "Name · W×H" label (R-6, SPEC §9.4 item 4).
class NameResolutionLabel extends StatelessWidget {
  const NameResolutionLabel({super.key, required this.text, this.semanticsLabel});

  final String text;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: IgnorePointer(
        child: LayoutBuilder(builder: (context, _) {
          final maxWidth = MediaQuery.sizeOf(context).width * 0.6;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Semantics(
              label: semanticsLabel,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
