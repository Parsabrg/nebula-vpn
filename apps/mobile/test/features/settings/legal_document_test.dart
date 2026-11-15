import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/theme/color_tokens.dart';
import 'package:nebula_mobile/features/settings/legal_document_screen.dart';

void main() {
  for (final String name in <String>['privacy.md', 'terms.md']) {
    test('the app carries docs/$name as it is', () {
      String read(String path) =>
          File(path).readAsStringSync().replaceAll('\r\n', '\n');
      expect(read('assets/legal/$name'), read('../../docs/$name'));
    });
  }

  test('every line of the documents is shown', () {
    const NebulaPalette palette = NebulaPalette.light;
    for (final String name in <String>['privacy.md', 'terms.md']) {
      final String markdown = File('assets/legal/$name').readAsStringSync();
      final String shown = markdownBlocks(
        markdown,
        palette,
      ).expand((Widget w) => _texts(w)).join(' ');
      // A sample of what the renderer has to carry: a heading, a list
      // item's wrapped line, a nested item and a table cell.
      if (name == 'privacy.md') {
        expect(shown, contains('Never collected'));
        expect(shown, contains('Its own privacy policy for WARP applies'));
        expect(shown, contains('Removed from every server:'));
        expect(shown, contains('Password hash (Argon2id)'));
        expect(shown, isNot(contains('**')));
        expect(shown, isNot(contains('|')));
      } else {
        expect(shown, contains('Services run by others'));
        expect(shown, contains('version 3 or later.'));
      }
    }
  });

  test('marks become plain words', () {
    expect(
      plainMarkdown('**Free mode** at `x.io`, see [terms](terms.md)'),
      'Free mode at x.io, see terms',
    );
  });
}

Iterable<String> _texts(Widget widget) sync* {
  if (widget is Text) {
    yield widget.data ?? '';
  } else if (widget is Padding && widget.child != null) {
    yield* _texts(widget.child!);
  } else if (widget is Row) {
    for (final Widget child in widget.children) {
      yield* _texts(child);
    }
  } else if (widget is Expanded) {
    yield* _texts(widget.child);
  } else if (widget is Table) {
    for (final TableRow row in widget.children) {
      for (final Widget cell in row.children) {
        yield* _texts(cell);
      }
    }
  }
}
