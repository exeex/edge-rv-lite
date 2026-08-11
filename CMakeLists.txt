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
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/assembler_obj/Vedge_rv_lite_instruction_assembler_tb
  COMMAND ${VERILATOR} --binary --timing
          --top-module edge_rv_lite_instruction_assembler_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/assembler_obj
          ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_instruction_assembler.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_instruction_assembler_tb.v
  DEPENDS ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_instruction_assembler.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_instruction_assembler_tb.v)
add_custom_target(edge_rv_lite_instruction_assembler_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/assembler_obj/Vedge_rv_lite_instruction_assembler_tb)
add_test(NAME edge_rv_lite_instruction_assembler
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/assembler_obj/Vedge_rv_lite_instruction_assembler_tb)

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

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/dtcm_router_obj/Vedge_rv_lite_dtcm_router_tb
  COMMAND ${VERILATOR} --binary --timing
          --top-module edge_rv_lite_dtcm_router_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/dtcm_router_obj
          ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_dtcm_router.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_dtcm_router_tb.v
  DEPENDS ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_dtcm_router.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_dtcm_router_tb.v)
add_custom_target(edge_rv_lite_dtcm_router_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/dtcm_router_obj/Vedge_rv_lite_dtcm_router_tb)
add_test(NAME edge_rv_lite_dtcm_router
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/dtcm_router_obj/Vedge_rv_lite_dtcm_router_tb)

set(EDGE_RV_ROOT "${CMAKE_CURRENT_LIST_DIR}/../edge-rv" CACHE PATH
    "Path to the shared edge-rv execution-unit repository")
set(EDGE_COREMARK_MEM64
    "${CMAKE_CURRENT_LIST_DIR}/../../build/cmake-harness/tests/hardware/EDGE_SOC/software/coremark_bench/coremark_bench.data64.memh"
    CACHE FILEPATH "CoreMark RV64 memory image built by the edge-e3 harness")
set(CORE_RTL
  ${EDGE_RV_ROOT}/edge_instruction_classifier/edge_instruction_classifier.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_decode.v
  ${EDGE_RV_ROOT}/edge_scalar_fast_alu/edge_scalar_fast_alu.v
  ${EDGE_RV_ROOT}/edge_scalar_branch/edge_scalar_branch.v
  ${EDGE_RV_ROOT}/edge_scalar_divrem/edge_scalar_divrem.v
  ${EDGE_RV_ROOT}/edge_scalar_muldiv/edge_scalar_muldiv.v
  ${EDGE_RV_ROOT}/edge_scalar_muldiv/edge_scalar_muldiv_leaf.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_frontend.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_instruction_assembler.v
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
add_custom_target(edge_rv_lite_coremark_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/coremark_obj/Vedge_rv_lite_coremark_tb)
add_test(NAME edge_rv_lite_coremark
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/coremark_obj/Vedge_rv_lite_coremark_tb
          +mem64=${EDGE_COREMARK_MEM64})
set_tests_properties(edge_rv_lite_coremark PROPERTIES
  REQUIRED_FILES "${EDGE_COREMARK_MEM64}" TIMEOUT 30)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/accel_serial_obj/Vedge_rv_lite_accel_serial_tb
  COMMAND ${VERILATOR} --binary --timing -Wno-fatal
          --top-module edge_rv_lite_accel_serial_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/accel_serial_obj
          ${CORE_RTL} ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_accel_serial_tb.v
  DEPENDS ${CORE_RTL}
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_accel_serial_tb.v)
add_custom_target(edge_rv_lite_accel_serial_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/accel_serial_obj/Vedge_rv_lite_accel_serial_tb)
add_test(NAME edge_rv_lite_accel_serial
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/accel_serial_obj/Vedge_rv_lite_accel_serial_tb)
set_tests_properties(edge_rv_lite_accel_serial PROPERTIES TIMEOUT 30)

set(CACHED_CORE_RTL
  ${CORE_RTL}
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_icache_adapter.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_dcache_adapter.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_dtcm_router.v
  ${EDGE_RV_ROOT}/edge_ifu_icache/rtl/edge_ifu_icache_data_array.v
  ${EDGE_RV_ROOT}/edge_ifu_icache/rtl/edge_ifu_icache_tag_array.v
  ${EDGE_RV_ROOT}/edge_ifu_icache/edge_ifu_icache.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_mshr.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_hit_queue.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_lookup_buffer.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_registered_lookup_buffer.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_lookup_scheduler.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_pair_predictor.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_banked_data_array.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_tag_array.v
  ${EDGE_RV_ROOT}/edge_dcache/rtl/edge_dcache_dirty_array.v
  ${EDGE_RV_ROOT}/edge_dcache/edge_dcache.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_cached_core.v)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/cached_core_obj/Vedge_rv_lite_cached_core_tb
  COMMAND ${VERILATOR} --binary --timing -Wno-fatal
          --top-module edge_rv_lite_cached_core_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/cached_core_obj
          ${CACHED_CORE_RTL}
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_cached_core_tb.v
  DEPENDS ${CACHED_CORE_RTL}
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_cached_core_tb.v)
add_custom_target(edge_rv_lite_cached_core_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/cached_core_obj/Vedge_rv_lite_cached_core_tb)
add_test(NAME edge_rv_lite_cached_core
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/cached_core_obj/Vedge_rv_lite_cached_core_tb)
set_tests_properties(edge_rv_lite_cached_core PROPERTIES TIMEOUT 30)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/cache_biu_obj/Vedge_rv_lite_cache_biu_tb
  COMMAND ${VERILATOR} --binary --timing -Wno-fatal
          --top-module edge_rv_lite_cache_biu_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/cache_biu_obj
          ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_cache_biu.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_cache_biu_tb.v
  DEPENDS ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_cache_biu.v
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_cache_biu_tb.v)
add_custom_target(edge_rv_lite_cache_biu_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/cache_biu_obj/Vedge_rv_lite_cache_biu_tb)
add_test(NAME edge_rv_lite_cache_biu
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/cache_biu_obj/Vedge_rv_lite_cache_biu_tb)
set_tests_properties(edge_rv_lite_cache_biu PROPERTIES TIMEOUT 30)

set(AXI_CORE_RTL
  ${CACHED_CORE_RTL}
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_cache_biu.v
  ${CMAKE_CURRENT_LIST_DIR}/rtl/edge_rv_lite_axi_core.v)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/axi_coremark_obj/Vedge_rv_lite_axi_coremark_tb
  COMMAND ${VERILATOR} --binary --timing -Wno-fatal
          --top-module edge_rv_lite_axi_coremark_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/axi_coremark_obj
          ${AXI_CORE_RTL}
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_axi_coremark_tb.v
  DEPENDS ${AXI_CORE_RTL}
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_axi_coremark_tb.v)
add_custom_target(edge_rv_lite_axi_coremark_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/axi_coremark_obj/Vedge_rv_lite_axi_coremark_tb)
add_test(NAME edge_rv_lite_axi_coremark
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/axi_coremark_obj/Vedge_rv_lite_axi_coremark_tb
          +mem64=${EDGE_COREMARK_MEM64})
set_tests_properties(edge_rv_lite_axi_coremark PROPERTIES
  REQUIRED_FILES "${EDGE_COREMARK_MEM64}" TIMEOUT 60)

add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/cached_coremark_obj/Vedge_rv_lite_cached_coremark_tb
  COMMAND ${VERILATOR} --binary --timing -Wno-fatal
          --top-module edge_rv_lite_cached_coremark_tb
          --Mdir ${CMAKE_CURRENT_BINARY_DIR}/cached_coremark_obj
          ${CACHED_CORE_RTL}
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_cached_coremark_tb.v
  DEPENDS ${CACHED_CORE_RTL}
          ${CMAKE_CURRENT_LIST_DIR}/tests/edge_rv_lite_cached_coremark_tb.v)
add_custom_target(edge_rv_lite_cached_coremark_vvp ALL
  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/cached_coremark_obj/Vedge_rv_lite_cached_coremark_tb)
add_test(NAME edge_rv_lite_cached_coremark
  COMMAND ${CMAKE_CURRENT_BINARY_DIR}/cached_coremark_obj/Vedge_rv_lite_cached_coremark_tb
          +mem64=${EDGE_COREMARK_MEM64})
set_tests_properties(edge_rv_lite_cached_coremark PROPERTIES
  REQUIRED_FILES "${EDGE_COREMARK_MEM64}" TIMEOUT 60)

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
