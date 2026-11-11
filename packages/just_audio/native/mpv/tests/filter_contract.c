// SPDX-License-Identifier: MIT
#include "test_api.h"
#include "../af_crisper.c"

struct fixture {
    struct mp_filter filter, converter;
    struct crisper_priv state;
    struct crisper_options options;
    struct mp_pin input, output;
};

static struct mp_aframe *source(int rate, int channels, int count, double pts, bool silent) {
    struct mp_aframe *f = mp_aframe_create();
    f->rate = rate; f->channels = channels; f->format = AF_FORMAT_FLOAT; f->pts = pts;
    assert(!mp_aframe_pool_allocate(NULL, f, count));
    for (int i = 0; i < count; ++i)
        for (int c = 0; c < channels; ++c)
            f->data[i * channels + c] = silent ? 0 : .3 * sin(i * 2 * 3.141592653589793 * 440 / rate);
    return f;
}

static void init(struct fixture *t, int engine, double rate,
                 struct mp_aframe **frames, int count) {
    memset(t, 0, sizeof(*t));
    t->options.engine = engine;
    t->input.input = frames; t->input.count = count;
    t->filter.priv = &t->state; t->filter.ppins[1] = &t->output;
    t->state.converter = &t->converter;
    t->state.input = &t->input; t->state.options = &t->options;
    t->state.format = mp_aframe_create(); t->state.requested_speed = rate;
    t->state.origin_pts = MP_NOPTS_VALUE;
}

static struct mp_aframe *pull(struct fixture *t, bool *eof) {
    for (int attempts = 0; attempts < 10000; ++attempts) {
        crisper_process(&t->filter);
        assert(!t->filter.failed);
        struct mp_frame output = t->output.output;
        t->output.output = (struct mp_frame){0};
        if (output.type == MP_FRAME_EOF) { *eof = true; return NULL; }
        if (output.type == MP_FRAME_AUDIO) return output.data;
    }
    assert(!"mpv filter stalled");
    return NULL;
}

static void destroy(struct fixture *t) {
    crisper_destroy(&t->filter);
    test_free(t->state.format);
    for (int i = t->input.index; i < t->input.count; ++i) test_free(t->input.input[i]);
}

static void check_stream(int engine, double speed) {
    const int count = 192001; // More than the core's input capacity: partial write.
    struct mp_aframe *frames[] = {source(48000, 2, count, 5, false)};
    struct fixture t; init(&t, engine, speed, frames, 1);
    int64_t delivered = 0;
    bool eof = false;
    double peak = 0;
    while (!eof) {
        struct mp_aframe *out = pull(&t, &eof);
        if (!out) break;
        assert(out->speed == speed);
        const double expected = 5 + floor(delivered * speed) / 48000;
        assert(fabs(out->pts - expected) < 1e-9);
        for (int i = 0; i < out->size * 2; ++i) {
            assert(isfinite(out->data[i]));
            peak = fmax(peak, fabs(out->data[i]));
            if (speed == 1) {
                const double wanted = .3 * sin((delivered + i / 2) * 2 * 3.141592653589793 * 440 / 48000);
                assert(fabs(out->data[i] - wanted) < 1e-7);
            }
        }
        delivered += out->size;
        test_free(out);
    }
    assert(delivered == llround(count / speed));
    assert(peak > .1);
    destroy(&t);
}

static void check_rate_change(int engine) {
    const int count = 300001;
    struct mp_aframe *frames[] = {source(48000, 1, count, 5, false)};
    struct fixture t; init(&t, engine, 1.5, frames, 1);
    bool eof = false;
    struct mp_aframe *out = pull(&t, &eof);
    assert(out && !eof);
    int64_t old_count = out->size, new_count = 0;
    const int64_t accepted = cp_dsp_input_frames(t.state.dsp);
    test_free(out);
    struct mp_filter_command command = {MP_FILTER_COMMAND_SET_SPEED, .75};
    assert(crisper_command(&t.filter, &command));
    bool entered_new_segment = false;
    while (!eof) {
        out = pull(&t, &eof);
        if (!out) break;
        if (out->speed == 1.5) {
            assert(!entered_new_segment);
            assert(fabs(out->pts - (5 + floor(old_count * 1.5) / 48000)) < 1e-9);
            old_count += out->size;
        } else {
            assert(out->speed == .75);
            entered_new_segment = true;
            assert(fabs(out->pts - (5 + (accepted + floor(new_count * .75)) / 48000)) < 1e-9);
            new_count += out->size;
        }
        test_free(out);
    }
    assert(entered_new_segment);
    assert(old_count == llround(accepted / 1.5));
    assert(new_count == llround((count - accepted) / .75));
    destroy(&t);
}

static void check_seek(int engine) {
    struct mp_aframe *frames[] = {source(48000, 1, 240000, 5, false)};
    struct fixture t; init(&t, engine, 1.5, frames, 1);
    bool eof = false;
    test_free(pull(&t, &eof));
    crisper_reset(&t.filter);
    frames[0] = source(48000, 1, 24001, 100, true);
    t.input.index = 0; t.input.sent_eof = false;
    int64_t delivered = 0;
    while (!eof) {
        struct mp_aframe *out = pull(&t, &eof);
        if (!out) break;
        assert(fabs(out->pts - (100 + floor(delivered * 1.5) / 48000)) < 1e-9);
        for (int i = 0; i < out->size; ++i) assert(fabs(out->data[i]) < 1e-7);
        delivered += out->size;
        test_free(out);
    }
    assert(delivered == llround(24001 / 1.5));
    destroy(&t);
}

static void check_format_change(int engine) {
    struct mp_aframe *frames[] = {
        source(48000, 1, 48001, 10, false),
        source(44100, 2, 44101, 20, false),
    };
    struct fixture t; init(&t, engine, 2, frames, 2);
    bool eof = false, second = false;
    int64_t delivered[2] = {0, 0};
    while (!eof) {
        struct mp_aframe *out = pull(&t, &eof);
        if (!out) break;
        int stream = out->rate == 48000 ? 0 : 1;
        if (stream) second = true;
        else assert(!second);
        assert(out->channels == stream + 1);
        assert(fabs(out->pts - ((stream ? 20 : 10) +
                   (double)delivered[stream] * 2 / out->rate)) < 1e-9);
        delivered[stream] += out->size;
        test_free(out);
    }
    assert(delivered[0] == llround(48001 / 2.0));
    assert(delivered[1] == llround(44101 / 2.0));
    destroy(&t);
}

static void check_failure_closed(int engine, int kind) {
    struct mp_aframe *frames[] = {source(48000, kind == 0 ? 3 : 1, 4096, 5, false)};
    struct fixture t; init(&t, engine, 1.5, frames, 1);
    if (kind == 1) frames[0]->data[0] = NAN;
    if (kind == 2) {
        struct mp_filter_command command = {MP_FILTER_COMMAND_SET_SPEED, 4};
        assert(crisper_command(&t.filter, &command));
    }
    if (kind == 3) mp_filter_internal_mark_failed(&t.converter);
    bool eof = false;
    assert(!pull(&t, &eof));
    assert(eof && t.state.failed);
    // Marking an mpv user filter failed would make mpv bypass it. We must send
    // EOF without that flag, and never return raw PCM on subsequent requests.
    assert(!t.filter.failed);
    eof = false;
    assert(!pull(&t, &eof));
    assert(eof);
    destroy(&t);
}

int main(void) {
    const double rates[] = {.5, 1, 1.25, 1.5, 2, 3};
    for (int engine = 0; engine < 4; ++engine) {
        for (int rate = 0; rate < 6; ++rate) check_stream(engine, rates[rate]);
        check_rate_change(engine);
        check_seek(engine);
        check_format_change(engine);
        for (int failure = 0; failure < 4; ++failure)
            check_failure_closed(engine, failure);
    }
    puts("52 mpv callback contracts passed: PCM, source clocks, lifecycle, and no untreated audio after processor failure");
    return 0;
}
