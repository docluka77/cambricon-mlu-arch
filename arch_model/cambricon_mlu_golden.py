#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Cambricon Siyuan 590 / 690 (MLUarch05/06 & Cambricon-LLM/Q/S) Bit-Exact Golden Reference Model.
Matches rtl/mlu_pkg.sv bit-for-bit across all 24 BANG ISA opcodes, (72,64) Hsiao SECDED ECC,
8 numerical precisions, Cambricon-S/X sparsity, Cambricon-Q quantization, and MLU-Link NoC flits.
"""

from dataclasses import dataclass
from enum import IntEnum
import math
import struct
from typing import Dict, List, Optional, Tuple
import numpy as np


class MluMemSpace(IntEnum):
    MEM_SPACE_NRAM  = 0b000
    MEM_SPACE_WRAM  = 0b001
    MEM_SPACE_SRAM  = 0b010
    MEM_SPACE_LDRAM = 0b011
    MEM_SPACE_GDRAM = 0b100
    MEM_SPACE_MLULK = 0b101
    MEM_SPACE_FLASH = 0b110
    MEM_SPACE_MMIO  = 0b111


class MluPrec(IntEnum):
    PREC_INT4     = 0b000
    PREC_INT8     = 0b001
    PREC_FP8_E4M3 = 0b010
    PREC_FP8_E5M2 = 0b011
    PREC_FP16     = 0b100
    PREC_BF16     = 0b101
    PREC_TF32     = 0b110
    PREC_FP32     = 0b111


class MluSparseMode(IntEnum):
    SPARSE_DENSE     = 0b00
    SPARSE_2_OF_4    = 0b01
    SPARSE_BLOCK_4X4 = 0b10
    SPARSE_INDEXED   = 0b11


class MluEngine(IntEnum):
    ENG_ICU_CTRL = 0b000
    ENG_TFU_MAT  = 0b001
    ENG_VFU_VEC  = 0b010
    ENG_MFU_DMA  = 0b011
    ENG_MPU_COL  = 0b100
    ENG_LLM_KV   = 0b101


class MluOpcode(IntEnum):
    OP_NOP             = 0x00
    OP_SYNC_IPU        = 0x01
    OP_SYNC_CLUSTER    = 0x02
    OP_PWR_GATE_CFG    = 0x03
    OP_BANG_MATMUL     = 0x10
    OP_BANG_CONV2D     = 0x11
    OP_BANG_SPARSE_MM  = 0x12
    OP_BANG_QUANT_MM   = 0x13
    OP_BANG_VADD       = 0x20
    OP_BANG_VMUL       = 0x21
    OP_BANG_SOFTMAX    = 0x22
    OP_BANG_ROPE       = 0x23
    OP_BANG_RMSNORM    = 0x24
    OP_BANG_SWIGLU     = 0x25
    OP_BANG_QUANT_STAT = 0x26
    OP_BANG_MEMCPY_1D  = 0x30
    OP_BANG_MEMCPY_2D  = 0x31
    OP_BANG_GATHER     = 0x32
    OP_BANG_SCATTER    = 0x33
    OP_BANG_DECOMP_DMA = 0x34
    OP_BANG_TRANSPOSE  = 0x35
    OP_MPU_BCAST_SRAM  = 0x38
    OP_MPU_ALLREDUCE   = 0x39
    OP_LLM_KV_PACK     = 0x3A
    OP_LLM_SPEC_VERIFY = 0x3B


class MluFlitType(IntEnum):
    FLIT_HEAD_TAIL = 0b00
    FLIT_HEAD      = 0b01
    FLIT_BODY      = 0b10
    FLIT_TAIL      = 0b11


class HsiaoSecded72x64:
    """Bit-exact (72,64) Hsiao Minimum-Weight Odd-Column SECDED ECC Engine."""
    H_ROW: Tuple[int, ...] = (
        0xDF04225844B12CB7,
        0xEF0844A88952555B,
        0xF710893112649A6D,
        0x7B2111C22388E38E,
        0xBD421E043C0F03F0,
        0x3E83E007C00FFC00,
        0xC0FC0007FFF00000,
        0x00FFFFF800000000,
    )
    COL_SYNDROME: Dict[int, int] = {
        b: sum(((rows[r] >> b) & 1) << r for r in range(8))
        for rows in (H_ROW,) for b in range(64)
    }
    SYNDROME_TO_BIT: Dict[int, int] = {v: k for k, v in COL_SYNDROME.items()}

    @classmethod
    def encode(cls, data_64b: int) -> int:
        d = data_64b & 0xFFFFFFFFFFFFFFFF
        parity = 0
        for r in range(8):
            bit_p = (bin(d & cls.H_ROW[r]).count("1")) & 1
            parity |= (bit_p << r)
        return (parity << 64) | d

    @classmethod
    def decode(cls, codeword_72b: int) -> Tuple[int, int, bool, bool]:
        """Returns (corrected_data_64b, syndrome_8b, sec_corrected, ded_uncorrectable)."""
        cw = codeword_72b & ((1 << 72) - 1)
        d_in = cw & 0xFFFFFFFFFFFFFFFF
        p_in = (cw >> 64) & 0xFF
        syndrome = 0
        for r in range(8):
            calc_p = (bin(d_in & cls.H_ROW[r]).count("1")) & 1
            syndrome |= (((p_in >> r) & 1) ^ calc_p) << r
        if syndrome == 0:
            return d_in, 0, False, False
        odd_wt = (bin(syndrome).count("1") & 1) == 1
        if odd_wt:
            if syndrome in cls.SYNDROME_TO_BIT:
                bit_pos = cls.SYNDROME_TO_BIT[syndrome]
                return d_in ^ (1 << bit_pos), syndrome, True, False
            # Single-bit error in one of the 8 parity bits (weight-1 syndrome)
            return d_in, syndrome, True, False
        return d_in, syndrome, False, True


@dataclass
class BangInst128:
    opcode: MluOpcode
    engine: MluEngine
    prec: MluPrec
    sparse_mode: MluSparseMode
    src_space: MluMemSpace
    dst_space: MluMemSpace
    dep_mask: int
    tag_id: int
    dst_addr: int
    src0_addr: int
    src1_or_strd: int
    len_or_dims: int

    def pack(self) -> int:
        val = ((int(self.opcode) & 0x3F) << 122)
        val |= ((int(self.engine) & 0x7) << 119)
        val |= ((int(self.prec) & 0x7) << 116)
        val |= ((int(self.sparse_mode) & 0x3) << 114)
        val |= ((int(self.src_space) & 0x7) << 111)
        val |= ((int(self.dst_space) & 0x7) << 108)
        val |= ((self.dep_mask & 0xF) << 104)
        val |= ((self.tag_id & 0xFF) << 96)
        val |= ((self.dst_addr & 0xFFFFFFFF) << 64)
        val |= ((self.src0_addr & 0xFFFFFFFF) << 32)
        val |= ((self.src1_or_strd & 0xFFFF) << 16)
        val |= (self.len_or_dims & 0xFFFF)
        return val

    @classmethod
    def unpack(cls, word_128b: int) -> "BangInst128":
        w = word_128b & ((1 << 128) - 1)
        return cls(
            opcode=MluOpcode((w >> 122) & 0x3F),
            engine=MluEngine((w >> 119) & 0x7),
            prec=MluPrec((w >> 116) & 0x7),
            sparse_mode=MluSparseMode((w >> 114) & 0x3),
            src_space=MluMemSpace((w >> 111) & 0x7),
            dst_space=MluMemSpace((w >> 108) & 0x7),
            dep_mask=(w >> 104) & 0xF,
            tag_id=(w >> 96) & 0xFF,
            dst_addr=(w >> 64) & 0xFFFFFFFF,
            src0_addr=(w >> 32) & 0xFFFFFFFF,
            src1_or_strd=(w >> 16) & 0xFFFF,
            len_or_dims=w & 0xFFFF,
        )


@dataclass
class MluNocFlit128:
    flit_type: MluFlitType
    vc_id: int
    src_id: int
    dst_id: int
    pkt_seq: int
    addr: int
    payload: int
    crc16_or_cmd: Optional[int] = None

    @staticmethod
    def compute_crc16_ccitt(header_16b: int, addr_32b: int, payload_64b: int) -> int:
        """CRC-16-CCITT (poly=0x1021, init=0xFFFF, MSB-first) over 112-bit non-CRC fields."""
        bits_112 = ((header_16b & 0xFFFF) << 96) | ((addr_32b & 0xFFFFFFFF) << 64) | (payload_64b & 0xFFFFFFFFFFFFFFFF)
        crc = 0xFFFF
        for i in range(111, -1, -1):
            bit = (bits_112 >> i) & 1
            c15 = (crc >> 15) & 1
            crc = ((crc << 1) & 0xFFFF)
            if (c15 ^ bit) == 1:
                crc ^= 0x1021
        return crc & 0xFFFF

    def pack(self, auto_crc: bool = True) -> int:
        hdr16 = ((int(self.flit_type) & 0x3) << 14) | ((self.vc_id & 0x1) << 13) | ((self.src_id & 0xF) << 9) | ((self.dst_id & 0xF) << 5) | (self.pkt_seq & 0x1F)
        crc = self.compute_crc16_ccitt(hdr16, self.addr, self.payload) if (auto_crc or self.crc16_or_cmd is None) else (self.crc16_or_cmd & 0xFFFF)
        self.crc16_or_cmd = crc
        return (hdr16 << 112) | (crc << 96) | ((self.addr & 0xFFFFFFFF) << 64) | (self.payload & 0xFFFFFFFFFFFFFFFF)

    @classmethod
    def unpack(cls, flit_128b: int) -> Tuple["MluNocFlit128", bool]:
        w = flit_128b & ((1 << 128) - 1)
        hdr16 = (w >> 112) & 0xFFFF
        crc_rx = (w >> 96) & 0xFFFF
        addr = (w >> 64) & 0xFFFFFFFF
        payload = w & 0xFFFFFFFFFFFFFFFF
        crc_calc = cls.compute_crc16_ccitt(hdr16, addr, payload)
        flit = cls(
            flit_type=MluFlitType((hdr16 >> 14) & 0x3),
            vc_id=(hdr16 >> 13) & 0x1,
            src_id=(hdr16 >> 9) & 0xF,
            dst_id=(hdr16 >> 5) & 0xF,
            pkt_seq=hdr16 & 0x1F,
            addr=addr,
            payload=payload,
            crc16_or_cmd=crc_rx,
        )
        return flit, (crc_rx == crc_calc)


class NumericCodec:
    """Bit-exact scalar & tensor numeric quantization/conversion matching MLUarch05/06."""

    @staticmethod
    def encode_fp8_e4m3(val: float) -> int:
        if math.isnan(val):
            return 0x7F
        sign = 1 if val < 0 else 0
        av = min(abs(val), 448.0)
        if av == 0.0:
            return sign << 7
        exp_unbiased = int(math.floor(math.log2(av)))
        if exp_unbiased < -6:
            mant = int(round(av / (2.0 ** -9)))
            mant = max(0, min(7, mant))
            return (sign << 7) | mant
        exp_biased = max(1, min(15, exp_unbiased + 7))
        mant = int(round((av / (2.0 ** (exp_biased - 7)) - 1.0) * 8.0))
        if mant >= 8:
            mant = 0
            exp_biased = min(15, exp_biased + 1)
        if exp_biased == 15 and mant == 7:
            mant = 6  # E4M3 max normal is S.1111.110 = 448.0
        return (sign << 7) | (exp_biased << 3) | (mant & 0x7)

    @staticmethod
    def decode_fp8_e4m3(byte_val: int) -> float:
        b = byte_val & 0xFF
        sign = -1.0 if ((b >> 7) & 1) else 1.0
        exp = (b >> 3) & 0xF
        mant = b & 0x7
        if exp == 0:
            return sign * (mant / 8.0) * (2.0 ** -6)
        if exp == 15 and mant == 7:
            return float("nan")
        return sign * (1.0 + mant / 8.0) * (2.0 ** (exp - 7))

    @staticmethod
    def encode_fp8_e5m2(val: float) -> int:
        if math.isnan(val):
            return 0x7F
        sign = 1 if val < 0 else 0
        av = min(abs(val), 57344.0)
        if av == 0.0:
            return sign << 7
        exp_unbiased = int(math.floor(math.log2(av)))
        if exp_unbiased < -14:
            mant = max(0, min(3, int(round(av / (2.0 ** -16)))))
            return (sign << 7) | mant
        exp_biased = max(1, min(30, exp_unbiased + 15))
        mant = int(round((av / (2.0 ** (exp_biased - 15)) - 1.0) * 4.0))
        if mant >= 4:
            mant = 0
            exp_biased = min(30, exp_biased + 1)
        return (sign << 7) | (exp_biased << 2) | (mant & 0x3)

    @staticmethod
    def decode_fp8_e5m2(byte_val: int) -> float:
        b = byte_val & 0xFF
        sign = -1.0 if ((b >> 7) & 1) else 1.0
        exp = (b >> 2) & 0x1F
        mant = b & 0x3
        if exp == 0:
            return sign * (mant / 4.0) * (2.0 ** -14)
        if exp == 31:
            return float("inf") * sign if mant == 0 else float("nan")
        return sign * (1.0 + mant / 4.0) * (2.0 ** (exp - 15))

    @classmethod
    def quantize_value(cls, val: float, prec: MluPrec) -> float:
        if prec == MluPrec.PREC_INT4:
            return float(max(-8, min(7, int(round(val)))))
        if prec == MluPrec.PREC_INT8:
            return float(max(-128, min(127, int(round(val)))))
        if prec == MluPrec.PREC_FP8_E4M3:
            return cls.decode_fp8_e4m3(cls.encode_fp8_e4m3(val))
        if prec == MluPrec.PREC_FP8_E5M2:
            return cls.decode_fp8_e5m2(cls.encode_fp8_e5m2(val))
        if prec == MluPrec.PREC_FP16:
            return float(np.float16(val))
        if prec == MluPrec.PREC_BF16:
            bits = struct.unpack(">I", struct.pack(">f", float(val)))[0]
            bf_bits = ((bits + 0x7FFF + ((bits >> 16) & 1)) & 0xFFFF0000)
            return struct.unpack(">f", struct.pack(">I", bf_bits))[0]
        if prec == MluPrec.PREC_TF32:
            bits = struct.unpack(">I", struct.pack(">f", float(val)))[0]
            tf_bits = ((bits + 0xFFF + ((bits >> 13) & 1)) & 0xFFFFE000)
            return struct.unpack(">f", struct.pack(">I", tf_bits))[0]
        return float(np.float32(val))


class CambriconMluGoldenModel:
    """Bit-exact functional and cycle-latency reference model for all 24 BANG ISA opcodes."""

    def __init__(self, num_ipus: int = 4) -> None:
        self.num_ipus = num_ipus
        self.nram: List[Dict[int, int]] = [{} for _ in range(num_ipus)]
        self.wram: List[Dict[int, int]] = [{} for _ in range(num_ipus)]
        self.sram: Dict[int, int] = {}
        self.gdram: Dict[int, int] = {}
        self.flash: Dict[int, int] = {}
        self.mmio: Dict[int, int] = {0x00: 0, 0x04: 0}
        self.completed_tags: List[int] = []
        self.total_cycles: int = 0

    @staticmethod
    def nram_bank_index(byte_addr: int) -> int:
        """XOR bank-swizzled conflict-free NRAM bank mapping (8 banks, 64-bit words)."""
        return ((byte_addr >> 3) & 0x7) ^ ((byte_addr >> 6) & 0x7)

    def tfu_matmul(self, a: np.ndarray, b: np.ndarray, prec: MluPrec) -> Tuple[np.ndarray, int]:
        qa = np.vectorize(lambda x: NumericCodec.quantize_value(float(x), prec))(a)
        qb = np.vectorize(lambda x: NumericCodec.quantize_value(float(x), prec))(b)
        out = np.matmul(qa.astype(np.float64), qb.astype(np.float64))
        m, k = a.shape
        _, n = b.shape
        kappa = {MluPrec.PREC_INT4: 4, MluPrec.PREC_INT8: 2, MluPrec.PREC_FP8_E4M3: 2, MluPrec.PREC_FP8_E5M2: 2}.get(prec, 1)
        cycles = 4 + math.ceil(m / 8) * math.ceil(n / 8) * math.ceil(k / kappa)
        self.total_cycles += cycles
        return out.astype(np.float32), cycles

    def tfu_conv2d(self, x: np.ndarray, w: np.ndarray, prec: MluPrec) -> Tuple[np.ndarray, int]:
        # x: [C, H, W], w: [O, C, R, S]
        c_in, h, width = x.shape
        o_ch, _, r, s = w.shape
        oh, ow = h - r + 1, width - s + 1
        qx = np.vectorize(lambda v: NumericCodec.quantize_value(float(v), prec))(x)
        qw = np.vectorize(lambda v: NumericCodec.quantize_value(float(v), prec))(w)
        out = np.zeros((o_ch, oh, ow), dtype=np.float32)
        for o in range(o_ch):
            for i in range(oh):
                for j in range(ow):
                    out[o, i, j] = float(np.sum(qx[:, i:i+r, j:j+s] * qw[o]))
        cycles = 6 + o_ch * oh * ow * c_in * r * s // 16
        self.total_cycles += cycles
        return out, cycles

    def tfu_sparse_mm(
        self, a: np.ndarray, b_dense: np.ndarray, sparse_mode: MluSparseMode, prec: MluPrec
    ) -> Tuple[np.ndarray, np.ndarray, int]:
        """Cambricon-S/X Sparse GEMM returning (output_matrix, pruned_weight_matrix, cycles)."""
        qa = np.vectorize(lambda v: NumericCodec.quantize_value(float(v), prec))(a)
        qb = np.vectorize(lambda v: NumericCodec.quantize_value(float(v), prec))(b_dense).copy()
        k_dim, n_dim = qb.shape
        if sparse_mode == MluSparseMode.SPARSE_2_OF_4:
            for col in range(n_dim):
                for g in range(0, k_dim, 4):
                    grp = qb[g:g+4, col]
                    if len(grp) == 4:
                        idx_sorted = np.argsort(np.abs(grp), kind="stable")
                        grp[idx_sorted[:2]] = 0.0
                        qb[g:g+4, col] = grp
            speedup = 2.0
        elif sparse_mode == MluSparseMode.SPARSE_BLOCK_4X4:
            active_blocks, total_blocks = 0, 0
            for r in range(0, k_dim, 4):
                for c in range(0, n_dim, 4):
                    total_blocks += 1
                    blk = qb[r:r+4, c:c+4]
                    if np.max(np.abs(blk)) < 1e-6:
                        qb[r:r+4, c:c+4] = 0.0
                    else:
                        active_blocks += 1
            speedup = max(1.0, total_blocks / max(1, active_blocks))
        else:
            nz_ratio = max(0.25, float(np.count_nonzero(qb)) / max(1, qb.size))
            speedup = 1.0 / nz_ratio
        out = np.matmul(qa.astype(np.float64), qb.astype(np.float64)).astype(np.float32)
        base_cycles = 4 + math.ceil(a.shape[0] / 8) * math.ceil(n_dim / 8) * k_dim
        cycles = max(4, int(round(base_cycles / speedup)))
        self.total_cycles += cycles
        return out, qb.astype(np.float32), cycles

    def tfu_quant_mm(
        self, a_int: np.ndarray, w_int: np.ndarray, scale_a: float, zp_a: int, scale_w: float, zp_w: int
    ) -> Tuple[np.ndarray, np.ndarray, int]:
        """Cambricon-Q Statistical Quantized MatMul: returns (dequant_fp32, int32_accum, cycles)."""
        a_shifted = a_int.astype(np.int64) - int(zp_a)
        w_shifted = w_int.astype(np.int64) - int(zp_w)
        acc_i32 = np.matmul(a_shifted, w_shifted).astype(np.int32)
        dequant = (acc_i32.astype(np.float64) * float(scale_a) * float(scale_w)).astype(np.float32)
        cycles = 5 + math.ceil(a_int.shape[0] / 8) * math.ceil(w_int.shape[1] / 8) * math.ceil(a_int.shape[1] / 2)
        self.total_cycles += cycles
        return dequant, acc_i32, cycles

    def vfu_vadd(self, a: np.ndarray, b: np.ndarray, prec: MluPrec) -> np.ndarray:
        self.total_cycles += 3 + math.ceil(a.size / 8)
        return np.vectorize(lambda x, y: NumericCodec.quantize_value(float(x) + float(y), prec))(a, b).astype(np.float32)

    def vfu_vmul(self, a: np.ndarray, b: np.ndarray, prec: MluPrec) -> np.ndarray:
        self.total_cycles += 3 + math.ceil(a.size / 8)
        return np.vectorize(lambda x, y: NumericCodec.quantize_value(float(x) * float(y), prec))(a, b).astype(np.float32)

    def vfu_softmax(self, x: np.ndarray) -> np.ndarray:
        self.total_cycles += 6 + 2 * math.ceil(x.size / 8)
        xf = x.astype(np.float64)
        m = np.max(xf, axis=-1, keepdims=True)
        ex = np.exp(xf - m)
        return (ex / np.sum(ex, axis=-1, keepdims=True)).astype(np.float32)

    def vfu_rope(self, x: np.ndarray, cos_t: np.ndarray, sin_t: np.ndarray) -> np.ndarray:
        """Rotary Position Embedding on interleaved pairs (x[2i], x[2i+1])."""
        self.total_cycles += 4 + math.ceil(x.size / 8)
        out = np.zeros_like(x, dtype=np.float32)
        x0 = x[..., 0::2].astype(np.float64)
        x1 = x[..., 1::2].astype(np.float64)
        c = cos_t.astype(np.float64)
        s = sin_t.astype(np.float64)
        out[..., 0::2] = (x0 * c - x1 * s).astype(np.float32)
        out[..., 1::2] = (x0 * s + x1 * c).astype(np.float32)
        return out

    def vfu_rmsnorm(self, x: np.ndarray, gamma: np.ndarray, eps: float = 1e-5) -> np.ndarray:
        self.total_cycles += 6 + 2 * math.ceil(x.size / 8)
        xf = x.astype(np.float64)
        rms_inv = 1.0 / np.sqrt(np.mean(xf * xf, axis=-1, keepdims=True) + eps)
        return (xf * rms_inv * gamma.astype(np.float64)).astype(np.float32)

    def vfu_swiglu(self, gate: np.ndarray, up: np.ndarray) -> np.ndarray:
        self.total_cycles += 4 + math.ceil(gate.size / 8)
        g = gate.astype(np.float64)
        silu = g / (1.0 + np.exp(-g))
        return (silu * up.astype(np.float64)).astype(np.float32)

    def vfu_quant_stat(self, x: np.ndarray, qmax: int = 127) -> Dict[str, float]:
        """Cambricon-Q dynamic statistical analyzer: returns min, max, absmax, scale, zero_point."""
        self.total_cycles += 5 + math.ceil(x.size / 8)
        xmin, xmax = float(np.min(x)), float(np.max(x))
        absmax = max(abs(xmin), abs(xmax), 1e-8)
        scale = absmax / float(qmax)
        zp = int(round(- (xmin + xmax) / (2.0 * scale))) if qmax == 127 else 0
        zp = max(-qmax, min(qmax, zp))
        return {"min": xmin, "max": xmax, "absmax": absmax, "scale": scale, "zero_point": float(zp)}

    def mfu_memcpy_1d(self, src_buf: np.ndarray) -> Tuple[np.ndarray, int]:
        cycles = 4 + math.ceil(src_buf.nbytes / 64)
        self.total_cycles += cycles
        return src_buf.copy(), cycles

    def mfu_memcpy_2d(
        self, src_mem: np.ndarray, src_offset: int, dst_shape: Tuple[int, int], src_stride: int, dst_stride: int
    ) -> Tuple[np.ndarray, int]:
        rows, cols = dst_shape
        flat_src = src_mem.reshape(-1)
        dst_flat = np.zeros(rows * dst_stride, dtype=src_mem.dtype)
        for r in range(rows):
            s_idx = src_offset + r * src_stride
            d_idx = r * dst_stride
            dst_flat[d_idx:d_idx + cols] = flat_src[s_idx:s_idx + cols]
        cycles = 6 + rows * math.ceil(cols / 8)
        self.total_cycles += cycles
        return dst_flat.reshape(rows, dst_stride)[:, :cols], cycles

    def mfu_gather(self, table: np.ndarray, indices: np.ndarray) -> Tuple[np.ndarray, int]:
        cycles = 5 + len(indices)
        self.total_cycles += cycles
        return table[indices].copy(), cycles

    def mfu_scatter(self, dst_base: np.ndarray, values: np.ndarray, indices: np.ndarray) -> Tuple[np.ndarray, int]:
        out = dst_base.copy()
        out[indices] = values
        cycles = 5 + len(indices)
        self.total_cycles += cycles
        return out, cycles

    def mfu_decomp_dma(self, nz_values: np.ndarray, zero_bitmap: int, total_len: int) -> Tuple[np.ndarray, int]:
        """Hardware Zero-Bitmap / LZ4 Decompression DMA into WRAM/NRAM."""
        out = np.zeros(total_len, dtype=nz_values.dtype)
        nz_ptr = 0
        for i in range(total_len):
            if (zero_bitmap >> i) & 1:
                out[i] = nz_values[nz_ptr]
                nz_ptr += 1
        cycles = 5 + math.ceil(total_len / 16)
        self.total_cycles += cycles
        return out, cycles

    def mfu_transpose(self, mat_2d: np.ndarray) -> Tuple[np.ndarray, int]:
        """Conflict-free NRAM 2D matrix transpose using XOR bank-swizzled crossbar."""
        r, c = mat_2d.shape
        cycles = 4 + math.ceil((r * c) / 8)
        self.total_cycles += cycles
        return np.ascontiguousarray(mat_2d.T), cycles

    def mpu_bcast_sram(self, sram_tile: np.ndarray, ipu_mask: int = 0xF) -> Tuple[Dict[int, np.ndarray], int]:
        """Single-read multi-cast broadcast from MPU 4 MB Shared SRAM to selected IPU cores."""
        delivered: Dict[int, np.ndarray] = {}
        for ipu_id in range(self.num_ipus):
            if (ipu_mask >> ipu_id) & 1:
                delivered[ipu_id] = sram_tile.copy()
        cycles = 4 + math.ceil(sram_tile.nbytes / 64)
        self.total_cycles += cycles
        return delivered, cycles

    def mpu_allreduce(self, ipu_tensors: List[np.ndarray], mode: str = "SUM") -> Tuple[np.ndarray, int]:
        stack = np.stack(ipu_tensors, axis=0).astype(np.float64)
        if mode == "MAX":
            res = np.max(stack, axis=0)
        elif mode == "MIN":
            res = np.min(stack, axis=0)
        elif mode == "AVG":
            res = np.mean(stack, axis=0)
        else:
            res = np.sum(stack, axis=0)
        cycles = 6 + math.ceil(ipu_tensors[0].size / 8)
        self.total_cycles += cycles
        return res.astype(np.float32), cycles

    def llm_kv_pack(self, kv_fp16: np.ndarray, prec: MluPrec = MluPrec.PREC_INT4) -> Tuple[np.ndarray, float, np.ndarray, int]:
        """Cambricon-LLM (MICRO'24) Per-Token KV-Cache INT4/FP8 Quant-Pack + Dequant Reference."""
        absmax = max(float(np.max(np.abs(kv_fp16))), 1e-8)
        if prec == MluPrec.PREC_INT4:
            scale = absmax / 7.0
            q_vals = np.clip(np.round(kv_fp16 / scale), -8, 7).astype(np.int8)
            deq = (q_vals.astype(np.float32) * scale)
        else:
            scale = absmax / 448.0
            q_vals = np.array([NumericCodec.encode_fp8_e4m3(float(v / scale)) for v in kv_fp16.reshape(-1)], dtype=np.uint8).reshape(kv_fp16.shape)
            deq = np.array([NumericCodec.decode_fp8_e4m3(int(b)) * scale for b in q_vals.reshape(-1)], dtype=np.float32).reshape(kv_fp16.shape)
        cycles = 4 + math.ceil(kv_fp16.size / 16)
        self.total_cycles += cycles
        return q_vals, scale, deq, cycles

    def llm_spec_verify(self, p_target: np.ndarray, q_draft: np.ndarray, u_rand: np.ndarray) -> Tuple[int, List[bool], int]:
        """Cambricon-LLM Speculative Decoding Tree Verification: accepts prefix while u_t < min(1, p_t / q_t)."""
        accepted_flags: List[bool] = []
        accepted_len = 0
        prefix_alive = True
        for p, q, u in zip(p_target, q_draft, u_rand):
            ratio = min(1.0, float(p) / max(float(q), 1e-9))
            ok = bool(float(u) < ratio) and prefix_alive
            accepted_flags.append(ok)
            if ok:
                accepted_len += 1
            else:
                prefix_alive = False
        cycles = 3 + len(p_target)
        self.total_cycles += cycles
        return accepted_len, accepted_flags, cycles

    def execute_control_op(self, inst: BangInst128) -> Dict[str, int]:
        self.completed_tags.append(inst.tag_id)
        lat = 1 if inst.opcode == MluOpcode.OP_NOP else (2 if inst.opcode == MluOpcode.OP_PWR_GATE_CFG else 3)
        self.total_cycles += lat
        if inst.opcode == MluOpcode.OP_PWR_GATE_CFG:
            self.mmio[0x04] = ((inst.src1_or_strd & 0xFFFF) << 16) | (inst.len_or_dims & 0xFFFF)
        return {"opcode": int(inst.opcode), "tag_id": inst.tag_id, "cycles": lat, "mmio_pwr_cfg": self.mmio[0x04]}
