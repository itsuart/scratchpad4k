# CMakeList.txt : CMake project for scratchpad4k, include source and define
# project specific logic here.
#
cmake_minimum_required (VERSION 3.20)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Enable Hot Reload for MSVC compilers if supported.
if (POLICY CMP0141)
  cmake_policy(SET CMP0141 NEW)
  set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT "$<IF:$<AND:$<C_COMPILER_ID:MSVC>,$<CXX_COMPILER_ID:MSVC>>,$<$<CONFIG:Debug,RelWithDebInfo>:EditAndContinue>,$<$<CONFIG:Debug,RelWithDebInfo>:ProgramDatabase>>")
endif()

project ("scratchpad4k")

# Add source to this project's executable.
add_executable (scratchpad4k "src/main.cpp" "src/main_window.cpp" "src/window_msg_dispatcher.cpp" "src/helpers/string_conversions.cpp" "src/helpers/error_message.cpp")

set_property(TARGET scratchpad4k PROPERTY CXX_STANDARD 20)
set_property(TARGET scratchpad4k PROPERTY WIN32_EXECUTABLE on)

target_link_libraries(scratchpad4k PRIVATE Shcore.lib)

# TODO: Add tests and install targets if needed.
