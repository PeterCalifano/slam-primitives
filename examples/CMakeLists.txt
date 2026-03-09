set(lib_name ${project_name}) # Default name for the library is project_name

set(EXCLUDED_LIST "example_build")

# Add subdirectories
add_subdirectory(template_examples)

# Add examples files in this directory
add_examples(${project_name} EXCLUDED_LIST ${CUDA_COMPILE_TARGET})
