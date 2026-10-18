import 'dart:convert';

/// Only explicit overrides are stored. Missing keys inherit application defaults.
class BookPreferences {
  static const keys = {
    'speed',
    'skipSilence',
    'boostDb',
    'equalizer',
    'seekSeconds',
    'smartRewindSeconds',
    'smartRewindAfterSeconds',
  };
  static Map<String, dynamic> decode(String json) {
    final value = jsonDecode(json);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid book preferences');
    }
    return validate(value);
  }

  static Map<String, dynamic> validate(Map<String, dynamic> values) {
    final result = <String, dynamic>{};
    for (final entry in values.entries) {
      if (!keys.contains(entry.key)) {
        throw FormatException('Unknown book preference: ${entry.key}');
      }
      final value = entry.value;
      if (value == null) continue;
      final valid = switch (entry.key) {
        'speed' => value is num && value.isFinite && value >= .5 && value <= 3,
        'skipSilence' => value is bool,
        'boostDb' =>
          value is num && value.isFinite && value >= 0 && value <= 12,
        'equalizer' => [
          'off',
          'speech',
          'warm',
          'bass-reduction',
        ].contains(value),
        'seekSeconds' => value is int && [10, 15, 30, 60].contains(value),
        'smartRewindSeconds' => value is int && value >= 0 && value <= 60,
        'smartRewindAfterSeconds' =>
          value is int && value >= 0 && value <= 86400,
        _ => false,
      };
      if (!valid) throw FormatException('Invalid ${entry.key}');
      result[entry.key] = {'speed', 'boostDb'}.contains(entry.key)
          ? (value as num).toDouble()
          : value;
    }
    return result;
  }
}
