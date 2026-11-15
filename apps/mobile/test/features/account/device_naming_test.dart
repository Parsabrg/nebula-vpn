import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula_mobile/core/account/account_repository.dart';
import 'package:nebula_mobile/core/app_info.dart';
import 'package:nebula_mobile/features/account/account_controller.dart';

import '../../core/account/fake_account_repository.dart';

AccountDevice _device(String id, String name, {bool current = false}) =>
    AccountDevice(
      id: id,
      name: name,
      platform: 'android',
      state: 'active',
      clientVersion: '0.1.37',
      registeredAt: DateTime.utc(2026, 11, 14),
      isCurrent: current,
      serverCodes: const <String>[],
    );

Future<FakeAccountRepository> _load(List<AccountDevice> devices) async {
  final FakeAccountRepository repository = FakeAccountRepository()
    ..account = const AccountSummary(
      email: 'owner@example.org',
      username: 'owner',
      state: 'active',
      deviceLimit: 5,
      devicesInUse: 2,
      usedBytes: 0,
    )
    ..devices = devices;
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      accountRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await container.read(accountControllerProvider.notifier).load();
  // The renaming runs after the load, unawaited.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return repository;
}

void main() {
  test('the old placeholder names are recognised, real ones are not', () {
    expect(isPlaceholderDeviceName('android device'), isTrue);
    expect(isPlaceholderDeviceName('windows device'), isTrue);
    expect(isPlaceholderDeviceName('linux device'), isTrue);
    expect(isPlaceholderDeviceName('Xiaomi 2201117TG'), isFalse);
    expect(isPlaceholderDeviceName('my android device'), isFalse);
  });

  test('this device, still under the old name, takes its real one', () async {
    final FakeAccountRepository repository = await _load(<AccountDevice>[
      _device('this', 'windows device', current: true),
      _device('other', 'android device'),
    ]);
    // Only the device holding the app renames itself; the other is the
    // person's to rename, or its own app's.
    expect(repository.renamed, hasLength(1));
    expect(repository.renamed.single.$1, 'this');
    expect(isPlaceholderDeviceName(repository.renamed.single.$2), isFalse);
    expect(await readDeviceName(), repository.renamed.single.$2);
  });

  test('a name the person chose is left alone', () async {
    final FakeAccountRepository repository = await _load(<AccountDevice>[
      _device('this', 'Work laptop', current: true),
    ]);
    expect(repository.renamed, isEmpty);
  });
}
