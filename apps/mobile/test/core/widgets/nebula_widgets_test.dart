import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/theme/color_tokens.dart';
import 'package:nebula_mobile/core/theme/look.dart';
import 'package:nebula_mobile/core/theme/nebula_theme.dart';
import 'package:nebula_mobile/core/widgets/nebula/nebula_controls.dart';
import 'package:nebula_mobile/core/widgets/nebula/nebula_data.dart';
import 'package:nebula_mobile/core/widgets/nebula/nebula_nav.dart';
import 'package:nebula_mobile/core/widgets/nebula/nebula_rows.dart';

/// Every shared widget, drawn in every look and mode: one set of widgets
/// whose look is only token values, so none may fail in any of them.
void main() {
  for (final NebulaLook look in NebulaLook.values) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets(
        'the shared widgets draw in ${look.name} ${brightness.name}',
        (WidgetTester tester) async {
          await tester.binding.setSurfaceSize(const Size(420, 2400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          bool on = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: NebulaTheme.resolve(
                brightness,
                AppearanceChoice(look: look, accent: NebulaAccent.teal),
              ),
              home: Scaffold(
                body: GlassBackdrop(
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter set) =>
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: <Widget>[
                            const NebulaStatusHero(
                              dotColor: Colors.green,
                              eyebrow: 'Frankfurt',
                              title: 'Protected',
                              subline: 'Connected for 1:24:09',
                            ),
                            const NebulaSectionLabel('Connection'),
                            NebulaRowGroup(
                              children: <Widget>[
                                NebulaRow(
                                  title: 'Startup',
                                  subtitle: 'manual',
                                  icon: Icons.power_settings_new,
                                  trailing: NebulaRowTrailing.chevron(context),
                                  onTap: () {},
                                ),
                                NebulaRow(
                                  title: 'Protection',
                                  subtitle: 'Kill switch: off',
                                  icon: Icons.shield_outlined,
                                  tone: NebulaTone.warn,
                                  trailing: NebulaRowTrailing.badge(
                                    context,
                                    'This device',
                                  ),
                                  onTap: () {},
                                ),
                                NebulaSwitchRow(
                                  title: 'Connect on launch',
                                  value: on,
                                  onChanged: (bool v) => set(() => on = v),
                                ),
                                NebulaRow(
                                  title: 'Address',
                                  trailing: NebulaRowTrailing.value(
                                    context,
                                    '10.0.0.2',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            NebulaSegmented<int>(
                              segments: const <(int, String, IconData?)>[
                                (0, 'Light', Icons.light_mode_outlined),
                                (1, 'Dark', null),
                                (2, 'System', null),
                              ],
                              selected: 1,
                              onChanged: (_) {},
                            ),
                            const SizedBox(height: 16),
                            const NebulaStatsGrid(
                              stats: <(String, String)>[
                                ('Downloaded', '1.2 GB'),
                                ('Uploaded', '84.6 MB'),
                                ('Address', '10.0.0.2'),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const NebulaUsageMeter(fraction: 0.4),
                            const SizedBox(height: 16),
                            const NebulaNotice(text: 'Checking the server…'),
                            const SizedBox(height: 16),
                            const NebulaNotice(
                              text: 'Wrong password',
                              kind: NebulaNoticeKind.error,
                            ),
                            const SizedBox(height: 16),
                            const NebulaField(
                              label: 'Password',
                              password: true,
                              errorText: 'Too short',
                              showLabel: 'Show',
                              hideLabel: 'Hide',
                            ),
                            const SizedBox(height: 16),
                            NebulaField(
                              label: 'Link',
                              addLabel: 'Add',
                              onAdd: () {},
                              help: 'vless://, vmess://…',
                            ),
                            const SizedBox(height: 16),
                            const NebulaEmptyState(title: 'No links yet'),
                            const SizedBox(height: 16),
                            NebulaButton(label: 'Connect', onPressed: () {}),
                            NebulaButton.secondary(
                              label: 'Disconnect',
                              onPressed: () {},
                            ),
                            NebulaButton.danger(
                              label: 'Delete',
                              onPressed: () {},
                            ),
                            NebulaButton.text(
                              label: 'Cancel',
                              onPressed: () {},
                            ),
                            NebulaLinkButton(
                              label: 'Connection details',
                              onPressed: () {},
                            ),
                            SizedBox(
                              height: 400,
                              child: NebulaSideNav(
                                items: <NebulaNavItem>[
                                  NebulaNavItem(
                                    label: 'Connect',
                                    icon: Icons.shield_outlined,
                                    selectedIcon: Icons.shield,
                                    selected: true,
                                    onTap: () {},
                                  ),
                                  NebulaNavItem(
                                    label: 'Devices',
                                    icon: Icons.devices_outlined,
                                    selectedIcon: Icons.devices,
                                    selected: false,
                                    onTap: () {},
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                  ),
                ),
                bottomNavigationBar: NebulaTabBar(
                  items: <NebulaNavItem>[
                    NebulaNavItem(
                      label: 'Connect',
                      icon: Icons.shield_outlined,
                      selectedIcon: Icons.shield,
                      selected: true,
                      onTap: () {},
                    ),
                    NebulaNavItem(
                      label: 'Account',
                      icon: Icons.person_outline,
                      selectedIcon: Icons.person,
                      selected: false,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Connect on launch'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(on, isTrue);
          expect(find.bySemanticsLabel('Show'), findsOneWidget);
        },
      );
    }
  }
}
