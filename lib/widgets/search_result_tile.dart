import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/menu_item.dart';
import '../theme/theme_provider.dart';
import '../theme/app_theme.dart';
import '../services/discount_service.dart';
import 'price_with_promotion.dart';

class SearchResultTile extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  final String query;
  final String? categoryName;
  final PromotionPrice? priceInfo;

  const SearchResultTile({super.key, required this.item, required this.onTap, required this.query, this.categoryName, this.priceInfo});

  @override
  Widget build(BuildContext context) {
    final AppTheme appTheme = ThemeProvider.of(context);
    final priceContent = _buildPriceContent(appTheme);
    final titleStyle = GoogleFonts.poppins(
      color: appTheme.textColor,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    );
    final highlightStyle = GoogleFonts.poppins(
      color: appTheme.primaryColor,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: appTheme.cardColor.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (categoryName != null && categoryName!.trim().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Text(
                      categoryName!,
                      style: GoogleFonts.poppins(
                        color: appTheme.textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                _buildHighlightedTitle(item.name, query, titleStyle, highlightStyle),
                if (item.description != null && item.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      item.description!,
                      style: GoogleFonts.poppins(
                        color: appTheme.textColorSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (priceContent != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: appTheme.primaryColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: priceContent,
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: appTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PromotionPrice? get _resolvedPriceInfo {
    if (priceInfo != null) return priceInfo;
    double? fallback;
    if (item.hasMultipleSizes) {
      fallback = item.minPrice > 0 ? item.minPrice : null;
    } else {
      fallback = item.singleSizePrice ?? (item.minPrice > 0 ? item.minPrice : null);
    }
    if (fallback == null) return null;
    return PromotionPrice(
      basePrice: fallback,
      finalPrice: fallback,
      discountAmount: 0,
      promotion: null,
      target: null,
    );
  }

  Widget? _buildPriceContent(AppTheme appTheme) {
    final info = _resolvedPriceInfo;
    if (info == null) return null;
    final formatter = (double value) => '${value.toStringAsFixed(2)} €';
    final finalStyle = GoogleFonts.poppins(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );
    final baseStyle = finalStyle.copyWith(
      decoration: TextDecoration.lineThrough,
      color: Colors.white.withValues(alpha: 0.7),
    );

    Widget content = PriceWithPromotion(
      basePrice: info.basePrice,
      finalPrice: info.finalPrice,
      finalStyle: finalStyle,
      baseStyle: baseStyle,
      formatter: formatter,
    );

    if (item.hasMultipleSizes && info.basePrice > 0) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ab ', style: finalStyle),
          content,
        ],
      );
    }
    return content;
  }

  Widget _buildHighlightedTitle(String text, String query, TextStyle base, TextStyle highlight) {
    if (query.trim().isEmpty) {
      return Text(text, style: base, maxLines: 3, overflow: TextOverflow.ellipsis, softWrap: true);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start), style: base));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: base));
      }
      spans.add(TextSpan(text: text.substring(idx, idx + lowerQuery.length), style: highlight));
      start = idx + lowerQuery.length;
    }
    return RichText(
      text: TextSpan(children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
