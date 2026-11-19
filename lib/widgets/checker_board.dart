import 'package:flutter/material.dart';

/// 棋盘格背景，用来直观展示抠图后的透明区域。
class CheckerBoard extends StatelessWidget {
  const CheckerBoard({super.key, required this.child, this.cell = 14});

  final Widget child;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _CheckerPainter(
        a: dark ? const Color(0xFF2B2B2B) : const Color(0xFFE6E6E6),
        b: dark ? const Color(0xFF383838) : const Color(0xFFF8F8F8),
        cell: cell,
      ),
      child: child,
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter({required this.a, required this.b, required this.cell});

  final Color a;
  final Color b;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final paint = Paint()..color = b;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c).isOdd) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) =>
      old.a != a || old.b != b || old.cell != cell;
}
