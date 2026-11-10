// SPDX-License-Identifier: MIT
// CrisperPlayer addition. Distributed under the package's MIT license.
package com.ryanheise.just_audio;

import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.audio.AudioProcessorChain;
import androidx.media3.common.util.UnstableApi;

/** Owns the only speed stage; never appends the default Sonic stage. */
@UnstableApi
final class CrisperAudioProcessorChain implements AudioProcessorChain {
    private final CrisperAudioProcessor processor;
    private final AudioProcessor[] processors;

    CrisperAudioProcessorChain(int engineId, CrisperDspEngine engine) {
        processor = new CrisperAudioProcessor(engineId, engine);
        processors = new AudioProcessor[] { processor };
    }

    @Override public AudioProcessor[] getAudioProcessors() { return processors; }

    @Override public PlaybackParameters applyPlaybackParameters(PlaybackParameters parameters) {
        if (parameters.pitch != 1.0f) {
            throw new IllegalArgumentException("Native speed processors preserve pitch at 1.0");
        }
        processor.setRate(parameters.speed);
        return parameters;
    }

    @Override public boolean applySkipSilenceEnabled(boolean enabled) { return false; }
    @Override public long getMediaDuration(long playoutDuration) {
        return processor.getMediaDuration(playoutDuration);
    }
    @Override public long getSkippedOutputFrameCount() { return 0; }
}
