/// Tempo processors understood by CrisperPlayer's desktop adapter.
///
/// Availability belongs to the loaded libmpv, not to the operating system.
/// The four portable engines require the optional `crisperdsp` native filter.
enum MediaKitSpeedProcessor {
  automatic(null),
  legacyScaletempo(null),
  sonic('crisperdsp=engine=sonic'),
  wsola('crisperdsp=engine=wsola'),
  signalsmith('crisperdsp=engine=signalsmith'),
  bungee('crisperdsp=engine=bungee'),
  atempo('lavfi-tempo=filter=atempo');

  final String? audioFilter;

  const MediaKitSpeedProcessor(this.audioFilter);

  /// mpv normally bypasses failed user filters. The optional processor must
  /// instead stop playback, including when an internal converter fails and mpv
  /// reports only the filter's application label from its `af` chain.
  bool isFatalFilterLog({
    required String prefix,
    required String level,
    required String text,
  }) {
    if (audioFilter == null || (level != 'error' && level != 'fatal')) {
      return false;
    }
    final message = text.toLowerCase();
    if (RegExp(r'\bdisabling filter @?crisper_speed\b').hasMatch(message)) {
      return true;
    }
    final parts = prefix.toLowerCase().split('/');
    if (this != atempo) return parts.contains('crisperdsp');
    return parts.any((part) => const {
              'lavfi_tempo',
              'lavfi-tempo',
              'lavfi',
              'atempo',
            }.contains(part)) ||
        (parts.contains('ffmpeg') && message.contains('atempo'));
  }

  /// Uses mpv's actual filter inventory, including its linked libavfilter.
  static Set<MediaKitSpeedProcessor> supportedBy(Iterable<String> filters) {
    final available = filters.toSet();
    return Set.unmodifiable({
      automatic,
      legacyScaletempo,
      if (available.contains('crisperdsp')) ...{
        sonic,
        wsola,
        signalsmith,
        bungee,
      },
      // Plain lavfi atempo does not participate in mpv's source clock and
      // speed-control protocol. Require the native tempo-aware wrapper too.
      if (available.contains('lavfi-tempo') && available.contains('atempo'))
        atempo,
    });
  }
}
