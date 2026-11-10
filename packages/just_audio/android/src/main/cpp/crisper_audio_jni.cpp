// SPDX-License-Identifier: MIT
// CrisperPlayer's JNI transport; DSP source provenance is in native/crisper_dsp.
#include <jni.h>
#include <cstdint>
#include <exception>
#include <new>
#include "crisper_dsp.h"

namespace {
struct Handle {
    cp_dsp *processor;
    int channels;
};

void fail(JNIEnv *env, const char *message) {
    if (env->ExceptionCheck()) return;
    jclass type = env->FindClass("java/lang/IllegalStateException");
    if (type) env->ThrowNew(type, message && *message ? message : "Native audio processor failed");
}

Handle *handle(JNIEnv *env, jlong value) {
    if (!value) {
        fail(env, "Native audio processor is closed");
        return nullptr;
    }
    return reinterpret_cast<Handle *>(static_cast<intptr_t>(value));
}

int16_t *buffer(JNIEnv *env, jobject value, jint offset, jint frames, int channels) {
    if (!value || offset < 0 || frames < 0 || (offset % sizeof(int16_t)) != 0) {
        fail(env, "Invalid native PCM buffer range");
        return nullptr;
    }
    auto *base = static_cast<uint8_t *>(env->GetDirectBufferAddress(value));
    const jlong capacity = env->GetDirectBufferCapacity(value);
    const int64_t bytes = static_cast<int64_t>(frames) * channels * sizeof(int16_t);
    if (!base || capacity < 0 || static_cast<int64_t>(offset) + bytes > capacity) {
        fail(env, "PCM buffer must be direct and contain complete frames");
        return nullptr;
    }
    return reinterpret_cast<int16_t *>(base + offset);
}

template <typename Result, typename Callback>
Result guarded(JNIEnv *env, Result errorResult, Callback callback) {
    try {
        return callback();
    } catch (const std::exception &error) {
        fail(env, error.what());
    } catch (...) {
        fail(env, "Unexpected native audio processor failure");
    }
    return errorResult;
}
}  // namespace

extern "C" {
JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_JniCrisperDspEngine_create(
    JNIEnv *env, jobject, jint engine, jint sampleRate, jint channels, jdouble rate) {
    return guarded<jlong>(env, 0, [&]() -> jlong {
        cp_dsp *processor = cp_dsp_create(engine, sampleRate, channels, rate);
        if (!processor) { fail(env, cp_dsp_last_error()); return 0; }
        auto *value = new (std::nothrow) Handle{processor, channels};
        if (!value) {
            cp_dsp_destroy(processor);
            fail(env, "Unable to allocate native audio processor handle");
            return 0;
        }
        return static_cast<jlong>(reinterpret_cast<intptr_t>(value));
    });
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_JniCrisperDspEngine_destroy(JNIEnv *env, jobject, jlong value) {
    guarded<int>(env, 0, [&]() {
        if (value) {
            auto *current = reinterpret_cast<Handle *>(static_cast<intptr_t>(value));
            cp_dsp_destroy(current->processor);
            delete current;
        }
        return 0;
    });
}

JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_JniCrisperDspEngine_write(
    JNIEnv *env, jobject, jlong value, jobject input, jint offset, jint frames) {
    return guarded<jint>(env, 0, [&]() -> jint {
        Handle *current = handle(env, value);
        if (!current) return 0;
        int16_t *samples = buffer(env, input, offset, frames, current->channels);
        if (!samples) return 0;
        int consumed = cp_dsp_write_s16(current->processor, samples, frames);
        if (consumed < 0) fail(env, cp_dsp_last_error());
        return consumed;
    });
}

JNIEXPORT jint JNICALL
Java_com_ryanheise_just_1audio_JniCrisperDspEngine_read(
    JNIEnv *env, jobject, jlong value, jobject output, jint frames) {
    return guarded<jint>(env, 0, [&]() -> jint {
        Handle *current = handle(env, value);
        if (!current) return 0;
        int16_t *samples = buffer(env, output, 0, frames, current->channels);
        if (!samples) return 0;
        int delivered = cp_dsp_read_s16(current->processor, samples, frames);
        if (delivered < 0) fail(env, cp_dsp_last_error());
        return delivered;
    });
}

JNIEXPORT void JNICALL
Java_com_ryanheise_just_1audio_JniCrisperDspEngine_finish(JNIEnv *env, jobject, jlong value) {
    guarded<int>(env, 0, [&]() {
        Handle *current = handle(env, value);
        if (current && cp_dsp_finish(current->processor) < 0) fail(env, cp_dsp_last_error());
        return 0;
    });
}

JNIEXPORT jboolean JNICALL
Java_com_ryanheise_just_1audio_JniCrisperDspEngine_ended(JNIEnv *env, jobject, jlong value) {
    return guarded<jboolean>(env, JNI_FALSE, [&]() -> jboolean {
        Handle *current = handle(env, value);
        if (!current) return JNI_FALSE;
        int result = cp_dsp_ended(current->processor);
        if (result < 0) fail(env, cp_dsp_last_error());
        return result > 0 ? JNI_TRUE : JNI_FALSE;
    });
}

JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_JniCrisperDspEngine_sourceFrames(JNIEnv *env, jobject, jlong value) {
    return guarded<jlong>(env, 0, [&]() -> jlong {
        Handle *current = handle(env, value);
        if (!current) return 0;
        int64_t result = cp_dsp_source_frames(current->processor);
        if (result < 0) fail(env, cp_dsp_last_error());
        return result;
    });
}

JNIEXPORT jlong JNICALL
Java_com_ryanheise_just_1audio_JniCrisperDspEngine_outputFrames(JNIEnv *env, jobject, jlong value) {
    return guarded<jlong>(env, 0, [&]() -> jlong {
        Handle *current = handle(env, value);
        if (!current) return 0;
        int64_t result = cp_dsp_output_frames(current->processor);
        if (result < 0) fail(env, cp_dsp_last_error());
        return result;
    });
}
}  // extern "C"
