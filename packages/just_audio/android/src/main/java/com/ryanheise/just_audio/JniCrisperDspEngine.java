// SPDX-License-Identifier: MIT
// CrisperPlayer addition. Distributed under the package's MIT license.
package com.ryanheise.just_audio;

import java.nio.ByteBuffer;

/** Loaded only when a native alternative is selected; Sonic never loads this library. */
final class JniCrisperDspEngine implements CrisperDspEngine {
    private static boolean loaded;

    static synchronized void ensureLoaded() {
        if (loaded) return;
        try {
            System.loadLibrary("crisper_audio_dsp");
            loaded = true;
        } catch (LinkageError error) {
            throw new IllegalStateException("The selected native audio processor could not be loaded", error);
        }
    }

    JniCrisperDspEngine() { ensureLoaded(); }

    @Override public native long create(int engine, int sampleRate, int channels, double rate);
    @Override public native void destroy(long handle);
    @Override public native int write(long handle, ByteBuffer input, int offsetBytes, int frames);
    @Override public native int read(long handle, ByteBuffer output, int maxFrames);
    @Override public native void finish(long handle);
    @Override public native boolean ended(long handle);
    @Override public native long sourceFrames(long handle);
    @Override public native long outputFrames(long handle);
}
