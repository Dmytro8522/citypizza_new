import 'package:flutter/material.dart';

/// Displays a price with an optional promotional value. When a promotion is
/// active the original price is shown with a strikethrough decoration and the
/// discounted price is rendered next to it.
class PriceWithPromotion extends StatelessWidget {
  const PriceWithPromotion({
    super.key,
    required this.basePrice,
    required this.finalPrice,
    this.baseStyle,
    this.finalStyle,
    this.formatter,
    this.spacing = 6,
    this.alignment = MainAxisAlignment.start,
  });

  /// Original unit price before the promotion.
  final double basePrice;

  /// Final unit price after the promotion has been applied.
  final double finalPrice;

  /// Custom style for the original (strikethrough) price.
  final TextStyle? baseStyle;

  /// Custom style for the final (active) price.
  final TextStyle? finalStyle;

  /// Optional formatter. When omitted values are formatted as `12.34 €`.
  final String Function(double value)? formatter;

  /// Horizontal spacing between the original and discounted price.
  final double spacing;

  /// Alignment applied to the Row.
  final MainAxisAlignment alignment;

  bool get _hasDiscount => finalPrice < basePrice - 0.0005;

  @override
  Widget build(BuildContext context) {
    final resolvedFormatter = formatter ?? _defaultFormatter;
    final resolvedFinalStyle = finalStyle ?? Theme.of(context).textTheme.bodyMedium;
    final resolvedBaseStyle = _resolveBaseStyle(resolvedFinalStyle);

    if (!_hasDiscount) {
      return Text(
        resolvedFormatter(finalPrice),
        style: resolvedFinalStyle,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignment,
      children: [
        Text(
          resolvedFormatter(basePrice),
          style: resolvedBaseStyle,
        ),
        SizedBox(width: spacing),
        Text(
          resolvedFormatter(finalPrice),
          style: resolvedFinalStyle,
        ),
      ],
    );
  }

  TextStyle? _resolveBaseStyle(TextStyle? resolvedFinalStyle) {
    final base = baseStyle ?? resolvedFinalStyle;
    if (base == null) return const TextStyle(decoration: TextDecoration.lineThrough);
    final color = base.color ?? resolvedFinalStyle?.color;
    return base.copyWith(
      decoration: TextDecoration.lineThrough,
      color: color != null ? color.withOpacity(0.7) : null,
    );
  }

  String _defaultFormatter(double value) => '${value.toStringAsFixed(2)} €';
}
