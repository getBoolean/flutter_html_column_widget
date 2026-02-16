import 'package:flutter/foundation.dart';

@immutable
class HtmlCssWarning {
  const HtmlCssWarning({
    required this.code,
    required this.message,
    this.selector,
    this.property,
    this.value,
    this.source,
  });

  final String code;
  final String message;
  final String? selector;
  final String? property;
  final String? value;
  final String? source;

  @override
  String toString() {
    final parts = <String>[
      '[HtmlCssWarning:$code] $message',
      if (selector != null) 'selector=$selector',
      if (property != null) 'property=$property',
      if (value != null) 'value=$value',
      if (source != null) 'source=$source',
    ];
    return parts.join(' | ');
  }
}
