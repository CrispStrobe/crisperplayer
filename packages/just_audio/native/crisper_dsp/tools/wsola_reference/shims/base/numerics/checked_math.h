// SPDX-License-Identifier: MIT
// Test-only compatibility shim; never compiled into the app.
#pragma once
#include <cstdint>
#include <limits>
#include <stdexcept>
namespace base {
template<class T> struct CheckedValue {
  int64_t value;
  T ValueOrDie() const {
    if (value < 0 || static_cast<uint64_t>(value) > std::numeric_limits<T>::max())
      throw std::out_of_range("reference checked cast");
    return static_cast<T>(value);
  }
};
struct CheckedDifference {
  int64_t value;
  template<class T> CheckedValue<T> Cast() const { return {value}; }
};
template<class A, class B> CheckedDifference CheckSub(A a, B b) {
  return {static_cast<int64_t>(a) - static_cast<int64_t>(b)};
}
}
