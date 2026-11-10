// SPDX-License-Identifier: MIT
// CrisperPlayer addition. Distributed under the package's MIT license.
package com.ryanheise.just_audio;

import android.content.Context;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.audio.AudioSink;
import androidx.media3.exoplayer.audio.DefaultAudioSink;

@UnstableApi
final class CrisperRenderersFactory extends DefaultRenderersFactory {
    private final int engineId;

    CrisperRenderersFactory(Context context, int engineId) {
        super(context);
        JniCrisperDspEngine.ensureLoaded();
        this.engineId = engineId;
    }

    @Override protected AudioSink buildAudioSink(
            Context context, boolean enableFloatOutput, boolean enableAudioTrackPlaybackParams) {
        return new CrisperPcmAudioSink(new DefaultAudioSink.Builder(context)
            .setAudioProcessorChain(new CrisperAudioProcessorChain(engineId, new JniCrisperDspEngine()))
            .setEnableFloatOutput(false)
            .setEnableAudioTrackPlaybackParams(false)
            .build());
    }
}
