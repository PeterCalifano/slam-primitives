# CMake configuration to handle OpenMP setup and linking
include_guard(GLOBAL)

option(ENABLE_OMP "Enable OpenMP" OFF)

if(NOT DEFINED NUM_OMP_THREADS)
    set(NUM_OMP_THREADS 8 "Number of OpenMP threads to use")
endif()

function(handle_openmp)
    if(ENABLE_OMP AND NOT NO_OPTIMIZATION)
        find_package(OpenMP REQUIRED)
        foreach(_lang C CXX)
            set(_lang_var "CMAKE_${_lang}_FLAGS")
            if(OpenMP_${_lang}_FLAGS)
                set(${_lang_var} "${${_lang_var}} ${OpenMP_${_lang}_FLAGS}" PARENT_SCOPE)
            else()
                set(${_lang_var} "${${_lang_var}} -fopenmp" PARENT_SCOPE)
            endif()
        endforeach()
    else()
        set(OpenMP_CXX_FOUND OFF PARENT_SCOPE)
    endif()
endfunction()
