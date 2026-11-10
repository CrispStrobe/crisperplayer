// SPDX-License-Identifier: MIT
package com.ryanheise.just_audio;

import static org.junit.Assert.*;

import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.audio.AudioProcessingPipeline;
import androidx.media3.common.audio.AudioProcessor;
import androidx.media3.exoplayer.audio.AudioOffloadSupport;
import androidx.media3.exoplayer.audio.AudioSink;
import com.google.common.collect.ImmutableList;
import java.lang.reflect.Proxy;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.Test;

/** Media3 lifecycle tests. The deterministic engine models backpressure, not DSP quality. */
public class CrisperAudioProcessorTest {
    private static final AudioProcessor.AudioFormat MONO =
        new AudioProcessor.AudioFormat(48000, 1, C.ENCODING_PCM_16BIT);

    @Test public void nativeEngineIdsRemainStableAndReachTheConfiguredStage() throws Exception {
        for (int engineId : new int[] {1, 2, 3}) {
            FakeEngine engine = new FakeEngine();
            CrisperAudioProcessorChain chain = new CrisperAudioProcessorChain(engineId, engine);
            assertEquals(1, chain.getAudioProcessors().length);
            CrisperAudioProcessor processor = (CrisperAudioProcessor) chain.getAudioProcessors()[0];
            chain.applyPlaybackParameters(new PlaybackParameters(1.5f));
            processor.configure(MONO);
            processor.flush();
            assertEquals(engineId, engine.lastEngineId);
            assertEquals(1.5, engine.latest().rate, 0.0);
            assertFalse(chain.applySkipSilenceEnabled(true));
            processor.reset();
        }
        for (int unsupported : new int[] {-1, 0, 4}) {
            assertThrows(IllegalArgumentException.class,
                () -> new CrisperAudioProcessor(unsupported, new FakeEngine()));
        }
    }

    @Test public void partialInputWritesLeaveTheUnconsumedFramesInTheCallerBuffer() throws Exception {
        FakeEngine engine = new FakeEngine();
        engine.maxWriteFrames = 3;
        CrisperAudioProcessor processor = ready(engine);
        ByteBuffer input = pcm(10, 11, 12, 13, 14);
        processor.queueInput(input);
        assertEquals(6, input.position());
        assertEquals(4, input.remaining());
        assertArrayEquals(new short[] {10, 11, 12}, consume(processor.getOutput()));
        processor.queueInput(input);
        assertFalse(input.hasRemaining());
        assertArrayEquals(new short[] {13, 14}, consume(processor.getOutput()));
        processor.reset();
    }

    @Test public void unreadOutputIsNotOverwrittenOrCountedTwice() throws Exception {
        FakeEngine engine = new FakeEngine();
        engine.maxReadFrames = 2;
        CrisperAudioProcessor processor = ready(engine);
        processor.queueInput(pcm(100, 200, 300, 400));
        ByteBuffer first = processor.getOutput();
        assertEquals(100, first.getShort());
        assertSame(first, processor.getOutput());
        assertEquals(2, first.position());
        assertEquals(1, engine.readCalls);
        assertEquals(200, first.getShort());
        assertArrayEquals(new short[] {300, 400}, consume(processor.getOutput()));
        assertEquals(2, engine.readCalls);
        processor.reset();
    }

    @Test public void realMedia3PipelineDrainsPendingFramesAndEmptyEosPolls() throws Exception {
        FakeEngine engine = new FakeEngine();
        engine.maxWriteFrames = 3;
        engine.maxReadFrames = 2;
        CrisperAudioProcessor processor = new CrisperAudioProcessor(1, engine);
        AudioProcessingPipeline pipeline = new AudioProcessingPipeline(ImmutableList.of(processor));
        pipeline.configure(MONO);
        pipeline.flush();
        ByteBuffer input = pcm(1, 2, 3, 4, 5, 6, 7, 8);
        List<Short> received = new ArrayList<>();
        for (int retries = 0; input.hasRemaining() && retries < 30; retries++) {
            pipeline.queueInput(input);
            collect(pipeline.getOutput(), received);
        }
        assertFalse(input.hasRemaining());
        pipeline.queueEndOfStream();
        for (int retries = 0; !pipeline.isEnded() && retries < 30; retries++) {
            collect(pipeline.getOutput(), received);
        }
        assertTrue(pipeline.isEnded());
        assertEquals(List.of((short) 1, (short) 2, (short) 3, (short) 4,
            (short) 5, (short) 6, (short) 7, (short) 8), received);
        assertEquals(1, engine.finishCalls);
        pipeline.reset();
        assertTrue(engine.streams.isEmpty());
    }

    @Test public void endWaitsForTheReturnedOutputAndFinishIsIdempotent() throws Exception {
        FakeEngine engine = new FakeEngine();
        CrisperAudioProcessor processor = ready(engine);
        processor.queueInput(pcm(8, 9));
        processor.queueEndOfStream();
        processor.queueEndOfStream();
        processor.queueInput(AudioProcessor.EMPTY_BUFFER);
        ByteBuffer output = processor.getOutput();
        assertFalse(processor.isEnded());
        assertArrayEquals(new short[] {8, 9}, consume(output));
        assertTrue(processor.isEnded());
        assertEquals(1, engine.finishCalls);
        assertThrows(IllegalStateException.class, () -> processor.queueInput(pcm(1)));
        processor.reset();
    }

    @Test public void sourceClockUsesDeliveredFramesAndExcludesQueuedLookahead() throws Exception {
        FakeEngine engine = new FakeEngine();
        CrisperAudioProcessor processor = ready(engine);
        FakeEngine.Stream stream = engine.latest();
        stream.acceptedFrames = 100000;
        stream.deliveredFrames = 2000;
        stream.sourceFrames = 3000;
        assertEquals(1500000, processor.getMediaDuration(1000000));
        // Pending input grows, but it does not represent audio sent to the sink.
        stream.acceptedFrames += 100000;
        assertEquals(1500000, processor.getMediaDuration(1000000));
        processor.reset();
    }

    @Test public void rateChangeUsesOldClockUntilFlushThenStartsANewCheckpoint() throws Exception {
        FakeEngine engine = new FakeEngine();
        CrisperAudioProcessorChain chain = new CrisperAudioProcessorChain(2, engine);
        CrisperAudioProcessor processor = (CrisperAudioProcessor) chain.getAudioProcessors()[0];
        processor.configure(MONO);
        chain.applyPlaybackParameters(new PlaybackParameters(1.5f));
        processor.flush();
        long oldHandle = engine.lastHandle;
        assertEquals(1500000, chain.getMediaDuration(1000000));
        chain.applyPlaybackParameters(new PlaybackParameters(2.0f));
        assertEquals(1500000, chain.getMediaDuration(1000000));
        processor.queueEndOfStream();
        processor.flush();
        assertFalse(engine.streams.containsKey(oldHandle));
        assertEquals(2.0, engine.latest().rate, 0.0);
        assertEquals(2000000, chain.getMediaDuration(1000000));
        assertEquals(500000, processor.getDurationAfterProcessorApplied(1000000));
        assertEquals(0, engine.latest().deliveredFrames);
        processor.reset();
    }

    @Test public void seekFlushDropsPendingInputOutputAndOldClock() throws Exception {
        FakeEngine engine = new FakeEngine();
        engine.maxReadFrames = 1;
        CrisperAudioProcessor processor = ready(engine);
        processor.queueInput(pcm(111, 222, 333));
        processor.getOutput(); // Deliberately leave this old output unread.
        long oldHandle = engine.lastHandle;
        processor.flush();
        assertFalse(engine.streams.containsKey(oldHandle));
        assertFalse(processor.getOutput().hasRemaining());
        processor.queueInput(pcm(999));
        assertArrayEquals(new short[] {999}, consume(processor.getOutput()));
        assertEquals(1, engine.latest().acceptedFrames);
        processor.reset();
        processor.reset();
        assertTrue(engine.streams.isEmpty());
        assertFalse(processor.isActive());
    }

    @Test public void configurationIsPendingUntilFlushAndRejectsUnsupportedPcm() throws Exception {
        FakeEngine engine = new FakeEngine();
        CrisperAudioProcessor processor = ready(engine);
        AudioProcessor.AudioFormat stereo = new AudioProcessor.AudioFormat(44100, 2, C.ENCODING_PCM_16BIT);
        processor.configure(stereo);
        assertEquals(1, engine.latest().channels);
        processor.flush();
        assertEquals(2, engine.latest().channels);
        assertEquals(44100, engine.latest().sampleRate);
        assertThrows(AudioProcessor.UnhandledAudioFormatException.class,
            () -> processor.configure(new AudioProcessor.AudioFormat(48000, 6, C.ENCODING_PCM_16BIT)));
        assertThrows(AudioProcessor.UnhandledAudioFormatException.class,
            () -> processor.configure(new AudioProcessor.AudioFormat(48000, 2, C.ENCODING_PCM_FLOAT)));
        processor.reset();
    }

    @Test public void nativeChainHasOnlyOneSpeedStageAndNoSilenceSkip() {
        CrisperAudioProcessorChain chain = new CrisperAudioProcessorChain(1, new FakeEngine());
        assertEquals(1, chain.getAudioProcessors().length);
        assertTrue(chain.getAudioProcessors()[0] instanceof CrisperAudioProcessor);
        assertFalse(chain.applySkipSilenceEnabled(true));
        assertFalse(chain.applySkipSilenceEnabled(false));
        assertEquals(0, chain.getSkippedOutputFrameCount());
        assertThrows(IllegalArgumentException.class,
            () -> chain.applyPlaybackParameters(new PlaybackParameters(1.5f, 1.2f)));
        CrisperAudioProcessor processor = (CrisperAudioProcessor) chain.getAudioProcessors()[0];
        assertThrows(IllegalArgumentException.class, () -> processor.setRate(Double.NaN));
        assertThrows(IllegalArgumentException.class, () -> processor.setRate(0.49));
        assertThrows(IllegalArgumentException.class, () -> processor.setRate(3.01));
    }

    @Test public void pcmSinkDisablesEncodedPassthroughAndOffload() {
        int[] lastOffload = {-1};
        AudioSink delegate = (AudioSink) Proxy.newProxyInstance(
            AudioSink.class.getClassLoader(), new Class<?>[] {AudioSink.class}, (proxy, method, args) -> {
                switch (method.getName()) {
                    case "supportsFormat": return true;
                    case "getFormatSupport": return AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY;
                    case "setOffloadMode": lastOffload[0] = (Integer) args[0]; return null;
                    default: throw new AssertionError("Unexpected delegate call: " + method.getName());
                }
            });
        CrisperPcmAudioSink sink = new CrisperPcmAudioSink(delegate);
        Format encoded = new Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AC3).build();
        Format pcm = new Format.Builder().setSampleMimeType(MimeTypes.AUDIO_RAW)
            .setChannelCount(2).setSampleRate(48000).setPcmEncoding(C.ENCODING_PCM_16BIT).build();
        assertFalse(sink.supportsFormat(encoded));
        assertEquals(AudioSink.SINK_FORMAT_UNSUPPORTED, sink.getFormatSupport(encoded));
        assertTrue(sink.supportsFormat(pcm));
        assertEquals(AudioSink.SINK_FORMAT_SUPPORTED_DIRECTLY, sink.getFormatSupport(pcm));
        assertSame(AudioOffloadSupport.DEFAULT_UNSUPPORTED, sink.getFormatOffloadSupport(encoded));
        sink.setOffloadMode(AudioSink.OFFLOAD_MODE_ENABLED_GAPLESS_NOT_REQUIRED);
        assertEquals(AudioSink.OFFLOAD_MODE_DISABLED, lastOffload[0]);
    }

    private static CrisperAudioProcessor ready(FakeEngine engine) throws Exception {
        CrisperAudioProcessor processor = new CrisperAudioProcessor(1, engine);
        processor.configure(MONO);
        processor.flush();
        return processor;
    }

    private static ByteBuffer pcm(int... samples) {
        ByteBuffer buffer = ByteBuffer.allocateDirect(samples.length * 2).order(ByteOrder.nativeOrder());
        for (int sample : samples) buffer.putShort((short) sample);
        buffer.flip();
        return buffer;
    }

    private static short[] consume(ByteBuffer buffer) {
        short[] result = new short[buffer.remaining() / 2];
        for (int i = 0; i < result.length; i++) result[i] = buffer.getShort();
        return result;
    }

    private static void collect(ByteBuffer buffer, List<Short> result) {
        while (buffer.hasRemaining()) result.add(buffer.getShort());
    }

    private static final class FakeEngine implements CrisperDspEngine {
        static final class Stream {
            final int sampleRate, channels;
            final double rate;
            final ArrayDeque<Short> samples = new ArrayDeque<>();
            long acceptedFrames, deliveredFrames, sourceFrames;
            boolean finished;
            Stream(int sampleRate, int channels, double rate) {
                this.sampleRate = sampleRate; this.channels = channels; this.rate = rate;
            }
        }
        final Map<Long, Stream> streams = new HashMap<>();
        long lastHandle;
        int lastEngineId;
        int maxWriteFrames = Integer.MAX_VALUE, maxReadFrames = Integer.MAX_VALUE;
        int finishCalls, readCalls;
        Stream latest() { return streams.get(lastHandle); }
        @Override public long create(int engine, int sampleRate, int channels, double rate) {
            lastEngineId = engine;
            streams.put(++lastHandle, new Stream(sampleRate, channels, rate));
            return lastHandle;
        }
        @Override public void destroy(long handle) { assertNotNull(streams.remove(handle)); }
        @Override public int write(long handle, ByteBuffer input, int offsetBytes, int frames) {
            Stream stream = streams.get(handle);
            int consumed = Math.min(maxWriteFrames, frames);
            for (int i = 0; i < consumed * stream.channels; i++) {
                stream.samples.add(input.getShort(offsetBytes + i * 2));
            }
            stream.acceptedFrames += consumed;
            return consumed;
        }
        @Override public int read(long handle, ByteBuffer output, int maxFrames) {
            readCalls++;
            Stream stream = streams.get(handle);
            int frames = Math.min(Math.min(maxReadFrames, maxFrames), stream.samples.size() / stream.channels);
            for (int i = 0; i < frames * stream.channels; i++) output.putShort(i * 2, stream.samples.remove());
            stream.deliveredFrames += frames;
            stream.sourceFrames = Math.round(stream.deliveredFrames * stream.rate);
            return frames;
        }
        @Override public void finish(long handle) { finishCalls++; streams.get(handle).finished = true; }
        @Override public boolean ended(long handle) {
            Stream stream = streams.get(handle);
            return stream.finished && stream.samples.isEmpty();
        }
        @Override public long sourceFrames(long handle) { return streams.get(handle).sourceFrames; }
        @Override public long outputFrames(long handle) { return streams.get(handle).deliveredFrames; }
    }
}
