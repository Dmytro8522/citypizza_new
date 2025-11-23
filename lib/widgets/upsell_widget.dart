// lib/widgets/upsell_widget.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/upsell_service.dart';
import '../services/cart_service.dart';

class UpSellWidget extends StatefulWidget {
  final String channel;
  final double subtotal;
  final VoidCallback? onItemAdded;
  final void Function(int itemId)? onItemTap;
  final bool autoCloseOnAdd;
  final List<Map<String, dynamic>>? initialItems; // если переданы, не грузим повторно
  final int? itemId; // текущая позиция для экрана деталей
  final Future<void> Function(Rect startRect)? onAnimateToCart;

  const UpSellWidget({
    super.key,
    required this.channel,
    required this.subtotal,
    this.onItemAdded,
    this.onItemTap,
    this.autoCloseOnAdd = false,
    this.initialItems,
    this.itemId,
    this.onAnimateToCart,
  });

  @override
  State<UpSellWidget> createState() => _UpSellWidgetState();
}

class _UpSellWidgetState extends State<UpSellWidget> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _grouped = [];
  bool _isGrouped = false;
  final Map<String, GlobalKey> _buttonKeys = {};
  final Set<String> _animating = <String>{};
  final Set<int> _expandedGroups = <int>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialItems != null) {
      _updateData(widget.initialItems!);
      _loading = false;
    } else {
      _loadUpsell();
    }
  }

  Future<void> _loadUpsell() async {
    final data = await UpSellService.fetchUpsell(
      channel: widget.channel,
      subtotal: widget.subtotal,
      userId: null,
      itemId: widget.itemId,
    );
    if (!mounted) return;
    setState(() {
      _updateData(data);
      _loading = false;
    });
  }

  void _updateData(List<Map<String, dynamic>> data) {
    final looksGrouped = data.isNotEmpty && data.first.containsKey('items');
    if (widget.itemId != null || looksGrouped) {
      _isGrouped = true;
      _grouped = data;
      _items = const <Map<String, dynamic>>[];
      _expandedGroups.clear();
    } else {
      _isGrouped = false;
      _items = data;
      _grouped = const <Map<String, dynamic>>[];
      _expandedGroups.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isGrouped && _grouped.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Keine Angebote',
            style: GoogleFonts.poppins(color: Colors.black54),
          ),
        ),
      );
    }

    if (!_isGrouped && _items.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Keine Angebote',
            style: GoogleFonts.poppins(color: Colors.black54),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
  border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Das könnte Ihnen gefallen',
              style: GoogleFonts.poppins(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_isGrouped)
            Column(
              children: [
                for (int i = 0; i < _grouped.length; i++)
                  _buildGroupSection(_grouped[i], isLast: i == _grouped.length - 1),
              ],
            )
          else
            Column(
              children: [
                for (final it in _items.length > 8 ? _items.take(8) : _items) _buildRow(it),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildGroupSection(Map<String, dynamic> group, {required bool isLast}) {
    final groupName = (group['group_name'] as String?)?.trim();
    final rawItems = (group['items'] as List?) ?? const [];
    final items = rawItems.cast<Map<String, dynamic>>();
    if (items.isEmpty) return const SizedBox.shrink();

    final gid = (group['group_id'] as int?) ?? 0;
    final isExpanded = _expandedGroups.contains(gid);
    final visibleItems = isExpanded ? items : items.take(3).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (groupName != null && groupName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                groupName,
                style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Column(
            children: [
              for (final it in visibleItems) _buildRow(it, groupId: gid),
            ],
          ),
          if (items.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6, right: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedGroups.remove(gid);
                      } else {
                        _expandedGroups.add(gid);
                      }
                    });
                  },
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: Text(
                    isExpanded ? 'Weniger anzeigen' : 'Mehr anzeigen',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Divider(
                color: Colors.black.withValues(alpha: 0.1),
                height: 1,
                thickness: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> it, {int? groupId}) {
    final price = ((it['price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2);
  final title = '${it['article'] != null ? '[${it['article']}] ' : ''}${it['name'] ?? ''}';
    final int itemId = (it['id'] as int?) ?? 0;
    final identity = groupId != null ? 'g${groupId}_$itemId' : 's_$itemId';
    final buttonKey = _buttonKeys.putIfAbsent(identity, () => GlobalKey());
    final isAnimating = _animating.contains(identity);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onItemTap?.call(((it['id'] as int?) ?? 0)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: const BoxDecoration(),
          child: Row(
            children: [
              // Название слева
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.black87,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.visible,
                ),
              ),
              const SizedBox(width: 8),
              // Цена по правому краю
              Text(
                '€$price',
                style: GoogleFonts.poppins(
                  color: Colors.black87,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              // Кнопка добавления
              InkWell(
                key: buttonKey,
                onTap: () async {
                  final contextForButton = buttonKey.currentContext;
                  if (contextForButton != null) {
                    final renderBox = contextForButton.findRenderObject() as RenderBox?;
                    if (renderBox != null) {
                      final offset = renderBox.localToGlobal(Offset.zero);
                      final rect = offset & renderBox.size;
                      if (mounted) {
                        setState(() => _animating.add(identity));
                      } else {
                        _animating.add(identity);
                      }
                      try {
                        final addFuture = CartService.addItemById(itemId);
                        final animationFuture = widget.onAnimateToCart?.call(rect);
                        await addFuture;
                        if (!mounted) return;
                        if (animationFuture != null) {
                          await animationFuture;
                          if (!mounted) return;
                        }
                        if (widget.autoCloseOnAdd) {
                          final rootNavigator = Navigator.of(context, rootNavigator: true);
                          if (rootNavigator.canPop()) {
                            rootNavigator.maybePop();
                          } else if (Navigator.of(context).canPop()) {
                            Navigator.of(context).maybePop();
                          }
                        }
                        widget.onItemAdded?.call();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hinzugefügt: ${it['name']}')),
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _animating.remove(identity));
                        } else {
                          _animating.remove(identity);
                        }
                      }
                      return;
                    }
                  }
                  await CartService.addItemById(itemId);
                  if (!mounted) return;
                  if (widget.autoCloseOnAdd) {
                    final rootNavigator = Navigator.of(context, rootNavigator: true);
                    if (rootNavigator.canPop()) {
                      rootNavigator.maybePop();
                    } else if (Navigator.of(context).canPop()) {
                      Navigator.of(context).maybePop();
                    }
                  }
                  widget.onItemAdded?.call();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hinzugefügt: ${it['name']}')),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isAnimating ? Colors.greenAccent : Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      isAnimating ? Icons.shopping_bag : Icons.add,
                      key: ValueKey<bool>(isAnimating),
                      size: 20,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
