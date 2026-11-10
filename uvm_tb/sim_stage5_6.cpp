// =============================================================================
// File: uvm_tb/sim_stage5_6.cpp
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Cycle-Accurate Verilator C++ Testbench for Stage 5 (mlu_vfu_sfu_pipe)
//              and Stage 6 (mlu_mfu_dma_engine) verifying all 7 VFU/SFU ops
//              and all 6 MFU DMA modes.
// =============================================================================
#include "Vtb_stage5_6_vfu_mfu.h"
#include "verilated.h"
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>
#include <vector>

static void pack_inst128(
    VlWide<4>& out,
    uint8_t opcode,
    uint8_t engine,
    uint8_t prec,
    uint8_t sparse_mode,
    uint8_t src_space,
    uint8_t dst_space,
    uint8_t dep_mask,
    uint8_t tag_id,
    uint32_t dst_addr,
    uint32_t src0_addr,
    uint16_t src1_or_strd,
    uint16_t len_or_dims
) {
    uint32_t w3 = ((uint32_t)(opcode & 0x3F) << 26) |
                  ((uint32_t)(engine & 0x07) << 23) |
                  ((uint32_t)(prec & 0x07) << 20) |
                  ((uint32_t)(sparse_mode & 0x03) << 18) |
                  ((uint32_t)(src_space & 0x07) << 15) |
                  ((uint32_t)(dst_space & 0x07) << 12) |
                  ((uint32_t)(dep_mask & 0x0F) << 8) |
                  ((uint32_t)(tag_id & 0xFF));
    out[3] = w3;
    out[2] = dst_addr;
    out[1] = src0_addr;
    out[0] = ((uint32_t)src1_or_strd << 16) | (uint32_t)len_or_dims;
}

static void pack_vec8x16(VlWide<4>& out, const int16_t lanes[8]) {
    for (int w = 0; w < 4; w++) {
        uint16_t lo = (uint16_t)lanes[2 * w];
        uint16_t hi = (uint16_t)lanes[2 * w + 1];
        out[w] = ((uint32_t)hi << 16) | (uint32_t)lo;
    }
}

static void unpack_vec8x16(const VlWide<4>& in, int16_t lanes[8]) {
    for (int w = 0; w < 4; w++) {
        lanes[2 * w]     = (int16_t)(in[w] & 0xFFFFu);
        lanes[2 * w + 1] = (int16_t)((in[w] >> 16) & 0xFFFFu);
    }
}

static void tick(Vtb_stage5_6_vfu_mfu* dut) {
    dut->clk_i = 0;
    dut->eval();
    dut->clk_i = 1;
    dut->eval();
}

static void run_vfu_op(
    Vtb_stage5_6_vfu_mfu* dut,
    uint8_t opcode,
    uint8_t prec,
    uint8_t tag,
    uint16_t src1_flag,
    const int16_t va[8],
    const int16_t vb[8],
    const int16_t vlut[8],
    int16_t vout[8]
) {
    pack_inst128(dut->vfu_cmd_inst_i, opcode, 2 /*ENG_VFU_VEC*/, prec, 0, 0, 0, 0, tag, 0, 0, src1_flag, 8);
    pack_vec8x16(dut->vfu_vec_a_i, va);
    pack_vec8x16(dut->vfu_vec_b_i, vb);
    pack_vec8x16(dut->vfu_cos_sin_lut_i, vlut);
    dut->vfu_cmd_valid_i = 1;
    tick(dut);
    dut->vfu_cmd_valid_i = 0;
    int guard = 0;
    while (!dut->vfu_done_valid_o && guard < 20) {
        tick(dut);
        guard++;
    }
    assert(dut->vfu_done_valid_o == 1);
    assert(dut->vfu_vec_out_valid_o == 1);
    assert(dut->vfu_done_tag_o == tag);
    unpack_vec8x16(dut->vfu_vec_out_o, vout);
    tick(dut);
}

struct DmaBeatRecord {
    uint8_t  rd_space;
    uint32_t rd_addr;
    uint8_t  wr_space;
    uint32_t wr_addr;
    uint64_t wr_data;
    bool     transpose_en;
};

static std::vector<DmaBeatRecord> run_mfu_dma(
    Vtb_stage5_6_vfu_mfu* dut,
    uint8_t opcode,
    uint8_t src_space,
    uint8_t dst_space,
    uint8_t tag,
    uint32_t dst_addr,
    uint32_t src0_addr,
    uint16_t src1_or_strd,
    uint16_t len_or_dims,
    uint64_t idx_offset,
    const std::vector<uint8_t>& bitmaps,
    std::map<uint32_t, uint64_t>& src_mem,
    std::map<uint32_t, uint64_t>& dst_mem
) {
    std::vector<DmaBeatRecord> trace;
    pack_inst128(dut->mfu_cmd_inst_i, opcode, 3 /*ENG_MFU_DMA*/, 1, 0,
                 src_space, dst_space, 0, tag, dst_addr, src0_addr, src1_or_strd, len_or_dims);
    dut->mfu_idx_offset_i    = idx_offset;
    dut->mfu_decomp_bitmap_i = bitmaps.empty() ? 0xFF : bitmaps[0];
    dut->mfu_rd_resp_valid_i = 0;
    dut->mfu_rd_resp_data_i  = 0;
    dut->mfu_cmd_valid_i     = 1;
    tick(dut);
    dut->mfu_cmd_valid_i     = 0;

    uint32_t last_rd_addr = 0;
    uint8_t  last_rd_space = 0;
    size_t   bmp_idx = 0;
    int      guard = 0;

    while (guard < 200) {
        if (dut->mfu_rd_req_valid_o) {
            last_rd_addr  = dut->mfu_rd_req_addr_o;
            last_rd_space = dut->mfu_rd_req_space_o;
            dut->mfu_rd_resp_valid_i = 1;
            dut->mfu_rd_resp_data_i  = src_mem.count(last_rd_addr) ? src_mem[last_rd_addr]
                                                                   : (0xA000000000000000ULL | last_rd_addr);
            if (!bitmaps.empty()) {
                dut->mfu_decomp_bitmap_i = bitmaps[bmp_idx % bitmaps.size()];
                bmp_idx++;
            }
        } else {
            dut->mfu_rd_resp_valid_i = 0;
        }

        tick(dut);
        guard++;

        if (dut->mfu_wr_req_valid_o) {
            DmaBeatRecord rec;
            rec.rd_space     = last_rd_space;
            rec.rd_addr      = last_rd_addr;
            rec.wr_space     = dut->mfu_wr_req_space_o;
            rec.wr_addr      = dut->mfu_wr_req_addr_o;
            rec.wr_data      = dut->mfu_wr_req_data_o;
            rec.transpose_en = dut->mfu_nram_transpose_mode_o != 0;
            dst_mem[rec.wr_addr] = rec.wr_data;
            trace.push_back(rec);
        }

        if (dut->mfu_done_valid_o) {
            assert(dut->mfu_done_tag_o == tag);
            break;
        }
    }
    assert(guard < 200);
    dut->mfu_rd_resp_valid_i = 0;
    tick(dut);
    return trace;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_stage5_6_vfu_mfu* dut = new Vtb_stage5_6_vfu_mfu();

    dut->rst_ni              = 0;
    dut->vfu_cmd_valid_i     = 0;
    dut->mfu_cmd_valid_i     = 0;
    dut->mfu_rd_resp_valid_i = 0;
    for (int i = 0; i < 4; i++) tick(dut);
    dut->rst_ni = 1;
    tick(dut);

    int16_t va[8], vb[8], vlut[8], vout[8];
    memset(vlut, 0, sizeof(vlut));

    // 1. OP_BANG_VADD (0x20): 8-lane saturating vector addition
    for (int i = 0; i < 8; i++) { va[i] = (i == 7) ? 30000 : (i * 100 - 300); vb[i] = (i == 7) ? 10000 : (i * 50 + 100); }
    run_vfu_op(dut, 0x20, 4, 0x11, 0, va, vb, vlut, vout);
    for (int i = 0; i < 7; i++) assert(vout[i] == va[i] + vb[i]);
    assert(vout[7] == 32767); // Saturated
    printf("[PASS] Stage 5 OP_BANG_VADD: lane0=%d lane7_sat=%d\n", vout[0], vout[7]);

    // 2. OP_BANG_VMUL (0x21): 8-lane Q8.8 fixed-point multiplication
    for (int i = 0; i < 8; i++) { va[i] = (i + 1) * 128; vb[i] = 512; } // (0.5*(i+1)) * 2.0 = (i+1) in Q8.8
    run_vfu_op(dut, 0x21, 4, 0x12, 0, va, vb, vlut, vout);
    for (int i = 0; i < 8; i++) assert(vout[i] == (i + 1) * 256);
    printf("[PASS] Stage 5 OP_BANG_VMUL: lane0=%d lane7=%d\n", vout[0], vout[7]);

    // 3. OP_BANG_SOFTMAX (0x22): FlashAttention Online Safe Softmax (single + continuation)
    for (int i = 0; i < 8; i++) va[i] = (i < 4) ? 256 : 0; // 4 lanes at 1.0, 4 lanes at 0.0
    run_vfu_op(dut, 0x22, 4, 0x13, 0, va, vb, vlut, vout);
    int sum_p = 0;
    for (int i = 0; i < 8; i++) sum_p += vout[i];
    assert((int16_t)dut->vfu_softmax_max_o == 256);
    assert(vout[0] > vout[4] && sum_p >= 248 && sum_p <= 260);
    uint32_t sum_tile0 = dut->vfu_softmax_sum_o;
    // Online continuation tile (src1_flag=1) with higher max = 512 (2.0 in Q8.8)
    for (int i = 0; i < 8; i++) va[i] = 512;
    run_vfu_op(dut, 0x22, 4, 0x14, 1, va, vb, vlut, vout);
    assert((int16_t)dut->vfu_softmax_max_o == 512);
    assert(dut->vfu_softmax_sum_o > 8 * 256);
    printf("[PASS] Stage 5 OP_BANG_SOFTMAX: max=%d sum_tile0=%u sum_cont=%u p0=%d\n",
           (int16_t)dut->vfu_softmax_max_o, sum_tile0, dut->vfu_softmax_sum_o, vout[0]);

    // 4. OP_BANG_ROPE (0x23): Rotary Position Embedding 90-deg & 0-deg complex rotation
    for (int k = 0; k < 4; k++) {
        va[2*k] = 256; va[2*k+1] = 128;
        vlut[2*k] = (k % 2 == 0) ? 0 : 256;   // cos(90)=0, cos(0)=1.0
        vlut[2*k+1] = (k % 2 == 0) ? 256 : 0; // sin(90)=1.0, sin(0)=0
    }
    run_vfu_op(dut, 0x23, 4, 0x15, 0, va, vb, vlut, vout);
    assert(vout[0] == -128 && vout[1] == 256);
    assert(vout[2] == 256  && vout[3] == 128);
    printf("[PASS] Stage 5 OP_BANG_ROPE: pair0=(%d,%d) pair1=(%d,%d)\n", vout[0], vout[1], vout[2], vout[3]);

    // 5. OP_BANG_RMSNORM (0x24): RMS LayerNorm (x_i = +/-1.0 -> rms=1.0 -> rsqrt=1.0)
    for (int i = 0; i < 8; i++) { va[i] = (i % 2 == 0) ? 256 : -256; vb[i] = 512; } // gamma = 2.0
    run_vfu_op(dut, 0x24, 4, 0x16, 0, va, vb, vlut, vout);
    assert(std::abs(vout[0] - 512) <= 8 && std::abs(vout[1] + 512) <= 8);
    printf("[PASS] Stage 5 OP_BANG_RMSNORM: out0=%d out1=%d\n", vout[0], vout[1]);

    // 6. OP_BANG_SWIGLU (0x25): Fused SiLU(gate) * up
    for (int i = 0; i < 8; i++) { va[i] = (i - 3) * 256; vb[i] = 256; }
    run_vfu_op(dut, 0x25, 4, 0x17, 0, va, vb, vlut, vout);
    assert(vout[3] == 0 && vout[4] > 180 && vout[4] < 200); // g=0 -> 0; g=1.0 -> ~0.731*256 = 188
    printf("[PASS] Stage 5 OP_BANG_SWIGLU: g0_out=%d g1_out=%d\n", vout[3], vout[4]);

    // 7. OP_BANG_QUANT_STAT (0x26): Cambricon-Q Dynamic Statistical Quantizer
    int16_t q_in[8] = {-1270, -635, 0, 254, 508, 762, 1016, 1270};
    run_vfu_op(dut, 0x26, 1 /*PREC_INT8*/, 0x18, 0, q_in, vb, vlut, vout);
    assert(dut->vfu_absmax_o == 1270);
    assert((int16_t)dut->vfu_min_val_o == -1270 && (int16_t)dut->vfu_max_val_o == 1270);
    assert(dut->vfu_dyn_scale_o == 10 && vout[0] == -127 && vout[7] == 127);
    printf("[PASS] Stage 5 OP_BANG_QUANT_STAT: absmax=%u scale=%u q_min=%d q_max=%d\n",
           dut->vfu_absmax_o, dut->vfu_dyn_scale_o, vout[0], vout[7]);

    // Stage 6: MFU DMA Engine Verification (All 6 Modes)
    std::map<uint32_t, uint64_t> src_mem, dst_mem;
    for (uint32_t a = 0; a < 0x400; a += 8) src_mem[0x1000 + a] = 0x1122334400000000ULL | a;

    // 6.1 OP_BANG_MEMCPY_1D (0x30)
    auto tr1d = run_mfu_dma(dut, 0x30, 4 /*GDRAM*/, 0 /*NRAM*/, 0x21, 0x2000, 0x1000, 0, 4, 0, {}, src_mem, dst_mem);
    assert(tr1d.size() == 4 && dst_mem[0x2018] == src_mem[0x1018]);
    printf("[PASS] Stage 6 OP_BANG_MEMCPY_1D: beats=%zu dst[0x2018]=0x%llx\n", tr1d.size(), (unsigned long long)dst_mem[0x2018]);

    // 6.2 OP_BANG_MEMCPY_2D (0x31): 2 rows x 2 cols, src_stride=4, dst_stride=3
    auto tr2d = run_mfu_dma(dut, 0x31, 2 /*SRAM*/, 0 /*NRAM*/, 0x22, 0x3000, 0x1000, (4 << 8) | 3, (2 << 8) | 2, 0, {}, src_mem, dst_mem);
    assert(tr2d.size() == 4 && tr2d[2].rd_addr == 0x1020 && tr2d[2].wr_addr == 0x3018);
    printf("[PASS] Stage 6 OP_BANG_MEMCPY_2D: row1_rd=0x%x row1_wr=0x%x\n", tr2d[2].rd_addr, tr2d[2].wr_addr);

    // 6.3 OP_BANG_GATHER (0x32) & 6.4 OP_BANG_SCATTER (0x33)
    uint64_t idx_vec = ((uint64_t)0x0060 << 48) | ((uint64_t)0x0018 << 32) | ((uint64_t)0x0040 << 16) | 0x0008ULL;
    auto trg = run_mfu_dma(dut, 0x32, 4, 0, 0x23, 0x4000, 0x1000, 0, 4, idx_vec, {}, src_mem, dst_mem);
    assert(trg.size() == 4 && trg[0].rd_addr == 0x1008 && trg[2].rd_addr == 0x1018 && trg[3].rd_addr == 0x1060);
    auto trs = run_mfu_dma(dut, 0x33, 0, 2, 0x24, 0x5000, 0x1000, 0, 4, idx_vec, {}, src_mem, dst_mem);
    assert(trs.size() == 4 && trs[0].wr_addr == 0x5008 && trs[2].wr_addr == 0x5018 && trs[3].wr_addr == 0x5060);
    printf("[PASS] Stage 6 OP_BANG_GATHER & OP_BANG_SCATTER: gather[3]=0x%x scatter[3]=0x%x\n", trg[3].rd_addr, trs[3].wr_addr);

    // 6.5 OP_BANG_DECOMP_DMA (0x34): Hardware Zero-Bitmap Decompression
    src_mem[0x1200] = 0x00000000DDCCBBAAULL; // 4 non-zero bytes
    src_mem[0x1208] = 0x0000000044332211ULL; // 4 non-zero bytes
    auto trd = run_mfu_dma(dut, 0x34, 4, 1 /*WRAM*/, 0x25, 0x6000, 0x1200, 0, 2, 0, {0xA5, 0xC3}, src_mem, dst_mem);
    assert(trd.size() == 2 && trd[0].wr_data == 0xDD00CC0000BB00AAULL && trd[1].wr_data == 0x4433000000002211ULL);
    assert(dut->mfu_compressed_bytes_rd_o == 8 && dut->mfu_uncompressed_bytes_wr_o == 16);
    printf("[PASS] Stage 6 OP_BANG_DECOMP_DMA: word0=0x%016llx comp_rd=%u uncomp_wr=%u\n",
           (unsigned long long)trd[0].wr_data, dut->mfu_compressed_bytes_rd_o, dut->mfu_uncompressed_bytes_wr_o);

    // 6.6 OP_BANG_TRANSPOSE (0x35): 8-beat NRAM on-the-fly transpose
    auto trt = run_mfu_dma(dut, 0x35, 0, 0, 0x26, 0x7000, 0x1000, 0, 8, 0, {}, src_mem, dst_mem);
    assert(trt.size() == 8 && trt[1].transpose_en && trt[1].wr_addr == 0x7000 + (1u << 16));
    printf("[PASS] Stage 6 OP_BANG_TRANSPOSE: beats=%zu transpose_mode=%d\n", trt.size(), trt[1].transpose_en);

    printf("=== ALL STAGE 5 (7 VFU/SFU OPS) & STAGE 6 (6 MFU DMA MODES) TESTS PASSED ===\n");
    delete dut;
    return 0;
}
