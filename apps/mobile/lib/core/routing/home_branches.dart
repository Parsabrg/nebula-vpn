import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Each tab's own navigator (Connect, Devices, Account), so a tab tap can
/// clear what was opened on it, the screens pushed straight onto it
/// included (Connection details, Configuration), and land on its main page.
final homeBranchKeysProvider = Provider<List<GlobalKey<NavigatorState>>>(
  (Ref ref) => List<GlobalKey<NavigatorState>>.generate(
    3,
    (int i) => GlobalKey<NavigatorState>(debugLabel: 'home-branch-$i'),
  ),
);

/// Back to the main page of tab [branch]: everything opened on it closed.
void popHomeBranch(WidgetRef ref, int branch) => ref
    .read(homeBranchKeysProvider)[branch]
    .currentState
    ?.popUntil((Route<dynamic> route) => route.isFirst);
