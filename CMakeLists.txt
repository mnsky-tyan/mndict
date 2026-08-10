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

# Add llama.cpp
add_subdirectory(llama.cpp)

# Define our native wrapper library
add_library(llama_native SHARED jni/native_api.cpp)

# Include paths
target_include_directories(llama_native PRIVATE 
    artifacts/include
    llama.cpp/include
    llama.cpp/ggml/include
)

# Link against llama (static)
target_link_libraries(llama_native PRIVATE llama log)

# Rename output to libllama.so
set_target_properties(llama_native PROPERTIES OUTPUT_NAME "llama")
