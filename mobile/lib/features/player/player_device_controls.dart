import 'package:flutter/services.dart';

class PlayerDeviceState {
  const PlayerDeviceState({
    required this.volume,
    required this.brightness,
    required this.volumeAvailable,
    required this.brightnessAvailable,
  });

  const PlayerDeviceState.unavailable()
    : volume = 1,
      brightness = 0.5,
      volumeAvailable = false,
      brightnessAvailable = false;

  final double volume;
  final double brightness;
  final bool volumeAvailable;
  final bool brightnessAvailable;
}

abstract interface class PlayerDeviceControls {
  Future<PlayerDeviceState> readState();

  Future<bool> setVolume(double value);

  Future<bool> setBrightness(double value);

  Future<void> restoreBrightness();
}

class MethodChannelPlayerDeviceControls implements PlayerDeviceControls {
  const MethodChannelPlayerDeviceControls({
    MethodChannel channel = const MethodChannel(
      'com.luma.luma/player_controls',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<PlayerDeviceState> readState() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getState',
      );
      if (result == null) return const PlayerDeviceState.unavailable();
      return PlayerDeviceState(
        volume: _number(result['volume'], 1),
        brightness: _number(result['brightness'], 0.5),
        volumeAvailable: result['volumeAvailable'] == true,
        brightnessAvailable: result['brightnessAvailable'] == true,
      );
    } on PlatformException {
      return const PlayerDeviceState.unavailable();
    } on MissingPluginException {
      return const PlayerDeviceState.unavailable();
    }
  }

  @override
  Future<bool> setVolume(double value) => _setValue('setVolume', value);

  @override
  Future<bool> setBrightness(double value) => _setValue('setBrightness', value);

  Future<bool> _setValue(String method, double value) async {
    try {
      return await _channel.invokeMethod<bool>(method, {
            'value': value.clamp(0, 1),
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> restoreBrightness() async {
    try {
      await _channel.invokeMethod<void>('restoreBrightness');
    } on PlatformException {
      // The player still exits normally when the host capability is missing.
    } on MissingPluginException {
      // The player still exits normally when the host capability is missing.
    }
  }

  static double _number(Object? value, double fallback) =>
      value is num ? value.toDouble().clamp(0, 1).toDouble() : fallback;
}
