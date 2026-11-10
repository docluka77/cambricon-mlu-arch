#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

YOSYS=/usr/local/bin/yosys
LIB_ASAP7=/nfs/share/home/chenpei/hyr/latentcore_mla_dsa_20261103/synth/asap7_rvt_ff.lib
LIB_SKY130=/nfs/share/home/chenpei/hyr/dac2027_llm_dsa_marathon/synth/lib/sky130_fd_sc_hd__tt_025C_1v80.lib

synth_asap7() {
    local mod=$1
    local files=$2
    local synth_flags=${3:-""}
    if [ -s "synth/${mod}_asap7_netlist.v" ] && grep -q "End of script" "synth/synth_${mod}_asap7.log" 2>/dev/null; then
        echo "=== [ASAP7 7nm] Skipping ${mod} (already done) ==="
        return 0
    fi
    echo "=== [ASAP7 7nm] Synthesizing ${mod} ==="
    $YOSYS -p "
        read_verilog -sv -DSYNTH_SRAM_DEPTH=8 -Irtl -Isram_ip ${files};
        chformal -remove;
        synth -top ${mod} ${synth_flags} -noabc;
        dfflibmap -liberty ${LIB_ASAP7};
        abc -fast -liberty ${LIB_ASAP7};
        stat -liberty ${LIB_ASAP7};
        write_verilog -noattr synth/${mod}_asap7_netlist.v
    " > synth/synth_${mod}_asap7.log 2>&1
    echo "=== [ASAP7 7nm] Finished ${mod} ==="
}

synth_sky130() {
    local mod=$1
    local files=$2
    local synth_flags=${3:-""}
    if [ -s "synth/${mod}_sky130_netlist.v" ] && grep -q "End of script" "synth/synth_${mod}_sky130.log" 2>/dev/null; then
        echo "=== [Sky130 130nm] Skipping ${mod} (already done) ==="
        return 0
    fi
    echo "=== [Sky130 130nm] Synthesizing ${mod} ==="
    $YOSYS -p "
        read_verilog -sv -DSYNTH_SRAM_DEPTH=8 -Irtl -Isram_ip ${files};
        chformal -remove;
        synth -top ${mod} ${synth_flags} -noabc;
        dfflibmap -liberty ${LIB_SKY130};
        abc -fast -liberty ${LIB_SKY130};
        stat -liberty ${LIB_SKY130};
        write_verilog -noattr synth/${mod}_sky130_netlist.v
    " > synth/synth_${mod}_sky130.log 2>&1
    echo "=== [Sky130 130nm] Finished ${mod} ==="
}

# Batch 1: SRAM & Memory + Compute/Control/Interconnect Leaf Modules (in parallel)
synth_asap7  mlu_sram_secded_ecc        "sram_ip/mlu_sram_secded_ecc.sv" &
synth_sky130 mlu_sram_secded_ecc        "sram_ip/mlu_sram_secded_ecc.sv" &
synth_asap7  mlu_sram_sp_macro          "sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv" &
synth_sky130 mlu_sram_sp_macro          "sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv" &
synth_asap7  mlu_nram_banked_scratchpad "sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_nram_banked_scratchpad.sv" "-noshare" &
synth_sky130 mlu_nram_banked_scratchpad "sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_nram_banked_scratchpad.sv" "-noshare" &
synth_asap7  mlu_wram_weight_buffer     "sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_wram_weight_buffer.sv" "-noshare" &
synth_sky130 mlu_wram_weight_buffer     "sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_wram_weight_buffer.sv" "-noshare" &
synth_asap7  mlu_mpu_shared_sram        "sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_mpu_shared_sram.sv" "-noshare" &
synth_sky130 mlu_mpu_shared_sram        "sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_mpu_shared_sram.sv" "-noshare" &

synth_asap7  mlu_bang_icu               "rtl/mlu_bang_icu.sv" &
synth_sky130 mlu_bang_icu               "rtl/mlu_bang_icu.sv" &
synth_asap7  mlu_pmu_clock_gate         "rtl/mlu_pmu_clock_gate.sv" &
synth_sky130 mlu_pmu_clock_gate         "rtl/mlu_pmu_clock_gate.sv" &
synth_asap7  mlu_tfu_fractal_mac        "rtl/mlu_tfu_fractal_mac.sv" &
synth_sky130 mlu_tfu_fractal_mac        "rtl/mlu_tfu_fractal_mac.sv" &
synth_asap7  mlu_vfu_sfu_pipe           "rtl/mlu_vfu_sfu_pipe.sv" &
synth_sky130 mlu_vfu_sfu_pipe           "rtl/mlu_vfu_sfu_pipe.sv" &
synth_asap7  mlu_mfu_dma_engine         "rtl/mlu_mfu_dma_engine.sv" &
synth_sky130 mlu_mfu_dma_engine         "rtl/mlu_mfu_dma_engine.sv" &
synth_asap7  mlu_link_noc_router        "rtl/mlu_link_noc_router.sv" &
synth_sky130 mlu_link_noc_router        "rtl/mlu_link_noc_router.sv" &
synth_asap7  mlu_c2c_serdes_pcs         "rtl/mlu_c2c_serdes_pcs.sv" &
synth_sky130 mlu_c2c_serdes_pcs         "rtl/mlu_c2c_serdes_pcs.sv" &
wait
echo "=== BATCH 1 (Modules 1-12) COMPLETE ==="

# Batch 2: Core, Cluster & Full-Chip Hierarchy Modules (in parallel)
IPU_FILES="sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_nram_banked_scratchpad.sv rtl/mlu_wram_weight_buffer.sv rtl/mlu_bang_icu.sv rtl/mlu_pmu_clock_gate.sv rtl/mlu_tfu_fractal_mac.sv rtl/mlu_vfu_sfu_pipe.sv rtl/mlu_mfu_dma_engine.sv rtl/mlu_cambricon_llm_flash_kv.sv rtl/mlu_ipu_core.sv"
MPU_FILES="sram_ip/mlu_sram_secded_ecc.sv sram_ip/mlu_sram_sp_macro.sv rtl/mlu_mpu_shared_sram.sv rtl/mlu_mpu_core.sv"
CLUSTER_FILES="${IPU_FILES} rtl/mlu_mpu_shared_sram.sv rtl/mlu_mpu_core.sv rtl/mlu_mtp_cluster.sv"
TOP_FILES="${CLUSTER_FILES} rtl/mlu_link_noc_router.sv rtl/mlu_c2c_serdes_pcs.sv rtl/mlu_chip_top.sv"

synth_asap7  mlu_ipu_core              "${IPU_FILES}" "-noshare" &
synth_sky130 mlu_ipu_core              "${IPU_FILES}" "-noshare" &
synth_asap7  mlu_mpu_core              "${MPU_FILES}" "-noshare" &
synth_sky130 mlu_mpu_core              "${MPU_FILES}" "-noshare" &
synth_asap7  mlu_mtp_cluster           "${CLUSTER_FILES}" "-noshare" &
synth_asap7  mlu_chip_top              "${TOP_FILES}" "-noshare" &
wait

echo "ALL_16_MODULES_SYNTH_DONE"
