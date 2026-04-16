cmake_minimum_required(VERSION 3.20)
project(veil CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(SOURCES
    src/main.cpp
    src/vpn_client.cpp
    src/config/config.cpp
    src/tun/tun_interface.cpp
    src/wireguard/wireguard.cpp
    src/network/route_manager.cpp
    src/proxy/proxy_parser.cpp
)

add_executable(veil ${SOURCES})
target_include_directories(veil PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_options(veil PRIVATE -Wall -Wextra -Wno-unused-parameter -Wno-missing-field-initializers)

if(APPLE)
    target_link_libraries(veil PRIVATE
        "-framework CoreFoundation"
        "-framework SystemConfiguration")
endif()

enable_testing()

add_executable(test_proxy_parser
    Tests/test_proxy_parser.cpp
    src/proxy/proxy_parser.cpp
)
target_include_directories(test_proxy_parser PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_options(test_proxy_parser PRIVATE -Wall -Wextra -Wno-unused-parameter)
add_test(NAME proxy_parser COMMAND test_proxy_parser)

add_executable(test_shared_cases
    Tests/test_shared_cases.cpp
    src/proxy/proxy_parser.cpp
)
target_include_directories(test_shared_cases PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_options(test_shared_cases PRIVATE -Wall -Wextra -Wno-unused-parameter)
add_test(NAME shared_cases COMMAND test_shared_cases ${CMAKE_CURRENT_SOURCE_DIR}/Tests/shared_test_cases.json)

add_executable(test_config
    Tests/test_config.cpp
    src/config/config.cpp
)
target_include_directories(test_config PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_options(test_config PRIVATE -Wall -Wextra -Wno-unused-parameter)
add_test(NAME config_persistence COMMAND test_config)

add_executable(test_wireguard
    Tests/test_wireguard.cpp
)
target_include_directories(test_wireguard PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_options(test_wireguard PRIVATE -Wall -Wextra -Wno-unused-parameter)
add_test(NAME wireguard COMMAND test_wireguard)

message(STATUS "Build:  cmake -B cmake-build-debug && cmake --build cmake-build-debug")
message(STATUS "Run:    sudo ./cmake-build-debug/veil connect <profile>")
message(STATUS "App:    ./cmake-build-debug/veil  (opens veil.app)")
message(STATUS "Test:   cmake --build cmake-build-debug && ctest --test-dir cmake-build-debug -V")
