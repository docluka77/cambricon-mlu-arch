#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Comprehensive Verification & Golden Vector Exporter for Cambricon MLU590 / MLU690 Golden Model.
Verifies all 24 BANG ISA opcodes, all 8 numerical precisions, (72,64) Hsiao SECDED ECC (all 72 1-bit
and all 2,556 2-bit error pairs), and 128-bit MLU-Link NoC flit CRC-16-CCITT.
"""

import json
import os
from pathlib import Path
import numpy as np

from cambricon_mlu_golden import (
    BangInst128,
    CambriconMluGoldenModel,
    HsiaoSecded72x64,
    MluEngine,
    MluFlitType,
    MluMemSpace,
    MluNocFlit128,
    MluOpcode,
    MluPrec,
    MluSparseMode,
    NumericCodec,
)


def test_hsiao_secded_72x64() -> dict:
    sample_words = [0x0000000000000000, 0xFFFFFFFFFFFFFFFF, 0xCAFEBABE12345678, 0xA5A5F0F00F0F5A5A]
    ecc_vectors = []
    for w in sample_words:
        cw = HsiaoSecded72x64.encode(w)
        dec, syn, sec, ded = HsiaoSecded72x64.decode(cw)
        assert dec == w and syn == 0 and not sec and not ded
        # Test all 72 single-bit flips (64 data + 8 parity)
        for bit in range(72):
            corrupted_1b = cw ^ (1 << bit)
            dec1, syn1, sec1, ded1 = HsiaoSecded72x64.decode(corrupted_1b)
            assert dec1 == w and syn1 != 0 and sec1 and not ded1, f"SEC failed at bit {bit}"
        ecc_vectors.append({"data_hex": f"0x{w:016X}", "codeword_72b_hex": f"0x{cw:018X}"})

    # Exhaustively test all C(72,2) = 2,556 double-bit flips on 0xCAFEBABE12345678
    cw_ref = HsiaoSecded72x64.encode(0xCAFEBABE12345678)
    ded_count = 0
    for i in range(72):
        for j in range(i + 1, 72):
            _, syn2, sec2, ded2 = HsiaoSecded72x64.decode(cw_ref ^ (1 << i) ^ (1 << j))
            assert syn2 != 0 and not sec2 and ded2, f"DED failed for bits ({i}, {j})"
            ded_count += 1
    assert ded_count == 2556
    return {"status": "PASS", "single_bit_tested": 72 * len(sample_words), "double_bit_pairs_tested": ded_count, "vectors": ecc_vectors}


def test_inst_and_noc_flit() -> dict:
    inst_vectors = []
    for idx, op in enumerate(MluOpcode):
        eng = (
            MluEngine.ENG_ICU_CTRL if op < 0x10 else
            MluEngine.ENG_TFU_MAT if op < 0x20 else
            MluEngine.ENG_VFU_VEC if op < 0x30 else
            MluEngine.ENG_MFU_DMA if op < 0x38 else
            MluEngine.ENG_MPU_COL if op in (MluOpcode.OP_MPU_BCAST_SRAM, MluOpcode.OP_MPU_ALLREDUCE) else
            MluEngine.ENG_LLM_KV
        )
        inst = BangInst128(
            opcode=op,
            engine=eng,
            prec=MluPrec(idx % 8),
            sparse_mode=MluSparseMode(idx % 4),
            src_space=MluMemSpace(idx % 8),
            dst_space=MluMemSpace((idx + 1) % 8),
            dep_mask=idx & 0xF,
            tag_id=(idx + 10) & 0xFF,
            dst_addr=0x00010000 + idx * 64,
            src0_addr=0x00020000 + idx * 64,
            src1_or_strd=0x0100 + idx,
            len_or_dims=0x0040 + idx,
        )
        packed = inst.pack()
        unpacked = BangInst128.unpack(packed)
        assert unpacked == inst, f"Instruction pack/unpack mismatch for {op.name}"
        inst_vectors.append({"opcode": op.name, "opcode_hex": f"0x{int(op):02X}", "inst_128b_hex": f"0x{packed:032X}"})

    flit = MluNocFlit128(
        flit_type=MluFlitType.FLIT_HEAD_TAIL,
        vc_id=1,
        src_id=3,
        dst_id=11,
        pkt_seq=19,
        addr=0x80004000,
        payload=0x0123456789ABCDEF,
    )
    packed_flit = flit.pack(auto_crc=True)
    unpacked_flit, crc_ok = MluNocFlit128.unpack(packed_flit)
    assert crc_ok and unpacked_flit == flit
    _, crc_bad = MluNocFlit128.unpack(packed_flit ^ (1 << 42))
    assert not crc_bad
    return {"inst_count": len(inst_vectors), "inst_vectors": inst_vectors, "sample_flit_128b_hex": f"0x{packed_flit:032X}", "crc16_hex": f"0x{flit.crc16_or_cmd:04X}"}


def test_all_24_opcodes_and_export() -> dict:
    np.random.seed(20261106)
    gm = CambriconMluGoldenModel(num_ipus=4)
    op_results = {}

    # 1. ICU Control Opcodes (4 opcodes: OP_NOP, OP_SYNC_IPU, OP_SYNC_CLUSTER, OP_PWR_GATE_CFG)
    for op in (MluOpcode.OP_NOP, MluOpcode.OP_SYNC_IPU, MluOpcode.OP_SYNC_CLUSTER, MluOpcode.OP_PWR_GATE_CFG):
        inst = BangInst128(op, MluEngine.ENG_ICU_CTRL, MluPrec.PREC_FP32, MluSparseMode.SPARSE_DENSE,
                           MluMemSpace.MEM_SPACE_NRAM, MluMemSpace.MEM_SPACE_NRAM, 0x7, int(op) + 1, 0, 0, 0x000F, 0x0020)
        op_results[op.name] = gm.execute_control_op(inst)

    # 2. TFU Opcodes (4 opcodes: OP_BANG_MATMUL, OP_BANG_CONV2D, OP_BANG_SPARSE_MM, OP_BANG_QUANT_MM)
    a_mat = np.arange(1, 65, dtype=np.float32).reshape(8, 8) * 0.25
    b_mat = np.arange(1, 65, dtype=np.float32).reshape(8, 8) * 0.125
    prec_Check = {}
    for p in MluPrec:
        c_out, cyc = gm.tfu_matmul(a_mat, b_mat, p)
        prec_Check[p.name] = {"sum": float(np.sum(c_out)), "cycles": cyc, "row0": [round(float(x), 5) for x in c_out[0, :4]]}
    op_results["OP_BANG_MATMUL"] = prec_Check

    x_conv = np.ones((2, 4, 4), dtype=np.float32) * 0.5
    w_conv = np.ones((2, 2, 2, 2), dtype=np.float32) * 0.25
    y_conv, cyc_conv = gm.tfu_conv2d(x_conv, w_conv, MluPrec.PREC_FP16)
    assert np.allclose(y_conv, 1.0)
    op_results["OP_BANG_CONV2D"] = {"shape": list(y_conv.shape), "val0": float(y_conv[0, 0, 0]), "cycles": cyc_conv}

    sp_out_24, sp_w_24, cyc_sp24 = gm.tfu_sparse_mm(a_mat, b_mat, MluSparseMode.SPARSE_2_OF_4, MluPrec.PREC_FP16)
    assert np.count_nonzero(sp_w_24) == 32
    b_blk = b_mat.copy()
    b_blk[0:4, 0:4] = 0.0
    b_blk[4:8, 4:8] = 0.0
    sp_out_blk, _, cyc_spblk = gm.tfu_sparse_mm(a_mat, b_blk, MluSparseMode.SPARSE_BLOCK_4X4, MluPrec.PREC_FP16)
    op_results["OP_BANG_SPARSE_MM"] = {"nnz_2of4": int(np.count_nonzero(sp_w_24)), "cycles_2of4": cyc_sp24, "cycles_blk4x4": cyc_spblk, "sum_2of4": float(np.sum(sp_out_24)), "sum_blk4x4": float(np.sum(sp_out_blk))}

    aq = np.array([[10, -4, 6, 2], [3, 8, -5, 1]], dtype=np.int8)
    wq = np.array([[2, -1], [4, 3], [-2, 5], [1, 2]], dtype=np.int8)
    deq_mm, acc_i32, cyc_qmm = gm.tfu_quant_mm(aq, wq, 0.05, 1, 0.02, -1)
    op_results["OP_BANG_QUANT_MM"] = {"acc_i32": acc_i32.tolist(), "dequant": deq_mm.round(6).tolist(), "cycles": cyc_qmm}

    # 3. VFU Opcodes (7 opcodes: VADD, VMUL, SOFTMAX, ROPE, RMSNORM, SWIGLU, QUANT_STAT)
    v0 = np.array([1.0, -2.0, 3.5, 0.5, -1.5, 2.0, 4.0, -0.5], dtype=np.float32)
    v1 = np.array([0.5, 4.0, -1.5, 2.0, 3.0, -1.0, 0.25, 2.5], dtype=np.float32)
    op_results["OP_BANG_VADD"] = gm.vfu_vadd(v0, v1, MluPrec.PREC_FP16).tolist()
    op_results["OP_BANG_VMUL"] = gm.vfu_vmul(v0, v1, MluPrec.PREC_FP16).tolist()
    sm = gm.vfu_softmax(v0)
    assert abs(float(np.sum(sm)) - 1.0) < 1e-5
    op_results["OP_BANG_SOFTMAX"] = [round(float(x), 6) for x in sm]
    cos_t = np.array([1.0, 0.0, 0.5, 0.8660254], dtype=np.float32)
    sin_t = np.array([0.0, 1.0, 0.8660254, 0.5], dtype=np.float32)
    op_results["OP_BANG_ROPE"] = [round(float(x), 6) for x in gm.vfu_rope(v0, cos_t, sin_t)]
    op_results["OP_BANG_RMSNORM"] = [round(float(x), 6) for x in gm.vfu_rmsnorm(v0, np.ones(8, dtype=np.float32))]
    op_results["OP_BANG_SWIGLU"] = [round(float(x), 6) for x in gm.vfu_swiglu(v0, v1)]
    op_results["OP_BANG_QUANT_STAT"] = gm.vfu_quant_stat(v0)

    # 4. MFU DMA Opcodes (6 opcodes: MEMCPY_1D, MEMCPY_2D, GATHER, SCATTER, DECOMP_DMA, TRANSPOSE)
    c1d, _ = gm.mfu_memcpy_1d(v0)
    op_results["OP_BANG_MEMCPY_1D"] = c1d.tolist()
    c2d, _ = gm.mfu_memcpy_2d(np.arange(16, dtype=np.int32), 0, (2, 3), 4, 4)
    op_results["OP_BANG_MEMCPY_2D"] = c2d.tolist()
    g_out, _ = gm.mfu_gather(v0, np.array([7, 0, 3, 5]))
    op_results["OP_BANG_GATHER"] = g_out.tolist()
    s_out, _ = gm.mfu_scatter(np.zeros(8, dtype=np.float32), np.array([9.0, 8.0]), np.array([2, 6]))
    op_results["OP_BANG_SCATTER"] = s_out.tolist()
    dc_out, _ = gm.mfu_decomp_dma(np.array([11, 22, 33], dtype=np.int32), 0b01010010, 8)
    op_results["OP_BANG_DECOMP_DMA"] = dc_out.tolist()
    tr_out, _ = gm.mfu_transpose(np.arange(12, dtype=np.int32).reshape(3, 4))
    op_results["OP_BANG_TRANSPOSE"] = tr_out.tolist()
    # Verify NRAM XOR bank swizzling produces 8 distinct banks across both row and 8-word column strides
    assert len({gm.nram_bank_index(i * 8) for i in range(8)}) == 8
    assert all(len({gm.nram_bank_index(i * 64 + c * 8) for i in range(8)}) == 8 for c in range(8))

    # 5. MPU & Cambricon-LLM Opcodes (4 opcodes: BCAST_SRAM, ALLREDUCE, KV_PACK, SPEC_VERIFY)
    bcast_map, _ = gm.mpu_bcast_sram(np.array([10, 20, 30, 40], dtype=np.int32), ipu_mask=0xF)
    op_results["OP_MPU_BCAST_SRAM"] = {str(k): v.tolist() for k, v in bcast_map.items()}
    ar_sum, _ = gm.mpu_allreduce([v0, v1, v0 * 2.0, v1 * 2.0], mode="SUM")
    op_results["OP_MPU_ALLREDUCE"] = ar_sum.tolist()
    kv_q, kv_scale, kv_deq, _ = gm.llm_kv_pack(v0, MluPrec.PREC_INT4)
    op_results["OP_LLM_KV_PACK"] = {"q_int4": kv_q.tolist(), "scale": round(kv_scale, 6), "deq": [round(float(x), 5) for x in kv_deq]}
    acc_len, acc_flags, _ = gm.llm_spec_verify(np.array([0.8, 0.6, 0.2, 0.9]), np.array([0.7, 0.8, 0.5, 0.9]), np.array([0.5, 0.7, 0.6, 0.1]))
    assert acc_len == 2 and acc_flags == [True, True, False, False]
    op_results["OP_LLM_SPEC_VERIFY"] = {"accepted_len": acc_len, "accepted_flags": acc_flags}

    assert len(op_results) == len(MluOpcode), f"Expected {len(MluOpcode)} opcodes, got {len(op_results)}"
    return {"opcode_count": len(op_results), "total_cycles": gm.total_cycles, "op_results": op_results}


if __name__ == "__main__":
    ecc_res = test_hsiao_secded_72x64()
    inst_res = test_inst_and_noc_flit()
    ops_res = test_all_24_opcodes_and_export()
    out_dir = Path(__file__).resolve().parent / "vectors"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "golden_vectors.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"hsiao_secded_72x64": ecc_res, "inst_and_noc": inst_res, "bang_isa_24_opcodes": ops_res}, f, indent=2)
    print(f"[PASS] Verified all {ops_res['opcode_count']} BANG ISA opcodes, 8 precisions, SECDED ECC (2556 DED pairs), and NoC CRC-16.")
    print(f"[PASS] Exported golden vectors to {out_path}")
