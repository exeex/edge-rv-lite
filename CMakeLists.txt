cmake_minimum_required(VERSION 3.20)
project(edge_rv_lite LANGUAGES NONE)

find_program(VERILATOR verilator REQUIRED)
enable_testing()

set(RTL
  ${CMAKE_CURRENT_LIST_DIR}/../edge-rv/edge_instruction_classifier/edge_instruction_classifier.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_decode.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_pipeline.v)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/obj_dir/Vedge_rv_lite_pipeline_tb
  COMMAND ${VERILATOR} --binary --timing --top-module edge_rv_lite_pipeline_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/obj_dir
          ${RTL} ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_pipeline_tb.v
  DEPENDS ${RTL} ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_pipeline_tb.v)
add_custom_target(edge_rv_lite_pipeline_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/obj_dir/Vedge_rv_lite_pipeline_tb)
add_test(NAME edge_rv_lite_pipeline
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/obj_dir/Vedge_rv_lite_pipeline_tb)

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

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/lsu_obj/Vedge_rv_lite_lsu_tb
  COMMAND ${VERILATOR} --binary --timing --top-module edge_rv_lite_lsu_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/lsu_obj
          ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_lsu.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_lsu_tb.v
  DEPENDS ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_lsu.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_lsu_tb.v)
add_custom_target(edge_rv_lite_lsu_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/lsu_obj/Vedge_rv_lite_lsu_tb)
add_test(NAME edge_rv_lite_lsu
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/lsu_obj/Vedge_rv_lite_lsu_tb)

set(EDGE_RV_ROOT "${CMAKE_CURRENT_LIST_DIR}/../edge-rv" CACHE PATH
    "Path to the shared edge-rv execution-unit repository")
set(EDGE_COREMARK_MEM64
    "${CMAKE_CURRENT_LIST_DIR}/../../build/cmake-harness/tests/hardware/EDGE_SOC/software/coremark_bench/coremark_bench.data64.memh"
    CACHE FILEPATH "CoreMark RV64 memory image built by the edge-e3 harness")
set(CORE_RTL
  ${EDGE_RV_ROOT}/edge_scalar_fast_alu/edge_scalar_fast_alu.v
  ${EDGE_RV_ROOT}/edge_scalar_branch/edge_scalar_branch.v
  ${EDGE_RV_ROOT}/edge_scalar_divrem/edge_scalar_divrem.v
  ${EDGE_RV_ROOT}/edge_scalar_muldiv/edge_scalar_muldiv.v
  ${EDGE_RV_ROOT}/edge_scalar_muldiv/edge_scalar_muldiv_leaf.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_frontend.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_pipeline.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_lsu.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_core.v)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/coremark_obj/Vedge_rv_lite_coremark_tb
  COMMAND ${VERILATOR} --binary --timing -Wno-fatal
          --top-module edge_rv_lite_coremark_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/coremark_obj
          ${CORE_RTL} ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_coremark_tb.v
  DEPENDS ${CORE_RTL} ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_coremark_tb.v)
add_custom_target(edge_rv_lite_coremark_vvp
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/coremark_obj/Vedge_rv_lite_coremark_tb)
add_test(NAME edge_rv_lite_coremark
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/coremark_obj/Vedge_rv_lite_coremark_tb
          +mem64=${EDGE_COREMARK_MEM64})
set_tests_properties(edge_rv_lite_coremark PROPERTIES
  REQUIRED_FILES "${EDGE_COREMARK_MEM64}" TIMEOUT 30)

foreach(adapter IN ITEMS icache dcache)
  add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${adapter}_adapter_obj/Vedge_rv_lite_${adapter}_adapter_tb
    COMMAND ${VERILATOR} --binary --timing
            --top-module edge_rv_lite_${adapter}_adapter_tb
            --Mdir ${CMAKE_CURRENT_BINARY_DIR}/${adapter}_adapter_obj
            ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_${adapter}_adapter.v
            ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_${adapter}_adapter_tb.v
    DEPENDS ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_${adapter}_adapter.v
            ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_${adapter}_adapter_tb.v)
  add_custom_target(edge_rv_lite_${adapter}_adapter_vvp ALL
    DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${adapter}_adapter_obj/Vedge_rv_lite_${adapter}_adapter_tb)
  add_test(NAME edge_rv_lite_${adapter}_adapter
    COMMAND ${CMAKE_CURRENT_BINARY_DIR}/${adapter}_adapter_obj/Vedge_rv_lite_${adapter}_adapter_tb)
endforeach()

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/decode_obj/Vedge_rv_lite_decode_tb
  COMMAND ${VERILATOR} --binary --timing --top-module edge_rv_lite_decode_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/decode_obj
          ${EDGE_RV_ROOT}/edge_instruction_classifier/edge_instruction_classifier.v
          ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_decode.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_decode_tb.v
  DEPENDS ${EDGE_RV_ROOT}/edge_instruction_classifier/edge_instruction_classifier.v
          ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_decode.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_decode_tb.v)
add_custom_target(edge_rv_lite_decode_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/decode_obj/Vedge_rv_lite_decode_tb)
add_test(NAME edge_rv_lite_decode
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/decode_obj/Vedge_rv_lite_decode_tb)
