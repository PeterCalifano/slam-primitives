# Add programs to build
set(EXAMPLES_PATTERN "*.cpp" "*.cu")
file(GLOB srcProgramsFiles RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${EXAMPLES_PATTERN})

# Exclude EXCLUDED_LIST from the list of examples
set(EXCLUDED_LIST "excluded.cpp")
list(REMOVE_ITEM srcProgramsFiles ${EXCLUDED_LIST})

# Get name of current folder
get_filename_component(CURRENT_FOLDER_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
message(STATUS "Programs files found in ${CURRENT_FOLDER_NAME}: ${srcProgramsFiles}")

set(programs_targets "")

# Add to build and link
foreach(exampleFile ${srcProgramsFiles})

    get_filename_component(program_name ${exampleFile} NAME_WE)
    add_executable(${program_name} ${exampleFile})

    target_link_libraries(${program_name} PRIVATE ${project_name} ${CUDA_COMPILE_TARGET})

    # Optionally add additional targets or properties if required
    set_target_properties(${program_name} PROPERTIES OUTPUT_NAME "${program_name}")

    # Collect target names for further processing
    list(APPEND programs_targets ${program_name})

endforeach()

# Add install configuration
install(TARGETS ${programs_targets} 
        RUNTIME DESTINATION bin)