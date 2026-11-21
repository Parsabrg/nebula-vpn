import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

/// Manages the system tray icon and context menu on Windows.
///
/// Initialised once from [main] on desktop platforms. The tray icon stays
/// visible for the lifetime of the process; closing the window hides it
/// to the tray rather than terminating the app.
class DesktopTrayManager {
  DesktopTrayManager({required this.onShowWindow, required this.onExit});

  /// Called when the user clicks the tray icon or selects "Show".
  final VoidCallback onShowWindow;

  /// Called when the user selects "Exit" from the context menu.
  final VoidCallback onExit;

  // Held for as long as the icon should show: a collected wrapper releases
  // its native handle, and that removes the icon.
  TrayIcon? _icon;

  /// Sets up the tray icon and context menu. Safe to call on non-desktop
  /// platforms — it returns immediately.
  Future<void> init() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    if (_icon != null) return;
    final TrayIcon? icon = TrayIcon.create();
    final Menu? menu = Menu.create();
    if (icon == null || menu == null) return;
    _icon = icon;

    icon.icon = ImageAsset.fromAsset('assets/app_icon.ico');
    icon.setTooltip('Nebula VPN');
    _addItem(menu, 'Show Nebula VPN', onShowWindow);
    menu.addSeparator();
    _addItem(menu, 'Exit', onExit);
    icon.setContextMenu(menu);
    icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
    icon.addListener((TrayIconEvent event) {
      if (event is TrayIconClickedEvent) onShowWindow();
    });
    icon.setVisible(true);
  }

  static void _addItem(Menu menu, String label, VoidCallback onClick) {
    final MenuItem? item = MenuItem.createWithLabelAndType(
      label,
      MenuItemType.normal,
    );
    if (item == null) return;
    item.addListener((MenuEvent event) {
      if (event is MenuItemClickedEvent) onClick();
    });
    menu.addItem(item);
  }

  /// Updates the tooltip, e.g. to show connection status.
  Future<void> updateTooltip(String text) async {
    _icon?.setTooltip(text);
  }

  /// Removes the tray icon. Call before the app exits.
  Future<void> dispose() async {
    _icon?.dispose();
    _icon = null;
  }
}
