cmake_minimum_required(VERSION 3.14)
project(llama_android)
# Force rebuild for context size change

# Optimization flags
# Optimization flags - Force O3 for both Debug and Release to ensure fast inference
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -DNDEBUG")
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -O3 -DNDEBUG")


# Configure llama.cpp options
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE) # Build llama.cpp statically
# ARM KleidiAI i8mm/dotprod microkernels (FetchContent'd at configure time)
set(GGML_CPU_KLEIDIAI ON CACHE BOOL "" FORCE)
# common lib (speculative decoding helper for DSpark draft decoding)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)

# Add llama.cpp
add_subdirectory(llama.cpp)

# Define our native wrapper library
add_library(llama_native SHARED jni/native_api.cpp)

# Include paths
target_include_directories(llama_native PRIVATE
    artifacts/include
    llama.cpp/include
    llama.cpp/ggml/include
    llama.cpp/common
)

# Link against llama (static) + common (speculative decoding)
target_link_libraries(llama_native PRIVATE llama llama-common log)

# Rename output to libllama.so
set_target_properties(llama_native PROPERTIES OUTPUT_NAME "llama")

# ---------------------------------------------------------------------------
# MNN in-app spike bridge, opt-in only: gradle passes -DMNDICT_MNN_SPIKE=ON
# when MNN_SPIKE=1 is set in the environment. Links the prebuilt arm64 static
# MNN (mnn/mnn-src/build-arm64-static, NDK 27.0.12077973) behind the C ABI in
# jni/mnn_spike.cpp for dart:ffi. Not part of production builds.
option(MNDICT_MNN_SPIKE "Build the MNN in-app spike bridge" OFF)
if(MNDICT_MNN_SPIKE)
    set(MNN_SPIKE_TREE "${CMAKE_CURRENT_SOURCE_DIR}/mnn/mnn-src")
    add_library(mnn_spike SHARED jni/mnn_spike.cpp)
    target_include_directories(mnn_spike PRIVATE
        "${MNN_SPIKE_TREE}/include"
        "${MNN_SPIKE_TREE}/transformers/llm/engine/include")
    target_link_libraries(mnn_spike PRIVATE
        "${MNN_SPIKE_TREE}/build-arm64-static/libMNN.a"
        log m android atomic)
    set_target_properties(mnn_spike PROPERTIES OUTPUT_NAME "mnnspike")
endif()
