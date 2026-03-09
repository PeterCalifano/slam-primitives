# Modified and improved by Pietro Califano from OptiX SDK implementation (see copyright notice below), Dec 2025
# ======================================================================== #
# Copyright 2018 Ingo Wald                                                 #
#                                                                          #
# Licensed under the Apache License, Version 2.0 (the "License");          #
# you may not use this file except in compliance with the License.         #
# You may obtain a copy of the License at                                  #
#                                                                          #
#     http://www.apache.org/licenses/LICENSE-2.0                           #
#                                                                          #
# Unless required by applicable law or agreed to in writing, software      #
# distributed under the License is distributed on an "AS IS" BASIS,        #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. #
# See the License for the specific language governing permissions and      #
# limitations under the License.                                           #
# ======================================================================== #

#include_directories(${CUDA_TOOLKIT_INCLUDE})
if (CUDAToolkit_FOUND)
	include_directories(${CUDAToolkit_INCLUDE_DIRS})
else()
  message(FATAL_ERROR "CUDA Toolkit not found")
endif()

if (WIN32)
  add_definitions(-DNOMINMAX)
endif()

find_program(BIN2C bin2c
  DOC "Path to the cuda-sdk bin2c executable.")

if (NOT COMMAND cuda_compile_and_embed)

    macro(cuda_compile_and_embed output_var cuda_arch include_dirs)
    
    # Gather all remaining arguments as CUDA files to process
    set(cuda_files ${ARGN})
    if (NOT cuda_files)
      message(FATAL_ERROR "cuda_compile_and_embed requires at least one CUDA file.")
    endif()

    set(${output_var} "")
    set(${output_var}_SYMBOLS "")

    message(STATUS "CUDA files to compile to PTX: ${cuda_files}")
    message(STATUS "Include dirs to unpack for PTX generation: ${include_dirs}")

    # Rebuild list in case include_dirs arrives as a single semicolon-delimited string.
    set(include_dirs_list "")
    if (NOT "${include_dirs}" STREQUAL "")
      set(include_dirs_list ${include_dirs})
    endif()

    set(clean_include_dirs "")
    foreach(dir IN LISTS include_dirs_list)
      #if (dir MATCHES "-NOTFOUND$")
      #  continue()
      #endif()
      if (dir MATCHES "^\\$<BUILD_INTERFACE:([^>]+)>$")
        set(dir "${CMAKE_MATCH_1}")
      elseif (dir MATCHES "^\\$<INSTALL_INTERFACE:([^>]+)>$")
        continue()
      #elseif (dir MATCHES "^\\$<.+>$")
      #  continue()
      endif()

      if (NOT "${dir}" STREQUAL "")
        list(APPEND clean_include_dirs "${dir}")
      endif()
    endforeach()

    list(REMOVE_DUPLICATES clean_include_dirs)

    set(expanded_include_dirs "")
    foreach(dir IN LISTS clean_include_dirs)
      list(APPEND expanded_include_dirs "-I${dir}")
    endforeach()

    message(STATUS "Include dirs to nvcc: ${expanded_include_dirs}")

    # Determine C++ standard flag for nvcc
    set(cuda_cxx_standard_flag "")
    if (DEFINED CMAKE_CUDA_STANDARD)
      set(cuda_cxx_standard_flag "-std=c++${CMAKE_CUDA_STANDARD}")
    elseif (DEFINED CMAKE_CXX_STANDARD)
      set(cuda_cxx_standard_flag "-std=c++${CMAKE_CXX_STANDARD}")
    endif()

    set(_ptx_nvcc_flags)
    if (CUDA_PTX_USE_FAST_MATH)
      list(APPEND _ptx_nvcc_flags --use_fast_math)
    endif()
    if (DEFINED CUDA_PTX_NVCC_FLAGS AND NOT "${CUDA_PTX_NVCC_FLAGS}" STREQUAL "")
      list(APPEND _ptx_nvcc_flags ${CUDA_PTX_NVCC_FLAGS})
    endif()
    list(REMOVE_DUPLICATES _ptx_nvcc_flags)

    # Process each CUDA file to PTX binary and embed as const char string
    list(LENGTH cuda_files cuda_files_count)
    foreach(cuda_file IN LISTS cuda_files)
      # Define name for the PTX variable
      get_filename_component(cuda_file_name ${cuda_file} NAME_WE)
      set(ptx_file ${CMAKE_CURRENT_BINARY_DIR}/${cuda_file_name}.ptx)

      if (cuda_files_count GREATER 1)
        set(c_var_name "${output_var}_${cuda_file_name}")
        string(MAKE_C_IDENTIFIER "${c_var_name}" c_var_name)
      else()
        set(c_var_name "${output_var}")
      endif()

      # Step 1: Compile CUDA file to PTX
      add_custom_command(
        OUTPUT ${ptx_file}
        COMMAND ${CMAKE_CUDA_COMPILER}
                --ptx
                --generate-line-info
                --keep
                ${cuda_cxx_standard_flag}
                --relocatable-device-code=true
                ${_ptx_nvcc_flags}
                -arch=sm_${cuda_arch}
                ${cuda_file}
                -o ${ptx_file}
                ${expanded_include_dirs}
        DEPENDS ${cuda_file}
        COMMENT "Compiling ${cuda_file} to PTX"
      )

      # Step 2: Embed PTX as a const char string using bin2c (in cuda/bin)
      set(embedded_file ${CMAKE_CURRENT_BINARY_DIR}/${cuda_file_name}_embedded.c)

      add_custom_command(
        OUTPUT ${embedded_file}
        COMMAND ${BIN2C} -c --padd 0 --type char --name ${c_var_name} ${ptx_file} > ${embedded_file}
        DEPENDS ${ptx_file}
        COMMENT "Embedding PTX from ${cuda_file} as const char ${c_var_name}[]"
      )

      # Step 3: Compile the embedded file to an object file using the C compiler
      set(object_file ${CMAKE_CURRENT_BINARY_DIR}/${cuda_file_name}_embedded.o)

      add_custom_command(
        OUTPUT ${object_file}
        COMMAND ${CMAKE_C_COMPILER} 
                -c ${embedded_file} 
                -o ${object_file}
                ${expanded_include_dirs}
        DEPENDS ${embedded_file}
        COMMENT "Compiling ${embedded_file} to object file"
      )
      
      # Append the object file and symbol name to the output variables
      list(APPEND ${output_var} ${object_file}) # This gets returned and added to source targets
      list(APPEND ${output_var}_SYMBOLS ${c_var_name})

    endforeach()
  endmacro()

endif()
