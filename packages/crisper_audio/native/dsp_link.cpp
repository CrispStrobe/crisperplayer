// SPDX-License-Identifier: MIT
#include "crisper_output.h"
#include "crisper_dsp.h"

extern "C" CA_EXPORT const char* ca_audio_dsp_error(void) {
    return cp_dsp_last_error();
}
