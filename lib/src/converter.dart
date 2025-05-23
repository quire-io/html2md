import 'package:html/dom.dart' as dom;

import 'node.dart';
import 'options.dart' show updateStyleOptions;
import 'rules.dart' show Rule;
import 'utils.dart' as util;

final Set<Rule> _appendRuleSet = <Rule>{};
final Map<String, String> _customOptions = <String, String>{};

final _leadingNewLinesRegExp = RegExp(r'^\n*');
final _trailingNewLinesRegExp = RegExp(r'\n*$');

/// Convert [input] to markdown text.
///
/// The [input] can be an html string or a [dom.Node](https://pub.dev/documentation/html/latest/dom/Node-class.html).
/// The root tag which should be converted can be set with [rootTag].
/// The image base url can be set with [imageBaseUrl].
/// Style options can be set with [styleOptions].
///
/// The default and available style options:
///
/// | Name        | Default           | Options  |
/// | ------------- |:-------------:| -----:|
/// | headingStyle      | "setext" | "setext", "atx" |
/// | hr      | "* * *" | "* * *", "- - -", "_ _ _" |
/// | bulletListMarker      | "*" | "*", "-", "_" |
/// | codeBlockStyle      | "indented" | "indented", "fenced" |
/// | fence      | "\`\`\`" | "\`\`\`", "~~~" |
/// | emDelimiter      | "_" | "_", "*" |
/// | strongDelimiter      | "**" | "**", "__" |
/// | linkStyle      | "inlined" | "inlined", "referenced" |
/// | linkReferenceStyle      | "full" | "full", "collapsed", "shortcut" |
///
/// Elements list in [ignore] would be ingored.
///
/// The [rules] parameter can be used to customize element processing.
///
String convert(
  Object input, {
  String? rootTag,
  String? imageBaseUrl,
  Map<String, String>? styleOptions,
  List<String>? ignore,
  List<Rule>? rules,
}) {
  if (imageBaseUrl != null && imageBaseUrl.isNotEmpty) {
    _customOptions['imageBaseUrl'] = imageBaseUrl;
  }
  updateStyleOptions(styleOptions);
  if (ignore != null && ignore.isNotEmpty) {
    Rule.addIgnore(ignore);
  }
  if (rules != null && rules.isNotEmpty) {
    Rule.addRules(rules);
  }
  final output = _process(Node.root(input, rootTag: rootTag));
  return _postProcess(output);
}

/// Escapes markdown's special characters to make it plain text.
String escape(String input) {
  return input
      .replaceAllMapped(RegExp(r'\\(\S)'),
          (match) => '\\\\${match[1]}') // Escape backslash escapes!
      .replaceAllMapped(RegExp(r'^(#{1,6} )', multiLine: true),
          (match) => '\\${match[1]}') // Escape headings
      .replaceAllMapped(RegExp(r'^([-*_] *){3,}$', multiLine: true), (match) {
        return match[0]!.split(match[1]!).join('\\${match[1]}');
      })
      .replaceAllMapped(RegExp(r'^(\W* {0,3})(\d+)\. ', multiLine: true),
          (match) => '${match[1]}${match[2]}\\. ')
      .replaceAllMapped(RegExp(r'^([^\\\w]*)[*+-] ', multiLine: true), (match) {
        return match[0]!
            .replaceAllMapped(RegExp(r'([*+-])'), (match) => '\\${match[1]}');
      })
      .replaceAllMapped(RegExp(r'^(\W* {0,3})> '), (match) => '${match[1]}\\> ')
      .replaceAllMapped(RegExp(_notLink + r'\*+(?!\s)[^*]+(?<!\s)\*+'), //space NOT allowed after the 1st *
          (match) => match[0]!.replaceAll(RegExp(r'\*'), '\\*'))
      .replaceAllMapped(RegExp(_notLink + r'_+(?!\s)[^_]+(?<!\s)_+'), //space NOT allowed after the 1st _
          (match) => match[0]!.replaceAll(RegExp(r'_'), '\\_'))
      .replaceAllMapped(RegExp(_notLink + r'`+[^`]+`+'), //space allowed after the 1st `
          (match) => match[0]!.replaceAll(RegExp(r'`'), '\\`'))
      .replaceAllMapped(RegExp(_notLink + r'~+[^~]+~+'), //space allowed after the 1st ~
          (match) => match[0]!.replaceAll(RegExp(r'~'), '\\~'))
      .replaceAllMapped(RegExp(_notLink + r'[\[\]]'), (match) => '\\${match[0]}');
}
const _notLink = r'(?<!(https?://|mailto:|tel:)\S+)';

Map<String, String> _getFlankingWhitespace(Node node) {
  var result = <String, String>{};
  if (!node.isBlock) {
    var hasLeading = RegExp(r'^[ \r\n\t]').hasMatch(node.textContent);
    var hasTrailing = RegExp(r'[ \r\n\t]$').hasMatch(node.textContent);

    if (hasLeading && !_isFlankedByWhitespace(node, 'left')) {
      result['leading'] = ' ';
    }
    if (hasTrailing && !_isFlankedByWhitespace(node, 'right')) {
      result['trailing'] = ' ';
    }
  }
  return result;
}

bool _isFlankedByWhitespace(Node node, String side) {
  dom.Node? sibling;
  RegExp regExp;
  var isFlanked = false;

  if (side == 'left') {
    sibling = util.previousSibling(node.node);
    regExp = RegExp(r' $');
  } else {
    sibling = util.nextSibling(node.node);
    regExp = RegExp(r'^ ');
  }

  if (sibling != null) {
    if (sibling.nodeType is dom.Text) {
      isFlanked = regExp.hasMatch((sibling as dom.Text).text);
    } else if (sibling is dom.Element && !util.isBlock(sibling)) {
      isFlanked = regExp.hasMatch(sibling.innerHtml);
    }
  }
  return isFlanked;
}

String _join(String string1, String string2) {
  var separator = _separatingNewlines(string1, string2);
  // Remove trailing/leading newlines and replace with separator
  string1 = string1.replaceAll(_trailingNewLinesRegExp, '');
  string2 = string2.replaceAll(_leadingNewLinesRegExp, '');
  return '$string1$separator$string2';
}

String _postProcess(String input) {
  _appendRuleSet.forEach((rule) {
    input = _join(input, rule.append!());
  });

  if (input.isNotEmpty) {
    return input
        .replaceAll(RegExp(r'^[\t\r\n]+'), '')
        .replaceAll(RegExp(r'[\t\r\n]+$'), '');
  }
  return '';
}

String _process(Node inNode) {
  var result = '';
  for (var node in inNode.childNodes()) {
    var replacement = '';
    if (node.nodeType == 3) {
      // Text
      var textContent = node.textContent;
      /// Escapes markdown's special characters to make it plain text.
      replacement = node.isCode ? textContent : escape(textContent);
    } else if (node.nodeType == 1) {
      // Element
      replacement = _replacementForNode(node);
    }
    result = _join(result, replacement);
  }
  return result;
}

String _replacementForNode(Node node) {
  var rule = Rule.findRule(node);
  if (rule.append != null) {
    _appendRuleSet.add(rule);
  }
  var content = _process(node);
  var whitespace = _getFlankingWhitespace(node);
  if (whitespace['leading'] != null || whitespace['trailing'] != null) {
    content = content.trim();
  }
  var replacement = rule.replacement!(content, node);
  if (rule.name == 'image') {
    var imageSrc = node.getAttribute('src');
    var imageBaseUrl = _customOptions['imageBaseUrl'];
    if (imageSrc != null && imageBaseUrl != null) {
      String newSrc;
      if (imageBaseUrl.endsWith('/') || imageSrc.startsWith('/')) {
        newSrc = imageBaseUrl + imageSrc;
      } else {
        newSrc = imageBaseUrl + '/' + imageSrc;
      }
      replacement = replacement.replaceAll(RegExp(imageSrc), newSrc);
    }
  }
  return '${whitespace['leading'] ?? ''}$replacement${whitespace['trailing'] ?? ''}';
}

String _separatingNewlines(String output, String replacement) {
  var newlines = [
    _trailingNewLinesRegExp.stringMatch(output),
    _leadingNewLinesRegExp.stringMatch(replacement),
  ];
  newlines.sort((a, b) => a!.compareTo(b!));

  var maxNewlines = newlines.last!;
  return maxNewlines.length < 2 ? maxNewlines : '\n\n';
}
