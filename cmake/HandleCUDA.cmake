# CMake configuration to handle CUDA setup and architecture detection
include_guard(GLOBAL)
include(CMakeParseArguments)

set(CUDA_ARCHITECTURES "" CACHE STRING "Override CUDA architectures (e.g. 75;86). Leave empty to auto-detect.")
set(CUDA_DETECT_MULTIPLE_ARCHS OFF CACHE BOOL "Use all detected CUDA architectures when auto-detecting.")

# Function to detect the compute capability and architecture for CUDA

function(_cuda_validate_arch_nums output_var)
    set(_validated_arch_nums "")
    foreach(_arch_num IN LISTS ARGN)
        string(STRIP "${_arch_num}" _arch_num)
        if(_arch_num STREQUAL "")
            continue()
        endif()
        if(NOT _arch_num MATCHES "^[0-9]+$")
            message(FATAL_ERROR
                "Invalid CUDA architecture value '${_arch_num}'. "
                "Expected numeric SM values such as '87' or '87;90'.")
        endif()
        list(APPEND _validated_arch_nums "${_arch_num}")
    endforeach()
    list(REMOVE_DUPLICATES _validated_arch_nums)
    set(${output_var} "${_validated_arch_nums}" PARENT_SCOPE)
endfunction()

function(_cuda_arch_nums_to_names output_var)
    _cuda_validate_arch_nums(_validated_arch_nums ${ARGN})
    set(_arch_names "")
    foreach(_arch_num IN LISTS _validated_arch_nums)
        list(APPEND _arch_names "sm_${_arch_num}")
    endforeach()
    set(${output_var} "${_arch_names}" PARENT_SCOPE)
endfunction()

function(_cuda_reduce_detected_arch_nums output_var)
    set(_reduced_arch_nums ${ARGN})
    if(_reduced_arch_nums AND NOT CUDA_DETECT_MULTIPLE_ARCHS)
        list(GET _reduced_arch_nums 0 _first_arch)
        set(_reduced_arch_nums "${_first_arch}")
    endif()
    set(${output_var} "${_reduced_arch_nums}" PARENT_SCOPE)
endfunction()

function(_cuda_parse_nvidia_smi_output output_arch_nums output_error raw_output)
    string(REPLACE "\r\n" "\n" _gpu_output "${raw_output}")
    string(REPLACE "\r" "\n" _gpu_output "${_gpu_output}")
    string(REPLACE "\n" ";" _gpu_output_list "${_gpu_output}")

    set(_raw_arch_nums "")
    foreach(_cap IN LISTS _gpu_output_list)
        string(STRIP "${_cap}" _cap)
        if(_cap STREQUAL "")
            continue()
        endif()
        if(NOT _cap MATCHES "^[0-9]+(\\.[0-9]+)?$")
            set(${output_arch_nums} "" PARENT_SCOPE)
            set(${output_error}
                "nvidia-smi returned a malformed compute capability token '${_cap}'."
                PARENT_SCOPE)
            return()
        endif()
        string(REPLACE "." "" _sm "${_cap}")
        list(APPEND _raw_arch_nums "${_sm}")
    endforeach()

    if(NOT _raw_arch_nums)
        set(${output_arch_nums} "" PARENT_SCOPE)
        set(${output_error}
            "nvidia-smi returned no compute capability data."
            PARENT_SCOPE)
        return()
    endif()

    _cuda_validate_arch_nums(_validated_arch_nums ${_raw_arch_nums})
    _cuda_reduce_detected_arch_nums(_reduced_arch_nums ${_validated_arch_nums})
    set(${output_arch_nums} "${_reduced_arch_nums}" PARENT_SCOPE)
    set(${output_error} "" PARENT_SCOPE)
endfunction()

function(_query_nvidia_smi_compute_caps output_arch_nums output_error)
    set(_nvidia_smi_command "")
    if(DEFINED CUDA_DETECT_NVIDIA_SMI_COMMAND)
        set(_nvidia_smi_command ${CUDA_DETECT_NVIDIA_SMI_COMMAND})
    elseif(DEFINED CUDA_DETECT_NVIDIA_SMI_EXECUTABLE)
        if(NOT "${CUDA_DETECT_NVIDIA_SMI_EXECUTABLE}" STREQUAL "")
            set(_nvidia_smi_command "${CUDA_DETECT_NVIDIA_SMI_EXECUTABLE}")
        endif()
    else()
        find_program(_nvidia_smi_executable nvidia-smi)
        if(_nvidia_smi_executable)
            set(_nvidia_smi_command "${_nvidia_smi_executable}")
        endif()
    endif()

    list(LENGTH _nvidia_smi_command _nvidia_smi_command_length)
    if(_nvidia_smi_command_length EQUAL 0)
        set(${output_arch_nums} "" PARENT_SCOPE)
        set(${output_error} "nvidia-smi was not found." PARENT_SCOPE)
        return()
    endif()

    execute_process(
        COMMAND
            ${_nvidia_smi_command}
            --query-gpu=compute_cap
            --format=csv,noheader
        RESULT_VARIABLE _nvidia_smi_result
        OUTPUT_VARIABLE _gpu_compute_caps
        ERROR_VARIABLE _nvidia_smi_error
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
    )

    if(NOT "${_nvidia_smi_result}" STREQUAL "0")
        set(_nvidia_smi_failure_detail "${_nvidia_smi_error}")
        if("${_nvidia_smi_failure_detail}" STREQUAL "")
            set(_nvidia_smi_failure_detail "${_gpu_compute_caps}")
        endif()
        string(STRIP "${_nvidia_smi_failure_detail}" _nvidia_smi_failure_detail)
        if("${_nvidia_smi_failure_detail}" STREQUAL "")
            set(_nvidia_smi_failure_detail "unknown error")
        endif()
        set(${output_arch_nums} "" PARENT_SCOPE)
        set(${output_error}
            "nvidia-smi failed with exit code ${_nvidia_smi_result}: ${_nvidia_smi_failure_detail}"
            PARENT_SCOPE)
        return()
    endif()

    _cuda_parse_nvidia_smi_output(_parsed_arch_nums _parsed_error "${_gpu_compute_caps}")
    if(_parsed_error)
        set(${output_arch_nums} "" PARENT_SCOPE)
        set(${output_error} "${_parsed_error}" PARENT_SCOPE)
        return()
    endif()

    set(${output_arch_nums} "${_parsed_arch_nums}" PARENT_SCOPE)
    set(${output_error} "" PARENT_SCOPE)
endfunction()

function(_cuda_read_optional_text_file output_var input_path)
    set(_file_content "")
    if(EXISTS "${input_path}")
        file(STRINGS "${input_path}" _file_lines)
        string(JOIN " " _file_content ${_file_lines})
    endif()
    string(REPLACE "\r" " " _file_content "${_file_content}")
    string(REPLACE "\n" " " _file_content "${_file_content}")
    string(STRIP "${_file_content}" _file_content)
    string(TOLOWER "${_file_content}" _file_content)
    set(${output_var} "${_file_content}" PARENT_SCOPE)
endfunction()

function(_detect_native_tegra_arch output_arch_nums output_error)
    if(CMAKE_CROSSCOMPILING)
        set(${output_arch_nums} "" PARENT_SCOPE)
        set(${output_error}
            "CUDA architecture auto-detection on aarch64 is unavailable while cross-compiling."
            PARENT_SCOPE)
        return()
    endif()

    set(_tegra_release_file "/etc/nv_tegra_release")
    set(_tegra_model_file "/proc/device-tree/model")
    set(_tegra_compatible_file "/proc/device-tree/compatible")

    if(DEFINED CUDA_DETECT_TEGRA_RELEASE_FILE)
        set(_tegra_release_file "${CUDA_DETECT_TEGRA_RELEASE_FILE}")
    endif()
    if(DEFINED CUDA_DETECT_TEGRA_MODEL_FILE)
        set(_tegra_model_file "${CUDA_DETECT_TEGRA_MODEL_FILE}")
    endif()
    if(DEFINED CUDA_DETECT_TEGRA_COMPATIBLE_FILE)
        set(_tegra_compatible_file "${CUDA_DETECT_TEGRA_COMPATIBLE_FILE}")
    endif()

    _cuda_read_optional_text_file(_tegra_release_text "${_tegra_release_file}")
    _cuda_read_optional_text_file(_tegra_model_text "${_tegra_model_file}")
    _cuda_read_optional_text_file(_tegra_compatible_text "${_tegra_compatible_file}")

    string(CONCAT _tegra_identifiers
        "${_tegra_release_text} "
        "${_tegra_model_text} "
        "${_tegra_compatible_text}")
    string(STRIP "${_tegra_identifiers}" _tegra_identifiers)

    if("${_tegra_identifiers}" STREQUAL "")
        set(${output_arch_nums} "" PARENT_SCOPE)
        set(${output_error}
            "No native Jetson/Tegra markers were found on this aarch64 system."
            PARENT_SCOPE)
        return()
    endif()

    if(NOT _tegra_identifiers MATCHES "(tegra|jetson|orin|xavier|thor)")
        set(${output_arch_nums} "" PARENT_SCOPE)
        set(${output_error}
            "The detected aarch64 system does not look like a native Jetson/Tegra device."
            PARENT_SCOPE)
        return()
    endif()

    if(_tegra_identifiers MATCHES "(tegra264|thor)")
        set(_tegra_arch_num "101")
    elseif(_tegra_identifiers MATCHES "(tegra234|orin)")
        set(_tegra_arch_num "87")
    elseif(_tegra_identifiers MATCHES "(tegra194|xavier)")
        set(_tegra_arch_num "72")
    else()
        set(${output_arch_nums} "" PARENT_SCOPE)
        set(${output_error}
            "Jetson/Tegra markers were found, but the SoC family could not be mapped automatically."
            PARENT_SCOPE)
        return()
    endif()

    set(${output_arch_nums} "${_tegra_arch_num}" PARENT_SCOPE)
    set(${output_error} "" PARENT_SCOPE)
endfunction()

# Function to detect the compute capability using nvidia-smi or native Tegra markers
function(detect_cuda_arch cuda_arch compute_cap)
    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _proc)

    set(_detected_arch_nums "")
    set(_detection_error "")

    if(_proc MATCHES "^(x86_64|amd64)$")
        _query_nvidia_smi_compute_caps(_detected_arch_nums _detection_error)
        if(_detection_error)
            message(FATAL_ERROR
                "CUDA architecture auto-detection failed on ${CMAKE_SYSTEM_PROCESSOR}: ${_detection_error} "
                "Set CUDA_ARCHITECTURES or CMAKE_CUDA_ARCHITECTURES explicitly.")
        endif()
    elseif(_proc MATCHES "^(aarch64|arm64)$")
        _query_nvidia_smi_compute_caps(_detected_arch_nums _detection_error)
        if(_detection_error)
            _detect_native_tegra_arch(_detected_arch_nums _tegra_detection_error)
            if(_tegra_detection_error)
                message(FATAL_ERROR
                    "CUDA architecture auto-detection failed on ${CMAKE_SYSTEM_PROCESSOR}: ${_detection_error} "
                    "Tegra fallback also failed: ${_tegra_detection_error} "
                    "Set CUDA_ARCHITECTURES or CMAKE_CUDA_ARCHITECTURES explicitly.")
            endif()
        endif()
    else()
        message(FATAL_ERROR
            "CUDA architecture auto-detection is unsupported for processor '${CMAKE_SYSTEM_PROCESSOR}'. "
            "Set CUDA_ARCHITECTURES or CMAKE_CUDA_ARCHITECTURES explicitly.")
    endif()

    _cuda_arch_nums_to_names(_detected_arch_names ${_detected_arch_nums})
    set(${cuda_arch} "${_detected_arch_names}" PARENT_SCOPE)
    set(${compute_cap} "${_detected_arch_nums}" PARENT_SCOPE)

    message(STATUS "Detected CUDA architectures: ${_detected_arch_names}")
    message(STATUS "Detected CUDA compute capabilities: ${_detected_arch_nums}")
endfunction()

# Function to handle CUDA setup
function(handle_cuda)
    # Get function arguments
    set(options)
    set(oneValueArgs TARGET MIN_VERSION)
    set(multiValueArgs LIBRARIES)
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
        return()
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
        _cuda_validate_arch_nums(_cuda_arch_nums ${CUDA_ARCHITECTURES})
        message(STATUS "Using explicitly configured CUDA architectures from CUDA_ARCHITECTURES: ${_cuda_arch_nums}")
    elseif(DEFINED CMAKE_CUDA_ARCHITECTURES AND NOT CMAKE_CUDA_ARCHITECTURES STREQUAL "")
        _cuda_validate_arch_nums(_cuda_arch_nums ${CMAKE_CUDA_ARCHITECTURES})
        message(STATUS "Using explicitly configured CUDA architectures from CMAKE_CUDA_ARCHITECTURES: ${_cuda_arch_nums}")
    else()
        detect_cuda_arch(_cuda_arch_names _cuda_arch_nums)
    endif()

    if(NOT _cuda_arch_names AND _cuda_arch_nums)
        _cuda_arch_nums_to_names(_cuda_arch_names ${_cuda_arch_nums})
    endif()

    if(NOT _cuda_arch_nums)
        message(FATAL_ERROR
            "Failed to resolve CUDA architectures. Set CUDA_ARCHITECTURES or CMAKE_CUDA_ARCHITECTURES explicitly.")
    endif()

    if(_cuda_arch_nums AND (NOT DEFINED CMAKE_CUDA_ARCHITECTURES OR CMAKE_CUDA_ARCHITECTURES STREQUAL ""))
        set(CMAKE_CUDA_ARCHITECTURES "${_cuda_arch_nums}" CACHE STRING "CUDA architectures" FORCE)
    endif()

    set(CUDAToolkit_FOUND TRUE CACHE BOOL "CUDA Toolkit found" FORCE)
    set(cuda_arch "${_cuda_arch_names}" PARENT_SCOPE)
    set(sm_version "${_cuda_arch_nums}" PARENT_SCOPE)
    set(CUDA_LINK_LIBRARIES "${_cuda_libs}" PARENT_SCOPE)
    set(CUDA_CONFIGURED ON PARENT_SCOPE)
endfunction()
