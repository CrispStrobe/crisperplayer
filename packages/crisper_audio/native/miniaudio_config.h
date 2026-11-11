// SPDX-License-Identifier: MIT
// Keep only the device / PCM ring APIs. Glint owns decoding; crisper_dsp owns
// processing. No miniaudio resource manager, mixer engine, or bundled decoder.
#ifndef CRISPER_MINIAUDIO_CONFIG_H
#define CRISPER_MINIAUDIO_CONFIG_H
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#include "vendor/miniaudio.h"
#endif
