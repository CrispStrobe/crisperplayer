/// Direct native PCM playback, with bounded decoding and portable DSP.
library;

export 'src/types.dart';
export 'src/player_stub.dart' if (dart.library.ffi) 'src/player.dart';
export 'src/probe_stub.dart' if (dart.library.ffi) 'src/probe.dart';
