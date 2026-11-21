cmake_minimum_required(VERSION 3.22.1)
project(mnnllm_jni CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(MNN_LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

add_library(mnnllm_jni SHARED mnn_llm_jni.cpp)

target_include_directories(mnnllm_jni PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include)

add_library(mnnllm SHARED IMPORTED)
set_target_properties(mnnllm PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libllm.so)
add_library(mnn_core SHARED IMPORTED)
set_target_properties(mnn_core PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libMNN.so)
add_library(mnn_express SHARED IMPORTED)
set_target_properties(mnn_express PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libMNN_Express.so)
add_library(mnn_cl SHARED IMPORTED)
set_target_properties(mnn_cl PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libMNN_CL.so)
add_library(mnn_vulkan SHARED IMPORTED)
set_target_properties(mnn_vulkan PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libMNN_Vulkan.so)
add_library(mnn_opencv SHARED IMPORTED)
set_target_properties(mnn_opencv PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libMNNOpenCV.so)
add_library(mnn_audio SHARED IMPORTED)
set_target_properties(mnn_audio PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libMNNAudio.so)
add_library(mnn_core_aux SHARED IMPORTED)
set_target_properties(mnn_core_aux PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libmnncore.so)
add_library(cpp_shared SHARED IMPORTED)
set_target_properties(cpp_shared PROPERTIES IMPORTED_LOCATION ${MNN_LIB_DIR}/libc++_shared.so)

find_library(log-lib log)

target_link_libraries(mnnllm_jni
        ${log-lib}
        android
        mnnllm
        mnn_core
        mnn_express
        mnn_cl
        mnn_vulkan
        mnn_opencv
        mnn_audio
        mnn_core_aux
        cpp_shared)
