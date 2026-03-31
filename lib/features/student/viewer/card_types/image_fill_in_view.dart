import 'package:flutter/material.dart';

import '../../../../domain/cards/card_types.dart';
import '../../../../domain/models/card_item.dart';
import '../../../../domain/models/image_annotation.dart';

class ImageFillInCardView extends StatefulWidget {
  const ImageFillInCardView({
    super.key,
    required this.card,
    required this.imageUrl,
    required this.onResultChanged,
  });

  final CardItem card;
  final String? imageUrl;
  final ValueChanged<bool?> onResultChanged;

  @override
  State<ImageFillInCardView> createState() => _ImageFillInCardViewState();
}

class _ImageFillInCardViewState extends State<ImageFillInCardView> {
  final TextEditingController _answer = TextEditingController();

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _check() {
    final decoded = ImageFillInCardData.tryDecode(widget.card.cardDataJson);
    final accepted = decoded?.acceptedAnswers ?? const <String>[];
    final normalized = normalizeAnswer(_answer.text);
    final ok = accepted.any((a) => normalizeAnswer(a) == normalized);
    widget.onResultChanged(ok);
  }

  @override
  Widget build(BuildContext context) {
    final decoded = ImageFillInCardData.tryDecode(widget.card.cardDataJson);
    final prompt = (decoded?.prompt ?? '').trim();

    final String? imageUrl = widget.imageUrl;
    final ann = ImageAnnotations.tryParse(widget.card.imageAnnotationsJson);

    Widget image() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: imageUrl == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      (widget.card.title == null || widget.card.title!.trim().isEmpty)
                          ? '(zonder titel)'
                          : widget.card.title!.trim(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(child: Text('Afbeelding laden mislukt'));
                      },
                    ),
                    if (ann != null && ann.items.isNotEmpty)
                      CustomPaint(
                        painter: _ImageAnnotOverlayPainter(items: ann.items),
                      ),
                  ],
                ),
        ),
      );
    }

    Widget controls({required bool centerText}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (prompt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                prompt,
                textAlign: centerText ? TextAlign.center : TextAlign.start,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          TextField(
            controller: _answer,
            textInputAction: TextInputAction.done,
            onChanged: (_) => widget.onResultChanged(null),
            onSubmitted: (_) => _check(),
            decoration: const InputDecoration(
              labelText: 'Antwoord',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _check,
            child: const Text('Controleer'),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: AspectRatio(
                aspectRatio: 1,
                child: image(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        controls(centerText: true),
      ],
    );
  }
}

// Small copy of the overlay painter used by CardViewerScreen.
class _ImageAnnotOverlayPainter extends CustomPainter {
  const _ImageAnnotOverlayPainter({required this.items});

  final List<ImageAnnotationItem> items;

  @override
  void paint(Canvas canvas, Size size) {
    for (final it in items) {
      if (it is ArrowAnnotation) {
        _paintArrow(canvas, size, it);
      } else if (it is TextAnnotation) {
        _paintText(canvas, size, it);
      }
    }
  }

  void _paintArrow(Canvas canvas, Size size, ArrowAnnotation a) {
    final p1 = Offset(a.fromX * size.width, a.fromY * size.height);
    final p2 = Offset(a.toX * size.width, a.toY * size.height);
    final dir = (p2 - p1);
    if (dir.distance < 4) return;

    final u = dir / dir.distance;
    final n = Offset(-u.dy, u.dx);

    final thickness = a.widthRel != null
        ? (a.widthRel! * (size.shortestSide)).clamp(2.0, 100.0)
        : (a.width <= 0 ? 2.0 : a.width.toDouble());
    final headLen = thickness * 4.0;
    final headWidth = thickness * 3.0;
    final base = p2 - u * headLen;

    final halfShaft = thickness / 2;
    final halfHead = headWidth / 2;

    final shaftLeftStart = p1 + n * halfShaft;
    final shaftRightStart = p1 - n * halfShaft;
    final shaftLeftEnd = base + n * halfShaft;
    final shaftRightEnd = base - n * halfShaft;
    final headLeft = base + n * halfHead;
    final headRight = base - n * halfHead;

    final path = Path()
      ..moveTo(shaftLeftStart.dx, shaftLeftStart.dy)
      ..lineTo(shaftLeftEnd.dx, shaftLeftEnd.dy)
      ..lineTo(headLeft.dx, headLeft.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(headRight.dx, headRight.dy)
      ..lineTo(shaftRightEnd.dx, shaftRightEnd.dy)
      ..lineTo(shaftRightStart.dx, shaftRightStart.dy)
      ..close();

    final fillPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (thickness * 0.35).clamp(2.0, 20.0)
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, outlinePaint);
  }

  void _paintText(Canvas canvas, Size size, TextAnnotation t) {
    final pos = Offset(t.atX * size.width, t.atY * size.height);
    final style = TextStyle(
      color: _parseHex(t.colorHex, fallback: const Color(0xFF000000)),
      fontSize: t.sizeRel != null ? (t.sizeRel! * size.shortestSide).clamp(10.0, 120.0) : t.size,
      fontWeight: FontWeight.w700,
      shadows: const <Shadow>[Shadow(blurRadius: 2, offset: Offset(0, 1))],
    );
    final painter = TextPainter(
      text: TextSpan(text: t.text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: size.width);
    painter.paint(canvas, pos);
  }

  Color _parseHex(String hex, {required Color fallback}) {
    final h = hex.trim();
    if (!h.startsWith('#')) return fallback;
    final raw = h.substring(1);
    final v = int.tryParse(raw, radix: 16);
    if (v == null) return fallback;
    if (raw.length == 6) return Color(0xFF000000 | v);
    if (raw.length == 8) return Color(v);
    return fallback;
  }

  @override
  bool shouldRepaint(covariant _ImageAnnotOverlayPainter oldDelegate) {
    return oldDelegate.items != items;
  }
}

