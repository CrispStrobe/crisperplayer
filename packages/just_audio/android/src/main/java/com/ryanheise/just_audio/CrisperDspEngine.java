// SPDX-License-Identifier: MIT
// CrisperPlayer addition. Distributed under the package's MIT license.
package com.ryanheise.just_audio;

import java.nio.ByteBuffer;

/** Narrow native boundary, also used to verify the Media3 lifecycle independently. */
interface CrisperDspEngine {
    long create(int engine, int sampleRate, int channels, double rate);
    void destroy(long handle);
    int write(long handle, ByteBuffer input, int offsetBytes, int frames);
    int read(long handle, ByteBuffer output, int maxFrames);
    void finish(long handle);
    boolean ended(long handle);
    long sourceFrames(long handle);
    long outputFrames(long handle);
}
