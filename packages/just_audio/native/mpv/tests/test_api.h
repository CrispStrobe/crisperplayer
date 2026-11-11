// SPDX-License-Identifier: MIT
// Minimal host-side model of mpv's frame/pin contract. This is test scaffolding,
// not a replacement native player or copied mpv implementation.
#pragma once
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MP_NOPTS_VALUE (-1e20)
#define MPMIN(a, b) ((a) < (b) ? (a) : (b))
#define mp_assert assert
#define MP_ERR(f, ...) fprintf(stderr, __VA_ARGS__)
#define talloc_steal(parent, pointer) (pointer)
#define TA_FREEP(pointer) do { test_free(*(pointer)); *(pointer) = NULL; } while (0)
#define talloc_free test_free
#define AF_FORMAT_FLOAT 1
#define OPT_CHOICE(...) 0

enum { MP_FRAME_NONE, MP_FRAME_AUDIO, MP_FRAME_EOF };
enum { MP_PIN_IN, MP_PIN_OUT, MP_FILTER_COMMAND_SET_SPEED };
struct mp_frame { int type; void *data; };
#define MAKE_FRAME(type, data) ((struct mp_frame){(type), (data)})
#define MP_EOF_FRAME MAKE_FRAME(MP_FRAME_EOF, NULL)

struct mp_aframe {
    int tag, rate, channels, format, size, offset;
    double pts, speed;
    float *data;
    uint8_t *planes[1];
};
struct mp_aframe_pool { int unused; };
struct mp_pin {
    struct mp_aframe **input;
    int count, index;
    bool sent_eof;
    struct mp_frame output;
};
struct mp_filter {
    void *priv;
    struct mp_filter *error_handler;
    struct mp_pin *ppins[2], *pins[2];
    bool failed;
    int progress;
};
struct mp_autoconvert { struct mp_filter *f; };
struct mp_filter_command { int type; double speed; };
struct mp_filter_info {
    const char *name;
    size_t priv_size;
    void (*process)(struct mp_filter *);
    bool (*command)(struct mp_filter *, struct mp_filter_command *);
    void (*reset)(struct mp_filter *), (*destroy)(struct mp_filter *);
};
struct m_option { const char *name; int unused; };
struct mp_user_filter_entry {
    struct {
        const char *description, *name;
        size_t priv_size;
        const void *priv_defaults;
        const struct m_option *options;
    } desc;
    struct mp_filter *(*create)(struct mp_filter *, void *);
};

static void test_free(void *pointer) {
    if (!pointer) return;
    struct mp_aframe *frame = pointer;
    assert(frame->tag == 42);
    free(frame->data);
    free(frame);
}
static struct mp_aframe *mp_aframe_create(void) {
    struct mp_aframe *f = calloc(1, sizeof(*f));
    f->tag = 42; f->speed = 1; f->pts = MP_NOPTS_VALUE;
    return f;
}
static void mp_aframe_reset(struct mp_aframe *f) {
    free(f->data); memset(f, 0, sizeof(*f));
    f->tag = 42; f->speed = 1; f->pts = MP_NOPTS_VALUE;
}
static void mp_aframe_config_copy(struct mp_aframe *a, struct mp_aframe *b) {
    a->rate = b->rate; a->channels = b->channels; a->format = b->format;
}
static bool mp_aframe_config_equals(struct mp_aframe *a, struct mp_aframe *b) {
    return a->rate == b->rate && a->channels == b->channels && a->format == b->format;
}
static void mp_aframe_copy_attributes(struct mp_aframe *a, struct mp_aframe *b) {
    a->pts = b->pts; a->speed = b->speed;
}
static struct mp_aframe *mp_aframe_new_ref(struct mp_aframe *format) {
    assert(!format->data);
    struct mp_aframe *f = mp_aframe_create();
    mp_aframe_config_copy(f, format); mp_aframe_copy_attributes(f, format);
    return f;
}
static int mp_aframe_pool_allocate(struct mp_aframe_pool *p, struct mp_aframe *f, int n) {
    (void)p; f->data = calloc((size_t)n * f->channels, sizeof(float));
    f->size = n; f->offset = 0; return f->data ? 0 : -1;
}
static int mp_aframe_get_rate(struct mp_aframe *f) { return f->rate; }
static int mp_aframe_get_channels(struct mp_aframe *f) { return f->channels; }
static int mp_aframe_get_format(struct mp_aframe *f) { return f->format; }
static int mp_aframe_get_size(struct mp_aframe *f) { return f->size; }
static double mp_aframe_get_pts(struct mp_aframe *f) { return f->pts; }
static double mp_aframe_get_speed(struct mp_aframe *f) { return f->speed; }
static void mp_aframe_set_size(struct mp_aframe *f, int n) { f->size = n; }
static void mp_aframe_set_pts(struct mp_aframe *f, double pts) { f->pts = pts; }
static void mp_aframe_set_speed(struct mp_aframe *f, double speed) { f->speed = speed; }
static uint8_t **mp_aframe_get_data_ro(struct mp_aframe *f) {
    f->planes[0] = (uint8_t *)(f->data + f->offset * f->channels); return f->planes;
}
static uint8_t **mp_aframe_get_data_rw(struct mp_aframe *f) { return mp_aframe_get_data_ro(f); }
static void mp_aframe_skip_samples(struct mp_aframe *f, int n) {
    assert(n >= 0 && n <= f->size); f->size -= n; f->offset += n;
    if (f->pts != MP_NOPTS_VALUE) f->pts += (double)n * f->speed / f->rate;
}
static bool mp_pin_in_needs_data(struct mp_pin *p) { return !p->output.type; }
static struct mp_frame mp_pin_out_read(struct mp_pin *p) {
    if (p->index < p->count) return MAKE_FRAME(MP_FRAME_AUDIO, p->input[p->index++]);
    if (!p->sent_eof) { p->sent_eof = true; return MP_EOF_FRAME; }
    return MAKE_FRAME(MP_FRAME_NONE, NULL);
}
static bool mp_pin_in_write(struct mp_pin *p, struct mp_frame f) {
    assert(!p->output.type); p->output = f; return true;
}
static void mp_frame_unref(struct mp_frame *f) { test_free(f->data); *f = (struct mp_frame){0}; }
static void mp_filter_internal_mark_failed(struct mp_filter *f) { f->failed = true; }
static void mp_filter_set_error_handler(struct mp_filter *f, struct mp_filter *handler) { f->error_handler = handler; }
static bool mp_filter_has_failed(struct mp_filter *f) { bool failed = f->failed; f->failed = false; return failed; }
static void mp_filter_internal_mark_progress(struct mp_filter *f) { ++f->progress; }

// Creation uses real mpv during native integration CI; the host harness below
// supplies its input/output pins directly and exercises the actual callbacks.
static struct mp_filter *mp_filter_create(struct mp_filter *p, const struct mp_filter_info *i) { (void)p; (void)i; return NULL; }
static struct mp_pin *mp_filter_add_pin(struct mp_filter *f, int d, const char *n) { (void)f; (void)d; (void)n; return NULL; }
static struct mp_aframe_pool *mp_aframe_pool_create(void *p) { (void)p; return NULL; }
static struct mp_autoconvert *mp_autoconvert_create(struct mp_filter *p) { (void)p; return NULL; }
static void mp_autoconvert_add_afmt(struct mp_autoconvert *p, int f) { (void)p; (void)f; }
static void mp_pin_connect(struct mp_pin *a, struct mp_pin *b) { (void)a; (void)b; }
