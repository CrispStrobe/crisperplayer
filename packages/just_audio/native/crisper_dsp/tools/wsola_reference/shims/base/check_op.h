// SPDX-License-Identifier: MIT
// Test-only compatibility shim; never compiled into the app.
#pragma once
#include <stdexcept>
#define CHECK_EQ(a,b) do { if ((a)!=(b)) throw std::runtime_error("reference CHECK_EQ"); } while(0)
#define DCHECK_EQ CHECK_EQ
#define DCHECK_LE(a,b) do { if ((a)>(b)) throw std::runtime_error("reference DCHECK_LE"); } while(0)
