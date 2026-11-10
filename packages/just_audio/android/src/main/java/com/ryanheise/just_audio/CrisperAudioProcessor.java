// SPDX-License-Identifier: MIT
// CrisperPlayer addition. Distributed under the package's MIT license.
package com.ryanheise.just_audio;

import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.common.util.UnstableApi;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/** A bounded PCM16 streaming processor. All methods belong to Media3's audio thread. */
@UnstableApi
final class CrisperAudioProcessor implements AudioProcessor {
    private static final int OUTPUT_CHUNK_FRAMES = 4096;
    private static final int MIN_CLOCK_FRAMES = 1024;
    private final int engineId;
    private final CrisperDspEngine engine;
    private AudioFormat pendingFormat = AudioFormat.NOT_SET;
    private AudioFormat format = AudioFormat.NOT_SET;
    private double pendingRate = 1.0;
    private double appliedRate = 1.0;
    private long handle;
    private boolean finishing;
    private ByteBuffer output = EMPTY_BUFFER;

    CrisperAudioProcessor(int engineId, CrisperDspEngine engine) {
        if (engineId != 1 && engineId != 2) {
            throw new IllegalArgumentException("Unknown native speed processor");
        }
        this.engineId = engineId;
        this.engine = engine;
    }

    void setRate(double rate) {
        if (Double.isNaN(rate) || Double.isInfinite(rate) || rate < 0.5 || rate > 3.0) {
            throw new IllegalArgumentException("Native playback speed must be between 0.5 and 3.0");
        }
        // Media3 drains the previous stream before applying and flushing this.
        pendingRate = rate;
    }

    long getMediaDuration(long playoutDuration) {
        if (handle != 0) {
            long delivered = engine.outputFrames(handle);
            long source = engine.sourceFrames(handle);
            if (delivered >= MIN_CLOCK_FRAMES && source > 0) {
                return Math.round(playoutDuration * ((double) source / delivered));
            }
        }
        return Math.round(playoutDuration * appliedRate);
    }

    @Override public long getDurationAfterProcessorApplied(long durationUs) {
        return Math.round(durationUs / appliedRate);
    }

    @Override public AudioFormat configure(AudioFormat input) throws UnhandledAudioFormatException {
        if (input.encoding != C.ENCODING_PCM_16BIT || input.sampleRate <= 0
                || input.channelCount < 1 || input.channelCount > 2) {
            throw new UnhandledAudioFormatException(input);
        }
        pendingFormat = input;
        return input;
    }

    @Override public boolean isActive() { return pendingFormat != AudioFormat.NOT_SET; }

    @Override public void queueInput(ByteBuffer input) {
        // AudioProcessingPipeline polls with EMPTY_BUFFER while draining EOS.
        if (!input.hasRemaining()) return;
        if (handle == 0 || finishing) throw new IllegalStateException("Processor is not accepting input");
        if (!input.isDirect() || input.order() != ByteOrder.nativeOrder()) {
            throw new IllegalArgumentException("PCM input must be direct and use native byte order");
        }
        int frameBytes = format.channelCount * 2;
        if (input.remaining() % frameBytes != 0) throw new IllegalArgumentException("Incomplete PCM frame");
        int frames = input.remaining() / frameBytes;
        if (frames == 0) return;
        int consumed = engine.write(handle, input, input.position(), frames);
        if (consumed < 0 || consumed > frames) throw new IllegalStateException("Invalid native input count");
        // Partial writes are intentional backpressure; the sink retries the remainder.
        input.position(input.position() + consumed * frameBytes);
    }

    @Override public void queueEndOfStream() {
        if (handle != 0 && !finishing) engine.finish(handle);
        finishing = true;
    }

    @Override public ByteBuffer getOutput() {
        if (handle == 0) return EMPTY_BUFFER;
        // The sink owns the returned view until it advances its position. Never
        // overwrite partially consumed PCM, even if getOutput is called again.
        if (output.hasRemaining()) return output;
        output.clear();
        int frames = engine.read(handle, output, OUTPUT_CHUNK_FRAMES);
        if (frames < 0 || frames > OUTPUT_CHUNK_FRAMES) throw new IllegalStateException("Invalid native output count");
        output.limit(frames * format.channelCount * 2);
        return output;
    }

    @Override public boolean isEnded() {
        return finishing && !output.hasRemaining() && (handle == 0 || engine.ended(handle));
    }

    @Override public void flush() {
        releaseHandle();
        format = pendingFormat;
        appliedRate = pendingRate;
        finishing = false;
        if (format == AudioFormat.NOT_SET) {
            output = EMPTY_BUFFER;
            return;
        }
        int outputBytes = OUTPUT_CHUNK_FRAMES * format.channelCount * 2;
        if (output.capacity() < outputBytes) {
            output = ByteBuffer.allocateDirect(outputBytes).order(ByteOrder.nativeOrder());
        }
        output.clear();
        output.limit(0);
        handle = engine.create(engineId, format.sampleRate, format.channelCount, appliedRate);
        if (handle == 0) throw new IllegalStateException("Native audio processor initialization failed");
    }

    @Override public void reset() {
        releaseHandle();
        pendingFormat = AudioFormat.NOT_SET;
        format = AudioFormat.NOT_SET;
        finishing = false;
        pendingRate = 1.0;
        appliedRate = 1.0;
        output = EMPTY_BUFFER;
    }

    private void releaseHandle() {
        if (handle != 0) {
            long previous = handle;
            handle = 0;
            engine.destroy(previous);
        }
    }
}
