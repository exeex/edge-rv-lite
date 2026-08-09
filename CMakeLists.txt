cmake_minimum_required(VERSION 3.20)
project(edge_rv_lite LANGUAGES NONE)

find_program(VERILATOR verilator REQUIRED)
enable_testing()

set(RTL
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_decode.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_serial_ctrl.v)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/obj_dir/Vedge_rv_lite_tb
  COMMAND ${VERILATOR} --binary --timing --top-module edge_rv_lite_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/obj_dir
          ${RTL} ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_serial_ctrl_tb.v
  DEPENDS ${RTL} ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_serial_ctrl_tb.v)
add_custom_target(edge_rv_lite_tb_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/obj_dir/Vedge_rv_lite_tb)
add_test(NAME edge_rv_lite_serial
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/obj_dir/Vedge_rv_lite_tb)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/redirect_obj/Vedge_rv_lite_frontend_redirect_tb
  COMMAND ${VERILATOR} --binary --timing
          --top-module edge_rv_lite_frontend_redirect_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/redirect_obj
          ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_frontend.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_frontend_redirect_tb.v
  DEPENDS ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_frontend.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_frontend_redirect_tb.v)
add_custom_target(edge_rv_lite_frontend_redirect_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/redirect_obj/Vedge_rv_lite_frontend_redirect_tb)
add_test(NAME edge_rv_lite_frontend_redirect
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/redirect_obj/Vedge_rv_lite_frontend_redirect_tb)
