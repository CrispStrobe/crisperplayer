// SPDX-License-Identifier: MIT
// CrisperPlayer addition. Distributed under the package's MIT license.
package com.ryanheise.just_audio;

import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.audio.AudioOffloadSupport;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.ForwardingAudioSink;

/** Forces decoding to PCM; encoded passthrough/offload would bypass our processor. */
@UnstableApi
final class CrisperPcmAudioSink extends ForwardingAudioSink {
    CrisperPcmAudioSink(AudioSink sink) { super(sink); }

    @Override public boolean supportsFormat(Format format) {
        return MimeTypes.AUDIO_RAW.equals(format.sampleMimeType) && super.supportsFormat(format);
    }

    @Override public int getFormatSupport(Format format) {
        return MimeTypes.AUDIO_RAW.equals(format.sampleMimeType)
            ? super.getFormatSupport(format) : SINK_FORMAT_UNSUPPORTED;
    }

    @Override public AudioOffloadSupport getFormatOffloadSupport(Format format) {
        return AudioOffloadSupport.DEFAULT_UNSUPPORTED;
    }

    @Override public void setOffloadMode(int mode) {
        super.setOffloadMode(OFFLOAD_MODE_DISABLED);
    }
}
