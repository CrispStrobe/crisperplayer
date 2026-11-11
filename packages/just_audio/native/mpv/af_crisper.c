// SPDX-License-Identifier: MIT
// Copyright (c) 2026 CrisperPlayer contributors
// Optional source-built libmpv filter; uses mpv's LGPL internal filter API.
#include <math.h>

#include "audio/aframe.h"
#include "audio/format.h"
#include "common/common.h"
#include "filters/f_autoconvert.h"
#include "filters/filter_internal.h"
#include "filters/user_filters.h"
#include "options/m_option.h"
#include "crisper_dsp.h"

struct crisper_options {
    int engine;
};

struct crisper_priv {
    struct crisper_options *options;
    struct mp_filter *converter;
    struct mp_pin *input;
    struct mp_aframe *pending;
    struct mp_aframe *format;
    struct mp_aframe_pool *pool;
    cp_dsp *dsp;
    double requested_speed, running_speed;
    double origin_pts, input_speed;
    bool finishing, eof, invalid_speed, failed;
};

static void clear_segment(struct crisper_priv *p)
{
    cp_dsp_destroy(p->dsp);
    p->dsp = NULL;
    p->finishing = false;
    p->origin_pts = MP_NOPTS_VALUE;
    mp_aframe_reset(p->format);
}

static bool begin_segment(struct mp_filter *f)
{
    struct crisper_priv *p = f->priv;
    mp_assert(p->pending && !p->dsp);
    const int rate = mp_aframe_get_rate(p->pending);
    const int channels = mp_aframe_get_channels(p->pending);
    if (mp_aframe_get_format(p->pending) != AF_FORMAT_FLOAT) {
        MP_ERR(f, "crisperdsp requires interleaved float PCM\n");
        return false;
    }
    p->dsp = cp_dsp_create(p->options->engine, rate, channels,
                          p->requested_speed);
    if (!p->dsp) {
        MP_ERR(f, "crisperdsp: %s\n", cp_dsp_last_error());
        return false;
    }
    mp_aframe_config_copy(p->format, p->pending);
    mp_aframe_copy_attributes(p->format, p->pending);
    p->origin_pts = mp_aframe_get_pts(p->pending);
    p->input_speed = mp_aframe_get_speed(p->pending);
    p->running_speed = p->requested_speed;
    p->finishing = false;
    return true;
}

static bool finish_segment(struct crisper_priv *p)
{
    if (!p->dsp || p->finishing) return true;
    if (cp_dsp_finish(p->dsp) < 0) return false;
    p->finishing = true;
    return true;
}

static void crisper_process(struct mp_filter *f)
{
    struct crisper_priv *p = f->priv;
    if (!mp_pin_in_needs_data(f->ppins[1])) return;
    if (p->failed) {
        mp_pin_in_write(f->ppins[1], MP_EOF_FRAME);
        return;
    }
    if (mp_filter_has_failed(p->converter)) {
        MP_ERR(f, "crisperdsp input conversion failed\n");
        goto error;
    }
    if (p->invalid_speed) goto error;

    // Work and storage are bounded. Output is pulled before accepting more
    // input; no native frame is released until every input sample is consumed.
    for (int iteration = 0; iteration < 64; ++iteration) {
        if (p->dsp && p->running_speed != p->requested_speed &&
            !finish_segment(p)) goto error;

        if (p->dsp) {
            const int available = cp_dsp_available(p->dsp);
            if (available < 0) goto error;
            if (available > 0) {
                struct mp_aframe *out = mp_aframe_new_ref(p->format);
                const int capacity = MPMIN(available, 4096);
                if (mp_aframe_pool_allocate(p->pool, out, capacity) < 0) {
                    talloc_free(out);
                    goto error;
                }
                const int64_t source = cp_dsp_source_frames(p->dsp);
                uint8_t **planes = mp_aframe_get_data_rw(out);
                const int count = cp_dsp_read_f32(p->dsp,
                                                 (float *)planes[0], capacity);
                if (count <= 0) {
                    talloc_free(out);
                    goto error;
                }
                mp_aframe_set_size(out, count);
                mp_aframe_set_speed(out, p->input_speed * p->running_speed);
                // PTS is source time represented by PCM delivered to mpv,
                // not decoded lookahead, queued input, or device wall time.
                mp_aframe_set_pts(out, p->origin_pts == MP_NOPTS_VALUE
                    ? MP_NOPTS_VALUE
                    : p->origin_pts + (double)source * p->input_speed /
                      mp_aframe_get_rate(p->format));
                mp_pin_in_write(f->ppins[1], MAKE_FRAME(MP_FRAME_AUDIO, out));
                return;
            }
            if (p->finishing) {
                if (!cp_dsp_ended(p->dsp)) goto error;
                clear_segment(p);
                continue;
            }
        }

        if (p->pending && !mp_aframe_get_size(p->pending))
            TA_FREEP(&p->pending);

        if (!p->pending && !p->eof) {
            const struct mp_frame frame = mp_pin_out_read(p->input);
            if (frame.type == MP_FRAME_AUDIO) {
                p->pending = frame.data;
            } else if (frame.type == MP_FRAME_EOF) {
                p->eof = true;
            } else if (frame.type) {
                struct mp_frame unexpected = frame;
                mp_frame_unref(&unexpected);
                MP_ERR(f, "crisperdsp received non-audio input\n");
                goto error;
            } else {
                return;
            }
        }

        if (p->eof && !p->pending) {
            if (p->dsp) {
                if (!finish_segment(p)) goto error;
                continue;
            }
            p->eof = false;
            mp_pin_in_write(f->ppins[1], MP_EOF_FRAME);
            return;
        }
        if (!p->pending) continue;
        if (!mp_aframe_get_size(p->pending)) continue;

        if (p->dsp) {
            const double expected = p->origin_pts == MP_NOPTS_VALUE
                ? MP_NOPTS_VALUE : p->origin_pts +
                  (double)cp_dsp_input_frames(p->dsp) * p->input_speed /
                  mp_aframe_get_rate(p->format);
            const double pts = mp_aframe_get_pts(p->pending);
            const bool discontinuity = expected != MP_NOPTS_VALUE &&
                pts != MP_NOPTS_VALUE && fabs(expected - pts) > .001;
            if (!mp_aframe_config_equals(p->format, p->pending) ||
                p->input_speed != mp_aframe_get_speed(p->pending) ||
                discontinuity) {
                if (!finish_segment(p)) goto error;
                continue;
            }
        } else if (!begin_segment(f)) {
            goto error;
        }

        uint8_t **planes = mp_aframe_get_data_ro(p->pending);
        const int consumed = cp_dsp_write_f32(p->dsp, (float *)planes[0],
                                              mp_aframe_get_size(p->pending));
        if (consumed < 0) goto error;
        mp_aframe_skip_samples(p->pending, consumed);
    }
    mp_filter_internal_mark_progress(f);
    return;

error:
    MP_ERR(f, "crisperdsp processing failed: %s\n", cp_dsp_last_error());
    // mpv bypasses user filters marked failed and forwards untreated PCM.
    // End this stream instead; the Dart adapter latches the error log and
    // stops the player. No raw audio can escape while that event is delivered.
    p->failed = true;
    clear_segment(p);
    TA_FREEP(&p->pending);
    mp_pin_in_write(f->ppins[1], MP_EOF_FRAME);
}

static bool crisper_command(struct mp_filter *f, struct mp_filter_command *cmd)
{
    struct crisper_priv *p = f->priv;
    if (cmd->type != MP_FILTER_COMMAND_SET_SPEED) return false;
    if (!isfinite(cmd->speed) || cmd->speed < .5 || cmd->speed > 3) {
        MP_ERR(f, "crisperdsp supports speeds from 0.5 to 3.0\n");
        p->invalid_speed = true;
        return true;
    }
    // Drain old-rate PCM before adopting the new rate, preserving all accepted
    // source frames. A seek reset deliberately discards old audio instead.
    p->requested_speed = cmd->speed;
    p->invalid_speed = false;
    return true;
}

static void crisper_reset(struct mp_filter *f)
{
    struct crisper_priv *p = f->priv;
    clear_segment(p);
    TA_FREEP(&p->pending);
    p->eof = false;
    p->failed = false;
}

static void crisper_destroy(struct mp_filter *f) { crisper_reset(f); }

static const struct mp_filter_info crisper_filter = {
    .name = "crisperdsp",
    .priv_size = sizeof(struct crisper_priv),
    .process = crisper_process,
    .command = crisper_command,
    .reset = crisper_reset,
    .destroy = crisper_destroy,
};

static struct mp_filter *crisper_create(struct mp_filter *parent, void *options)
{
    struct mp_filter *f = mp_filter_create(parent, &crisper_filter);
    if (!f) {
        talloc_free(options);
        return NULL;
    }
    mp_filter_add_pin(f, MP_PIN_IN, "in");
    mp_filter_add_pin(f, MP_PIN_OUT, "out");
    struct crisper_priv *p = f->priv;
    p->options = talloc_steal(p, options);
    p->requested_speed = p->running_speed = p->input_speed = 1.0;
    p->origin_pts = MP_NOPTS_VALUE;
    p->format = talloc_steal(p, mp_aframe_create());
    p->pool = mp_aframe_pool_create(p);
    struct mp_autoconvert *convert = mp_autoconvert_create(f);
    if (!convert) {
        talloc_free(f);
        return NULL;
    }
    p->converter = convert->f;
    // Converter and resampler failures must end this stream too. Otherwise
    // child failures propagate to this user filter and mpv bypasses it.
    mp_filter_set_error_handler(p->converter, f);
    mp_autoconvert_add_afmt(convert, AF_FORMAT_FLOAT);
    mp_pin_connect(convert->f->pins[0], f->ppins[0]);
    p->input = convert->f->pins[1];
    return f;
}

#define OPT_BASE_STRUCT struct crisper_options
const struct mp_user_filter_entry af_crisper = {
    .desc = {
        .description = "CrisperPlayer portable pitch-preserving tempo engines",
        .name = "crisperdsp",
        .priv_size = sizeof(OPT_BASE_STRUCT),
        .priv_defaults = &(const OPT_BASE_STRUCT) {.engine = CP_DSP_SONIC},
        .options = (const struct m_option[]) {
            {"engine", OPT_CHOICE(engine,
                {"sonic", CP_DSP_SONIC}, {"bungee", CP_DSP_BUNGEE_BASIC},
                {"signalsmith", CP_DSP_SIGNALSMITH}, {"wsola", CP_DSP_WSOLA})},
            {0},
        },
    },
    .create = crisper_create,
};
