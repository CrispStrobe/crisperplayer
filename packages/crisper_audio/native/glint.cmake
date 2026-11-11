# Decoder-only Glint closure. No CLI, encoders, host ISA tuning or GPL codec.
# OBJECT is intentional: Dart FFI symbols have no native link-time callers.
set(CRISPER_GLINT_ROOT "${CMAKE_CURRENT_LIST_DIR}/vendor/glint")
add_library(crisper_glint OBJECT
  "${CMAKE_CURRENT_LIST_DIR}/glint_bridge.cpp"
  "${CRISPER_GLINT_ROOT}/src/mp3_decoder.cpp"
  "${CRISPER_GLINT_ROOT}/src/aac_decoder.cpp"
)
set_target_properties(crisper_glint PROPERTIES
  POSITION_INDEPENDENT_CODE ON
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
)
target_include_directories(crisper_glint PUBLIC "${CMAKE_CURRENT_LIST_DIR}")
if(MSVC)
  target_compile_definitions(crisper_glint PRIVATE _USE_MATH_DEFINES)
endif()
