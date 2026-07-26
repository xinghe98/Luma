// DeviceKeyStore 测试以注入存储验证 single-flight、错误传播和进程内降级生命周期。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/device_key_store.dart';

void main() {
  test(
    'readOrCreate uses one storage operation for concurrent callers',
    () async {
      final readStarted = Completer<void>();
      final releaseRead = Completer<void>();
      var reads = 0;
      var writes = 0;
      final store = SecureDeviceKeyStore(
        read: () async {
          reads++;
          readStarted.complete();
          await releaseRead.future;
          return null;
        },
        write: (value) async => writes++,
      );

      final first = store.readOrCreate();
      final second = store.readOrCreate();
      await readStarted.future;
      releaseRead.complete();

      final values = await Future.wait([first, second]);
      expect(values[0], values[1]);
      expect(reads, 1);
      expect(writes, 1);
    },
  );

  test('ordinary secure storage errors are propagated', () async {
    final store = SecureDeviceKeyStore(
      read: () async => throw StateError('keystore unavailable'),
      write: (value) async {},
    );

    await expectLater(store.readOrCreate(), throwsStateError);
  });

  test('missing plugin falls back to one process-local key', () async {
    final store = SecureDeviceKeyStore(
      read: () async => throw MissingPluginException(),
      write: (value) async {},
    );

    final first = await store.readOrCreate();
    final second = await store.readOrCreate();
    expect(second, first);
  });

  test('unsupported platform falls back but platform errors do not', () async {
    final unsupported = SecureDeviceKeyStore(
      read: () async => throw UnsupportedError('not supported'),
      write: (value) async {},
    );
    final failed = SecureDeviceKeyStore(
      read: () async => throw PlatformException(code: 'storage_failed'),
      write: (value) async {},
    );

    expect(await unsupported.readOrCreate(), isNotEmpty);
    await expectLater(failed.readOrCreate(), throwsA(isA<PlatformException>()));
  });
}
