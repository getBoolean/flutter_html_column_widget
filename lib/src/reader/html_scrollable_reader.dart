import 'dart:async';

import 'package:flutter/material.dart' show SelectionArea, Theme;
import 'package:flutter/widgets.dart';

import '../spec/html/model/html_nodes.dart';
import '../spec/html/parsing/html_content_parser.dart';
import '../spec/html/rendering/html_block_widgets.dart';

typedef HtmlScrollableRefTapCallback =
    FutureOr<String?> Function(
      HtmlReference reference, {
      required Future<void> Function(String fragmentId) scrollToFragment,
    });

/// A vertically scrolling HTML reader that renders parsed blocks in a ListView.
///
/// This widget is useful for browser-style reading where pagination is not
/// needed, while keeping the same block rendering behavior as [HtmlColumnReader].
class HtmlScrollableReader extends StatefulWidget {
  const HtmlScrollableReader({
    super.key,
    required this.html,
    this.padding = const EdgeInsets.all(16),
    this.blockSpacing = 12,
    this.textStyle,
    this.headingStyles = const <int, TextStyle>{},
    this.onRefTap,
    this.onMessage,
    this.onImageTap,
    this.imageBuilder,
    this.imageBytesBuilder,
    this.parser,
    this.externalCss,
    this.externalCssResolver,
    this.blockBuilder,
    this.scrollController,
  }) : assert(blockSpacing >= 0, 'blockSpacing must be >= 0');

  final String html;
  final EdgeInsetsGeometry padding;
  final double blockSpacing;
  final TextStyle? textStyle;
  final Map<int, TextStyle> headingStyles;
  final HtmlScrollableRefTapCallback? onRefTap;
  final ValueChanged<String>? onMessage;
  final HtmlImageTapCallback? onImageTap;
  final HtmlImageBuilder? imageBuilder;
  final HtmlImageBytesBuilder? imageBytesBuilder;
  final HtmlContentParser? parser;
  final String? externalCss;
  final String? Function(String href)? externalCssResolver;
  final Widget? Function(BuildContext context, HtmlBlockNode block)?
  blockBuilder;
  final ScrollController? scrollController;

  @override
  State<HtmlScrollableReader> createState() => _HtmlScrollableReaderState();
}

class _HtmlScrollableReaderState extends State<HtmlScrollableReader> {
  final ScrollController _ownedScrollController = ScrollController();
  final HtmlContentParser _defaultParser = HtmlContentParser();
  final Map<String, GlobalKey> _anchorKeys = <String, GlobalKey>{};
  String? _lastDocumentToken;

  ScrollController get _effectiveScrollController =>
      widget.scrollController ?? _ownedScrollController;

  @override
  void dispose() {
    _ownedScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final html = widget.html;
    if (html.isEmpty) {
      return const SizedBox.shrink();
    }

    final documentToken = '$html::${widget.externalCss ?? ''}'.hashCode;
    if (documentToken.toString() != _lastDocumentToken) {
      _lastDocumentToken = documentToken.toString();
      _anchorKeys.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = _effectiveScrollController;
        if (controller.hasClients) {
          controller.jumpTo(0);
        }
      });
    }

    final parser = widget.parser ?? _defaultParser;
    final blocks = parser.parse(
      html,
      externalCss: widget.externalCss,
      externalCssResolver: widget.externalCssResolver,
    );
    final baseStyle =
        widget.textStyle ?? Theme.of(context).textTheme.bodyMedium!;

    return SelectionArea(
      child: ListView.separated(
        controller: _effectiveScrollController,
        padding: widget.padding,
        itemCount: blocks.length,
        separatorBuilder: (context, index) =>
            SizedBox(height: widget.blockSpacing),
        itemBuilder: (context, index) {
          final block = blocks[index];
          final blockKey = _keyForAnchor(block.id);
          final view = HtmlBlockView(
            block: block,
            blockContext: HtmlBlockContext(
              baseStyle: baseStyle,
              headingStyles: widget.headingStyles,
              onRefTap: _handleRefTap,
              onImageTap: widget.onImageTap,
              imageBuilder: widget.imageBuilder,
              imageBytesBuilder: widget.imageBytesBuilder,
            ),
            builder: widget.blockBuilder,
          );
          if (blockKey == null) {
            return view;
          }
          return KeyedSubtree(key: blockKey, child: view);
        },
      ),
    );
  }

  void _handleRefTap(HtmlReference reference) {
    final callback = widget.onRefTap;
    if (callback == null) {
      final raw = reference.raw.trim();
      final fragmentId = reference.fragmentId;
      if (raw.startsWith('#') && fragmentId != null && fragmentId.isNotEmpty) {
        unawaited(_scrollToFragment(fragmentId));
      }
      return;
    }
    unawaited(
      Future<String?>.value(
        callback(reference, scrollToFragment: _scrollToFragment),
      ).then((message) {
        if (message != null && message.isNotEmpty) {
          widget.onMessage?.call(message);
        }
      }),
    );
  }

  GlobalKey? _keyForAnchor(String? id) {
    if (id == null || id.trim().isEmpty) {
      return null;
    }
    return _anchorKeys.putIfAbsent(id, GlobalKey.new);
  }

  Future<void> _scrollToFragment(String fragmentId) async {
    final key = _anchorKeys[fragmentId];
    if (key == null) {
      widget.onMessage?.call('Anchor not found: #$fragmentId');
      return;
    }
    final anchorContext = key.currentContext;
    if (anchorContext == null) {
      widget.onMessage?.call('Anchor not visible yet: #$fragmentId');
      return;
    }
    await Scrollable.ensureVisible(
      anchorContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: 0.08,
    );
  }
}
