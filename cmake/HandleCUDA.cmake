# CMake configuration to handle CUDA setup and architecture detection
include_guard(GLOBAL)
include(CMakeParseArguments)

set(CUDA_ARCHITECTURES "" CACHE STRING "Override CUDA architectures (e.g. 75;86). Leave empty to auto-detect.")
set(CUDA_DETECT_MULTIPLE_ARCHS OFF CACHE BOOL "Use all detected CUDA architectures when auto-detecting.")

# Function to detect the compute capability using nvidia-smi
function(detect_cuda_arch cuda_arch compute_cap)
    if(NOT CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
        message(WARNING "CUDA architecture detection is not supported for this platform.")
        set(${cuda_arch} "" PARENT_SCOPE)
        set(${compute_cap} "" PARENT_SCOPE)
        return()
    endif()

    find_program(NVIDIA_SMI nvidia-smi)
    if(NOT NVIDIA_SMI)
        message(WARNING "nvidia-smi not found; CUDA architecture detection skipped.")
        set(${cuda_arch} "" PARENT_SCOPE)
        set(${compute_cap} "" PARENT_SCOPE)
        return()
    endif()

    execute_process(
        COMMAND ${NVIDIA_SMI} --query-gpu=compute_cap --format=csv,noheader
        OUTPUT_VARIABLE gpu_compute_caps
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    string(REPLACE "\n" ";" gpu_compute_caps_list "${gpu_compute_caps}")
    set(sm_archs "")
    set(clean_caps "")

    foreach(cap ${gpu_compute_caps_list})
        string(REPLACE "." "" sm "${cap}")
        list(APPEND sm_archs "sm_${sm}")
        list(APPEND clean_caps "${sm}")
    endforeach()

    if(NOT clean_caps)
        message(WARNING "No CUDA device was found on this machine. Returning empty capability list.")
        set(${cuda_arch} "" PARENT_SCOPE)
        set(${compute_cap} "" PARENT_SCOPE)
        return()
    endif()

    if(NOT CUDA_DETECT_MULTIPLE_ARCHS)
        list(GET clean_caps 0 clean_caps)
        list(GET sm_archs 0 sm_archs)
    endif()

    set(${cuda_arch} "${sm_archs}" PARENT_SCOPE)
    set(${compute_cap} "${clean_caps}" PARENT_SCOPE)

    message(STATUS "Detected CUDA compute capabilities: ${gpu_compute_caps_list}")
    message(STATUS "Using CUDA architectures: ${sm_archs}")
endfunction()

# Function to handle CUDA setup
function(handle_cuda)
    # Get function arguments 
    set(options)
    set(oneValueArgs TARGET MIN_VERSION) # Args with single value
    set(multiValueArgs LIBRARIES) # Args with multiple values
    cmake_parse_arguments(HCUDA "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Define target for compile settings (CUDA specific, empty interface by default)
    if(NOT HCUDA_TARGET)
        set(HCUDA_TARGET cuda_compile_interface)
    endif()
    if(NOT TARGET ${HCUDA_TARGET})
        add_library(${HCUDA_TARGET} INTERFACE)
    endif()

    # Set defaults if not enabled
    if(NOT ENABLE_CUDA)
        set(CUDA_CONFIGURED OFF PARENT_SCOPE)
        set(cuda_arch "" PARENT_SCOPE)
        set(sm_version "" PARENT_SCOPE)
        set(CUDA_PTX_NVCC_FLAGS "" PARENT_SCOPE)
        return() # Return if CUDA not enabled
    endif()

    if(NOT HCUDA_MIN_VERSION)
        set(HCUDA_MIN_VERSION 0)
    endif()

    # Find CUDA toolkit
    find_package(CUDAToolkit ${HCUDA_MIN_VERSION} REQUIRED)
    message(STATUS "CUDA found: ${CUDAToolkit_VERSION}")
    message(STATUS "CUDA_INCLUDE_DIRS: ${CUDAToolkit_INCLUDE_DIRS}")

    # Add include dirs and definitions to the target
    target_include_directories(${HCUDA_TARGET} INTERFACE ${CUDAToolkit_INCLUDE_DIRS})
    target_compile_definitions(${HCUDA_TARGET} INTERFACE __CUDA_ENABLED__=1)

    # Configure shared NVCC optimization flags.
    set(_cuda_shared_nvcc_flags)
    if(CUDA_ENABLE_FMAD)
        list(APPEND _cuda_shared_nvcc_flags --fmad=true)
    else()
        list(APPEND _cuda_shared_nvcc_flags --fmad=false)
    endif()

    if(CUDA_ENABLE_EXTRA_DEVICE_VECTORIZATION)
        list(APPEND _cuda_shared_nvcc_flags --extra-device-vectorization)
    endif()

    if(DEFINED CUDA_NVCC_EXTRA_FLAGS AND NOT CUDA_NVCC_EXTRA_FLAGS STREQUAL "")
        separate_arguments(_cuda_extra_flags UNIX_COMMAND "${CUDA_NVCC_EXTRA_FLAGS}")
        list(APPEND _cuda_shared_nvcc_flags ${_cuda_extra_flags})
    endif()

    list(REMOVE_DUPLICATES _cuda_shared_nvcc_flags)

    set(_cuda_compile_options ${_cuda_shared_nvcc_flags})
    if(CUDA_USE_FAST_MATH)
        list(APPEND _cuda_compile_options --use_fast_math)
    endif()

    list(REMOVE_DUPLICATES _cuda_compile_options)
    if(_cuda_compile_options)
        target_compile_options(${HCUDA_TARGET} INTERFACE
            $<$<COMPILE_LANGUAGE:CUDA>:${_cuda_compile_options}>)
    endif()

    # Link libraries to interface target
    if(HCUDA_LIBRARIES)
        set(_cuda_libs ${HCUDA_LIBRARIES})
    else()
        set(_cuda_libs CUDA::cublas CUDA::cudart CUDA::curand CUDA::cuda_driver)
    endif()
    target_link_libraries(${HCUDA_TARGET} INTERFACE ${_cuda_libs})

    # Determine CUDA architectures
    set(_cuda_arch_names "")
    set(_cuda_arch_nums "")

    if(DEFINED CUDA_ARCHITECTURES AND NOT CUDA_ARCHITECTURES STREQUAL "")
        set(_cuda_arch_nums "${CUDA_ARCHITECTURES}")
    elseif(DEFINED CMAKE_CUDA_ARCHITECTURES AND NOT CMAKE_CUDA_ARCHITECTURES STREQUAL "")
        set(_cuda_arch_nums "${CMAKE_CUDA_ARCHITECTURES}")
    else()
        detect_cuda_arch(_cuda_arch_names _cuda_arch_nums)
    endif()

    if(_cuda_arch_nums AND (NOT DEFINED CMAKE_CUDA_ARCHITECTURES OR CMAKE_CUDA_ARCHITECTURES STREQUAL ""))
        set(CMAKE_CUDA_ARCHITECTURES "${_cuda_arch_nums}" CACHE STRING "CUDA architectures" FORCE)
    endif()

    if(NOT _cuda_arch_names AND _cuda_arch_nums)
        foreach(_cap IN LISTS _cuda_arch_nums)
            list(APPEND _cuda_arch_names "sm_${_cap}")
        endforeach()
    endif()

    set(CUDAToolkit_FOUND TRUE CACHE BOOL "CUDA Toolkit found" FORCE)
    set(cuda_arch "${_cuda_arch_names}" PARENT_SCOPE)
    set(sm_version "${_cuda_arch_nums}" PARENT_SCOPE)
    set(CUDA_LINK_LIBRARIES "${_cuda_libs}" PARENT_SCOPE)
    set(CUDA_PTX_NVCC_FLAGS "${_cuda_shared_nvcc_flags}" PARENT_SCOPE)
    set(CUDA_CONFIGURED ON PARENT_SCOPE)
endfunction()
