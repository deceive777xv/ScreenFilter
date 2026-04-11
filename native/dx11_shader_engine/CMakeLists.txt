cmake_minimum_required(VERSION 3.14)
project(dx11_shader_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(dx11_shader_engine SHARED
    src/shader_engine.cpp
)

target_include_directories(dx11_shader_engine PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(dx11_shader_engine PRIVATE
    d3d11
    d3dcompiler
    dxgi
)

target_compile_definitions(dx11_shader_engine PRIVATE
    SHADER_ENGINE_EXPORTS
    UNICODE
    _UNICODE
)

# Install DLL next to the Flutter executable
install(TARGETS dx11_shader_engine
    RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
    LIBRARY DESTINATION "${CMAKE_INSTALL_PREFIX}"
)
