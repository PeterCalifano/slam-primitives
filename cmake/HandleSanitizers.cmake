# CMake configuration to handle sanitizers setup and linking (build only)
include_guard(GLOBAL)

function(handle_sanitizers)
    set(_sanitizer_target "sanitizer_target_interface")
    if(DEFINED SANITIZER_TARGET)
        set(_sanitizer_target "${SANITIZER_TARGET}")
    elseif(DEFINED LIB_NAMESPACE)
        set(_sanitizer_target "${LIB_NAMESPACE}_sanitizer_target_interface")
    endif()

    if(TARGET ${_sanitizer_target})
        set(SANITIZER_TARGET "${_sanitizer_target}" PARENT_SCOPE)
        return()
    endif()

    # Add sanitizer target if enabled
    add_library(${_sanitizer_target} INTERFACE)
    if(SANITIZE_BUILD AND SANITIZERS)
        target_compile_options(${_sanitizer_target} INTERFACE
            $<$<NOT:$<CONFIG:Release>>:-fsanitize=${SANITIZERS}>
        )
    endif()
    set(SANITIZER_TARGET "${_sanitizer_target}" PARENT_SCOPE)
endfunction()
