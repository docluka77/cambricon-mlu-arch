#!/usr/bin/env bash
set -euo pipefail
cd /nfs/share/home/chenpei/hyr/cambricon_mlu590_690_marathon

YOSYS=/usr/local/bin/yosys
LIB_ASAP7=/nfs/share/home/chenpei/hyr/latentcore_mla_dsa_20261103/synth/asap7_rvt_ff.lib
LIB_SKY130=/nfs/share/home/chenpei/hyr/dac2027_llm_dsa_marathon/synth/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

synth_leaf() {
    local pdk=$1
    local lib=$2
    local mod=$3
    local files=$4
    local flags=${5:-"-noshare"}
    echo "=== [${pdk}] Synthesizing ${mod} ==="
    $YOSYS -p "
        read_verilog -sv -DSYNTH_SRAM_DEPTH=8 -Irtl -Isram_ip ${files};
        chformal -remove;
        synth -top ${mod} ${flags} -noabc;
        dfflibmap -liberty ${lib};
        abc -fast -liberty ${lib};
        stat -top ${mod} -liberty ${lib};
        write_verilog -noattr synth/${mod}_${pdk}_netlist.v
    " > synth/synth_${mod}_${pdk}.log 2>&1
    echo "=== [${pdk}] Finished ${mod} ==="
}

synth_hier_fast() {
    local pdk=$1
    local lib=$2
    local mod=$3
    local files=$4
    echo "=== [${pdk}] Synthesizing hierarchical ${mod} ==="
    $YOSYS -p "
        read_liberty -lib ${lib};
        read_verilog -sv -DSYNTH_SRAM_DEPTH=8 -Irtl -Isram_ip ${files};
        blackbox mlu_tfu_fractal_mac mlu_vfu_sfu_pipe;
        chformal -remove;
        synth -top ${mod} -noshare -noabc;
        dfflibmap -liberty ${lib};
        abc -fast -liberty ${lib};
        delete mlu_tfu_fractal_mac mlu_vfu_sfu_pipe;
        read_verilog synth/mlu_tfu_fractal_mac_${pdk}_netlist.v synth/mlu_vfu_sfu_pipe_${pdk}_netlist.v;
        stat -top ${mod} -liberty ${lib};
        write_verilog -noattr synth/${mod}_${pdk}_netlist.v
    " > synth/synth_${mod}_${pdk}.log 2>&1
    echo "=== [${pdk}] Finished hierarchical ${mod} ==="
}

MPU_FILES="sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_mpu_shared_sram.sv rtl/mlu_mpu_core.sv"
OAM_FILES="rtl/mlu_pkg.sv rtl/mlu_link_noc_router.sv rtl/mlu_c2c_serdes_pcs.sv rtl/mlu_4chip_oam_node.sv"
IPU_FILES="sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_nram_banked_scratchpad.sv rtl/mlu_wram_weight_buffer.sv rtl/mlu_bang_icu.sv rtl/mlu_pmu_clock_gate.sv rtl/mlu_tfu_fractal_mac.sv rtl/mlu_vfu_sfu_pipe.sv rtl/mlu_mfu_dma_engine.sv rtl/mlu_cambricon_llm_flash_kv.sv rtl/mlu_ipu_core.sv"
CLUSTER_FILES="${IPU_FILES} rtl/mlu_mpu_shared_sram.sv rtl/mlu_mpu_core.sv rtl/mlu_mtp_cluster.sv"
TOP_FILES="${CLUSTER_FILES} rtl/mlu_link_noc_router.sv rtl/mlu_c2c_serdes_pcs.sv rtl/mlu_chip_top.sv"

synth_leaf asap7  "${LIB_ASAP7}"  mlu_mpu_core        "${MPU_FILES}" "-noshare" &
synth_leaf sky130 "${LIB_SKY130}" mlu_mpu_core        "${MPU_FILES}" "-noshare" &
synth_leaf asap7  "${LIB_ASAP7}"  mlu_link_noc_router "rtl/mlu_link_noc_router.sv" "" &
synth_leaf sky130 "${LIB_SKY130}" mlu_link_noc_router "rtl/mlu_link_noc_router.sv" "" &
synth_leaf asap7  "${LIB_ASAP7}"  mlu_4chip_oam_node  "${OAM_FILES}" "-noshare" &
synth_leaf sky130 "${LIB_SKY130}" mlu_4chip_oam_node  "${OAM_FILES}" "-noshare" &

synth_hier_fast sky130 "${LIB_SKY130}" mlu_ipu_core    "${IPU_FILES}" &
synth_hier_fast asap7  "${LIB_ASAP7}"  mlu_mtp_cluster "${CLUSTER_FILES}" &
synth_hier_fast sky130 "${LIB_SKY130}" mlu_mtp_cluster "${CLUSTER_FILES}" &
synth_hier_fast asap7  "${LIB_ASAP7}"  mlu_chip_top    "${TOP_FILES}" &
synth_hier_fast sky130 "${LIB_SKY130}" mlu_chip_top    "${TOP_FILES}" &

wait
echo "ALL_REFRESH_36_DONE"
