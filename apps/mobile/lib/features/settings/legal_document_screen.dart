import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/color_tokens.dart';
import '../../l10n/app_localizations.dart';

/// The privacy policy and the terms of use, as bundled with this build:
/// copies of docs/privacy.md and docs/terms.md (a test keeps them equal),
/// so they read offline and say what this very build does.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    required this.title,
    required this.asset,
    super.key,
  });

  static const String privacyAsset = 'assets/legal/privacy.md';
  static const String termsAsset = 'assets/legal/terms.md';

  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final NebulaPalette palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(title),
      ),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(asset),
          builder: (BuildContext context, AsyncSnapshot<String> text) {
            if (!text.hasData) {
              return const SizedBox.shrink();
            }
            return SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: <Widget>[
                  // The text is English; the page around it is not.
                  if (Localizations.localeOf(context).languageCode != 'en')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        AppText.of(context).legalEnglishOnly,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: markdownBlocks(text.data!, palette),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The markdown these two documents use: `##` headings, paragraphs, `-`
/// lists (nested by indent), tables, and bold, code and link marks, which
/// are shown as plain words. The `#` title is the app bar's.
@visibleForTesting
List<Widget> markdownBlocks(String markdown, NebulaPalette palette) {
  final TextStyle body = TextStyle(
    color: palette.textPrimary,
    fontSize: 14,
    height: 1.45,
  );
  final List<Widget> out = <Widget>[];
  final List<String> paragraph = <String>[];
  final List<String> lines = markdown.replaceAll('\r\n', '\n').split('\n');

  void flush() {
    if (paragraph.isNotEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(plainMarkdown(paragraph.join(' ')), style: body),
        ),
      );
      paragraph.clear();
    }
  }

  final RegExp bullet = RegExp(r'^(\s*)- (.*)$');
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final RegExpMatch? item = bullet.firstMatch(line);
    if (line.trim().isEmpty) {
      flush();
    } else if (line.startsWith('# ')) {
      flush();
    } else if (line.startsWith('## ')) {
      flush();
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(
            plainMarkdown(line.substring(3)),
            style: body.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
      );
    } else if (line.startsWith('|')) {
      flush();
      final List<List<String>> rows = <List<String>>[];
      for (; i < lines.length && lines[i].startsWith('|'); i++) {
        final List<String> cells = lines[i]
            .substring(1, lines[i].trimRight().length - 1)
            .split('|')
            .map((String cell) => plainMarkdown(cell.trim()))
            .toList();
        if (!cells.every((String cell) => RegExp(r'^:?-+:?$').hasMatch(cell))) {
          rows.add(cells);
        }
      }
      i--;
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Table(
            border: TableBorder(
              horizontalInside: BorderSide(color: palette.border),
            ),
            children: <TableRow>[
              for (int r = 0; r < rows.length; r++)
                TableRow(
                  children: <Widget>[
                    for (final String cell in rows[r])
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
                        child: Text(
                          cell,
                          style: r == 0
                              ? body.copyWith(fontWeight: FontWeight.w600)
                              : body.copyWith(fontSize: 13),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    } else if (item != null) {
      flush();
      final int indent = item.group(1)!.length;
      final List<String> words = <String>[item.group(2)!];
      // Its wrapped lines: indented past the dash, and not a list item.
      while (i + 1 < lines.length &&
          lines[i + 1].startsWith(' ' * (indent + 2)) &&
          !bullet.hasMatch(lines[i + 1])) {
        words.add(lines[++i].trim());
      }
      out.add(
        Padding(
          padding: EdgeInsets.only(left: indent * 6.0, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('•  ', style: body),
              Expanded(
                child: Text(plainMarkdown(words.join(' ')), style: body),
              ),
            ],
          ),
        ),
      );
    } else {
      paragraph.add(line.trim());
    }
  }
  flush();
  return out;
}

/// [text] without its bold, code and link marks.
@visibleForTesting
String plainMarkdown(String text) => text
    .replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (Match m) => m.group(1)!,
    )
    .replaceAll('**', '')
    .replaceAll('`', '');
