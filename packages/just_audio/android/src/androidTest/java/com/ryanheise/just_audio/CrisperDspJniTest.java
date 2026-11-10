// SPDX-License-Identifier: MIT
package com.ryanheise.just_audio;

import static org.junit.Assert.*;

import androidx.media3.common.C;
import androidx.media3.common.audio.AudioProcessingPipeline;
import androidx.media3.common.audio.AudioProcessor;
import com.google.common.collect.ImmutableList;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;
import org.junit.Test;

/** Runs the packaged ABI and real DSP through JNI; no mock engine or audio device. */
public class CrisperDspJniTest {
    @Test public void realMedia3PipelineHandlesNativeBackpressureAndFiniteDrain() throws Exception {
        for (int engineId : new int[] {1, 2}) {
            CrisperAudioProcessor processor = new CrisperAudioProcessor(engineId, new JniCrisperDspEngine());
            processor.setRate(2.0);
            AudioProcessingPipeline pipeline = new AudioProcessingPipeline(ImmutableList.of(processor));
            pipeline.configure(new AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_16BIT));
            pipeline.flush();
            ByteBuffer input = pcm(tone(48000, 48000, 440));
            int delivered = 0;
            for (int retry = 0; input.hasRemaining() && retry < 10000; retry++) {
                pipeline.queueInput(input);
                ByteBuffer output = pipeline.getOutput();
                delivered += output.remaining() / 2;
                output.position(output.limit());
            }
            assertFalse("pipeline consumes every input frame", input.hasRemaining());
            pipeline.queueEndOfStream();
            for (int retry = 0; !pipeline.isEnded() && retry < 10000; retry++) {
                ByteBuffer output = pipeline.getOutput();
                delivered += output.remaining() / 2;
                output.position(output.limit());
            }
            assertTrue("pipeline EOS is finite", pipeline.isEnded());
            assertEquals(24000, delivered);
            assertEquals(1000000, processor.getMediaDuration(500000));
            pipeline.flush();
            assertFalse(pipeline.getOutput().hasRemaining());
            assertEquals(2000000, processor.getMediaDuration(1000000));
            pipeline.reset();
        }
    }

    @Test public void bothEnginesStretchGeneratedToneAndPreservePitch() {
        for (int engineId : new int[] {1, 2}) {
            JniCrisperDspEngine engine = new JniCrisperDspEngine();
            long handle = engine.create(engineId, 48000, 1, 1.5);
            try {
                List<Short> output = process(engine, handle, tone(96000, 48000, 440), 1);
                assertEquals("finite tail length", 64000, output.size());
                assertEquals(96000, engine.sourceFrames(handle));
                assertEquals(64000, engine.outputFrames(handle));
                assertTrue(engine.ended(handle));
                // Ignore boundary transients. A speed-up without pitch correction
                // would be near 660 Hz; these actual native modes remain near 440.
                int first = 5000, last = output.size() - 5000, rising = 0;
                for (int i = first + 1; i < last; i++) {
                    if (output.get(i - 1) <= 0 && output.get(i) > 0) rising++;
                }
                double hertz = rising * 48000.0 / (last - first);
                assertEquals("original tone pitch for engine " + engineId, 440, hertz, 12);
            } finally {
                engine.destroy(handle);
            }
        }
    }

    @Test public void unityStereoIsExactAndNewHandleDropsOldLookahead() {
        for (int engineId : new int[] {1, 2}) {
            JniCrisperDspEngine engine = new JniCrisperDspEngine();
            long old = engine.create(engineId, 44100, 2, 2.0);
            ByteBuffer abandoned = pcm(new short[] {111, -111, 222, -222, 333, -333});
            engine.write(old, abandoned, 0, 3);
            engine.destroy(old); // The processor's seek/flush path replaces the handle.
            long fresh = engine.create(engineId, 44100, 2, 1.0);
            try {
                short[] expected = new short[] {7, -7, 15, -15, 0, 0, 32767, -32768};
                List<Short> result = process(engine, fresh, expected, 2);
                assertEquals(expected.length, result.size());
                for (int i = 0; i < expected.length; i++) assertEquals(expected[i], (short) result.get(i));
                assertEquals(4, engine.sourceFrames(fresh));
                assertEquals(4, engine.outputFrames(fresh));
            } finally {
                engine.destroy(fresh);
            }
        }
    }

    @Test public void jniRejectsInvalidBufferRangesAndZeroHandles() {
        JniCrisperDspEngine engine = new JniCrisperDspEngine();
        long handle = engine.create(1, 48000, 2, 1.5);
        try {
            assertThrows(IllegalStateException.class,
                () -> engine.write(handle, ByteBuffer.allocate(8), 0, 2));
            assertThrows(IllegalStateException.class,
                () -> engine.write(handle, ByteBuffer.allocateDirect(8), 0, 3));
            assertThrows(IllegalStateException.class,
                () -> engine.write(handle, ByteBuffer.allocateDirect(8), -1, 1));
            assertThrows(IllegalStateException.class,
                () -> engine.read(handle, ByteBuffer.allocateDirect(8), Integer.MAX_VALUE));
            assertThrows(IllegalStateException.class, () -> engine.sourceFrames(0));
        } finally {
            engine.destroy(handle);
        }
        assertThrows(IllegalStateException.class, () -> engine.create(1, 48000, 6, 1.5));
        assertThrows(IllegalStateException.class, () -> engine.create(2, 48000, 1, Double.NaN));
    }

    private static List<Short> process(JniCrisperDspEngine engine, long handle, short[] samples, int channels) {
        ByteBuffer input = pcm(samples);
        ByteBuffer output = ByteBuffer.allocateDirect(257 * channels * 2).order(ByteOrder.nativeOrder());
        List<Short> received = new ArrayList<>();
        int frames = samples.length / channels, consumed = 0, attempts = 0;
        while (consumed < frames) {
            assertTrue("bounded streaming progress", attempts++ < frames + 10000);
            int requested = Math.min(701, frames - consumed);
            int written = engine.write(handle, input, consumed * channels * 2, requested);
            assertTrue(written >= 0 && written <= requested);
            consumed += written;
            drainAvailable(engine, handle, output, channels, received);
        }
        engine.finish(handle);
        engine.finish(handle);
        for (int retry = 0; !engine.ended(handle) && retry < 10000; retry++) {
            drainAvailable(engine, handle, output, channels, received);
        }
        assertTrue("finite end-of-stream drain", engine.ended(handle));
        return received;
    }

    private static void drainAvailable(JniCrisperDspEngine engine, long handle, ByteBuffer output,
            int channels, List<Short> received) {
        for (int retry = 0; retry < 1000; retry++) {
            int read = engine.read(handle, output, 257);
            assertTrue(read >= 0 && read <= 257);
            if (read == 0) return;
            for (int i = 0; i < read * channels; i++) received.add(output.getShort(i * 2));
        }
        fail("Native drain did not return control");
    }

    private static ByteBuffer pcm(short[] samples) {
        ByteBuffer result = ByteBuffer.allocateDirect(samples.length * 2).order(ByteOrder.nativeOrder());
        for (short sample : samples) result.putShort(sample);
        result.flip();
        return result;
    }

    private static short[] tone(int frames, int sampleRate, int frequency) {
        short[] samples = new short[frames];
        for (int i = 0; i < frames; i++) {
            samples[i] = (short) Math.round(12000 * Math.sin(2 * Math.PI * frequency * i / sampleRate));
        }
        return samples;
    }
}
