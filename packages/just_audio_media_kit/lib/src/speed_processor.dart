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
