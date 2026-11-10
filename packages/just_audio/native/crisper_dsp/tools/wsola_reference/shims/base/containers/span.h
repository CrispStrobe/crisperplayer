// SPDX-License-Identifier: MIT
// Test-only compatibility shim; never compiled into the app.
#pragma once
#include <span>
namespace base {
template<class T, size_t N = std::dynamic_extent> using span = std::span<T, N>;
}
