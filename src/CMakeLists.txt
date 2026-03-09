set(lib_name ${project_name}) # Default name for the library is project_name

# Add config.h file to build
configure_file(config.h.in config.h)

# Add src files to library
set(SRC_PATTERN "*.cpp; *.cu")
file(GLOB srcLibFiles RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${SRC_PATTERN})
file(GLOB srcCudaFilesToPTX "*.ptx.cu")

# Get current folder name
get_filename_component(CURRENT_FOLDER_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
message(STATUS "Library src files found in ${CURRENT_FOLDER_NAME}: ${srcLibFiles}")

# Add subdirectories with src files
message(STATUS "Adding module: template_src")
add_subdirectory(template_src)

message(STATUS "Adding module: template_src_kernels")
add_subdirectory(template_src_kernels)

message(STATUS "Adding module: wrapped_impl")
add_subdirectory(wrapped_impl)

if (BUILD_AS_MAIN_PROJECT)
  message(STATUS "Adding module: bin")
  add_subdirectory(bin)
endif()

# Exclude EXCLUDED_LIST from the list of src files
set(EXCLUDED_LIST "")
list(REMOVE_ITEM srcLibFiles ${EXCLUDED_LIST})

# Install headers from this directory
file(GLOB installable_headers "*.h") # Discover and install all header files
install(FILES ${installable_headers} 
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${project_name}
      ) # Install headers

# Delete installable_headers
unset(installable_headers)

add_library(${lib_name} SHARED
            ${srcLibFiles})

# Link sanitizer target only for in-tree builds to avoid export/install deps.
if (ENABLE_SANITIZERS AND SANITIZER_TARGET AND TARGET ${SANITIZER_TARGET})
  target_link_libraries(${lib_name} PRIVATE ${SANITIZER_TARGET})
endif()

# If need to add other files after add_library, use:
#target_sources(${lib_name} SHARED ${srcLibFiles})

if ( ENABLE_OPTIX )
  message("Library .cu kernels files to compile as PTX: ${srcCudaFilesToPTX}")

  # Build CUDA to PTX code and const char
  get_target_property(project_interface_INCLUDE_DIRS ${project_name}_include INTERFACE_INCLUDE_DIRECTORIES)
  if (NOT project_interface_INCLUDE_DIRS)
    set(project_interface_INCLUDE_DIRS "")
  endif()

  set(PTX_INCLUDE_DIRS ${CUDAToolkit_INCLUDE_DIRS} 
                      ${OptiX_INCLUDE_DIRS} 
                      ${project_interface_INCLUDE_DIRS} 
                      ) # Include directories for PTX compilation

  cuda_compile_and_embed(embedded_ptx_code ${sm_version} "${PTX_INCLUDE_DIRS}" ${srcCudaFilesToPTX})
  # NOTE: Macro above sets up the build of CUDA kernels -> PTX code from which OptiX module is built.
  # Build occurs before compilation and linking of the library (or executables).
  # Variable embedded_ptx_code must be extern "C" const char within the cpp source code.
    
  # Add the embedded PTX code to the library
  target_sources(${lib_name} PRIVATE ${embedded_ptx_code})    
endif()

### Link targets
# Project include directories
target_link_libraries(${lib_name} PUBLIC ${project_name}_include ${LIB_COMPILE_TARGET})

# Link interface target for CUDA

if (ENABLE_CUDA)
  target_link_libraries(${lib_name} PUBLIC ${CUDA_COMPILE_TARGET})
endif()

# Link OptiX interface target
if(ENABLE_OPTIX)
  target_link_libraries(${lib_name} PUBLIC ${OPTIX_COMPILE_TARGET})
endif()

if (ENABLE_OPENGL)
  target_link_libraries(${lib_name} PUBLIC ${OPENGL_COMPILE_TARGET})
endif()

# Link profiling interface: gperftools always when found, compile flags only with ENABLE_PROFILING.
# PRIVATE: profiling is a build-time concern; not propagated to consumers and not exported.
if(TARGET ${PROFILING_COMPILE_TARGET})
  target_link_libraries(${lib_name} PRIVATE ${PROFILING_COMPILE_TARGET})
endif()

#target_include_directories(${lib_name} INTERFACE ${interface_INCLUDE_DIRS} ) 
# TIP: INTERFACE ensures that the consumer target does not need to include manually the include directories the library target depends on, because they are automagically propagated to the target, even if the target does not need thme. The same happens with PUBLIC, but this time the includes are used by the target library itself.

target_link_libraries(${lib_name} PUBLIC 
                      Eigen3::Eigen 
                      #gdt
                      #glfw 
                      #${OPENGL_LIBRARIES}
                      )

# Add target to installable list 
set(installable_targets ${installable_targets} 
                        ${lib_name} 
                        ${project_name}_include
                        ${LIB_COMPILE_TARGET})
                      
if (ENABLE_CUDA)
  list(APPEND installable_targets ${CUDA_COMPILE_TARGET})
  if(ENABLE_OPTIX)
    list(APPEND installable_targets ${OPTIX_COMPILE_TARGET})
  endif()
endif()

if (ENABLE_OPENGL)
  list(APPEND installable_targets ${OPENGL_COMPILE_TARGET})
endif()

message(NOTICE "Added target to installable list: ${installable_targets}")
#############################################################################
# Install global_includes.h file
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/global_includes.h" 
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${project_name}) 

# Install config.h file
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/config.h" 
       DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/${project_name}) 
# INSTALL CONFIGURATION
install(
	TARGETS ${installable_targets}
	EXPORT ${project_name} # Export target to be used by other projects
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
	ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
	RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
  INCLUDES DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
  ) # Install targets

# Configuration for CPack and consumer targets
# See https://cmake.org/cmake/help/latest/guide/tutorial/Adding%20Export%20Configuration.html
include(CMakePackageConfigHelpers)

install(EXPORT ${project_name}
    FILE "${project_name}Target.cmake"
    NAMESPACE ${project_name}::
    DESTINATION lib/cmake/${project_name}
)

write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/${project_name}ConfigVersion.cmake"
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)

configure_package_config_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/${project_name}Config.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/${project_name}Config.cmake"
    INSTALL_DESTINATION lib/cmake/${project_name}
)

install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/${project_name}Config.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/${project_name}ConfigVersion.cmake"
    DESTINATION lib/cmake/${project_name}
)

# Add target export to allow usage of build by other consumer projects
export(EXPORT ${lib_name}
  FILE "${CMAKE_CURRENT_BINARY_DIR}/cmake/${project_name}Target.cmake"
)
