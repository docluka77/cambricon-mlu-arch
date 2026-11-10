// =============================================================================
// File: rtl/mlu_pkg.sv
// Project: Cambricon Siyuan 590 / 690 (MLUarch05 / MLUarch06 & Cambricon-LLM/Q/S)
// Description: Master SystemVerilog Package defining BANG ISA 128-bit Instruction
//              Encoding, Multi-Precision Data Types (FP32/TF32/BF16/FP16/FP8/INT8/INT4),
//              NRAM/WRAM/SRAM/GDRAM Memory Hierarchy, SECDED ECC, and MLU-Link NoC Flits.
// =============================================================================
`ifndef MLU_PKG_SV
`define MLU_PKG_SV

package mlu_pkg;
  /* verilator lint_off UNUSEDPARAM */

  // ---------------------------------------------------------------------------
  // 1. Architectural Scaling & Hierarchy Parameters (MLU590 / MLU690 Baseline)
  // ---------------------------------------------------------------------------
  parameter int unsigned MLU_NUM_DIES          = 2;    // Dual-Die Chiplet (MLU590/690)
  parameter int unsigned MLU_CLUSTERS_PER_DIE  = 12;   // 12 MTP Clusters/Die (24 Total)
  parameter int unsigned MLU_IPUS_PER_CLUSTER  = 4;    // 4 IPU Tensor Cores per MTP Cluster
  parameter int unsigned MLU_MPUS_PER_CLUSTER  = 1;    // 1 MPU Memory Core per MTP Cluster

  // Parameterized RTL Verification / Synthesis Default Geometry (Scalable)
  parameter int unsigned P_CLUSTER_IPUS        = 4;    // 4 IPU Cores in RTL Cluster
  parameter int unsigned P_TFU_DIM             = 8;    // 8x8 Fractal MAC Tile (64 MACs/cycle/tile)
  parameter int unsigned P_VFU_LANES           = 8;    // 8 Parallel Vector/SFU Lanes (16-bit/32-bit)
  parameter int unsigned P_NRAM_BANKS          = 8;    // 8-Bank Conflict-Free NRAM Scratchpad
  parameter int unsigned P_WRAM_BANKS          = 4;    // 4-Bank Ping-Pong WRAM Weight Buffer
  parameter int unsigned P_SRAM_BANKS          = 8;    // 8-Bank MPU Cluster Shared SRAM
  parameter int unsigned P_DATA_W              = 64;   // 64-bit Data Word per Bank Port
  parameter int unsigned P_ECC_W               = 72;   // (72,64) Hsiao SECDED ECC Codeword
  parameter int unsigned P_ADDR_W              = 32;   // 32-bit Unified Address Space
  parameter int unsigned P_INST_W              = 128;  // 128-bit BANG ISA Instruction Word
  parameter int unsigned P_NOC_FLIT_W          = 128;  // 128-bit MLU-Link Coherent NoC Flit

  // ---------------------------------------------------------------------------
  // 2. Explicit Memory Space Aperture Encoding (BANG C Memory Hierarchy)
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    MEM_SPACE_NRAM  = 3'b000, // IPU Private Neural Activation Scratchpad (768 KB/IPU)
    MEM_SPACE_WRAM  = 3'b001, // IPU Private Weight Scratchpad (512 KB/IPU)
    MEM_SPACE_SRAM  = 3'b010, // MPU Cluster Shared Scratchpad (4 MB/Cluster)
    MEM_SPACE_LDRAM = 3'b011, // IPU Local Stack / Spill DRAM Aperture
    MEM_SPACE_GDRAM = 3'b100, // Off-Chip HBM2e / HBM3e Global Memory (96 GB, 2.0-2.8 TB/s)
    MEM_SPACE_MLULK = 3'b101, // Remote Die / Remote Chip via MLU-Link (512 GB/s)
    MEM_SPACE_FLASH = 3'b110, // Cambricon-LLM In-Flash KV/Weight Channel
    MEM_SPACE_MMIO  = 3'b111  // Control & Status Register Aperture
  } mlu_mem_space_e;

  // ---------------------------------------------------------------------------
  // 3. Multi-Precision Numerical Formats (MLUarch05 / MLUarch06 + Cambricon-Q/P)
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    PREC_INT4    = 3'b000, // 4-bit Signed Integer (1024 TOPS Peak Dense, 2048 Sparse)
    PREC_INT8    = 3'b001, // 8-bit Signed Integer (512 TOPS Peak Dense, 1024 Sparse)
    PREC_FP8_E4M3= 3'b010, // 8-bit FP8 E4M3 (688 TFLOPS MLUarch06 LLM Forward)
    PREC_FP8_E5M2= 3'b011, // 8-bit FP8 E5M2 (688 TFLOPS MLUarch06 LLM Gradient)
    PREC_FP16    = 3'b100, // IEEE 754 Half-Precision FP16 (256-345 TFLOPS)
    PREC_BF16    = 3'b101, // Brain Floating Point BF16 (256-345 TFLOPS)
    PREC_TF32    = 3'b110, // TensorFloat-32 (19-bit mantissa+exp, 128-172 TFLOPS)
    PREC_FP32    = 3'b111  // IEEE 754 Single-Precision FP32 Accumulator
  } mlu_prec_e;

  // ---------------------------------------------------------------------------
  // 4. Cambricon-S Sparsity & Cambricon-Q Quantization Modes
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    SPARSE_DENSE     = 2'b00, // Standard Dense Tensor Operation
    SPARSE_2_OF_4    = 2'b01, // Structured 2:4 Fine-Grained Sparsity (2x Speedup)
    SPARSE_BLOCK_4X4 = 2'b10, // Cambricon-S Coarse-Grained Block Sparsity (Bitmap Skip)
    SPARSE_INDEXED   = 2'b11  // Cambricon-X Unstructured Compressed Step-Index
  } mlu_sparse_mode_e;
  // ---------------------------------------------------------------------------
  // 5. BANG ISA Execution Engine Queue IDs & Opcode Enumeration
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ENG_ICU_CTRL = 3'b000, // Scalar Control, Branch, Loop, & Hardware Sync Barrier
    ENG_TFU_MAT  = 3'b001, // Tensor Function Unit (Matrix Multiply / Conv / Sparse MAC)
    ENG_VFU_VEC  = 3'b010, // Vector Function Unit (ALU / SFU / Softmax / RoPE / RMSNorm)
    ENG_MFU_DMA  = 3'b011, // Memory Function Unit (2D/3D Strided & Gather/Scatter DMA)
    ENG_MPU_COL  = 3'b100, // MPU Cluster Shared SRAM Broadcast / AllReduce Engine
    ENG_LLM_KV   = 3'b101  // Cambricon-LLM Flash KV-Cache & Speculative Tree Engine
  } mlu_engine_e;

  typedef enum logic [5:0] {
    // Control & Synchronization Opcodes (ENG_ICU_CTRL)
    OP_NOP              = 6'h00,
    OP_SYNC_IPU         = 6'h01, // Wait for local IPU queues (TFU/VFU/MFU) to drain
    OP_SYNC_CLUSTER     = 6'h02, // Hardware Union-Task Barrier across all 4 IPUs + 1 MPU
    OP_PWR_GATE_CFG     = 6'h03, // Dynamic Clock/Power Gating Hint for Idle Engines
    // Tensor Function Unit Opcodes (ENG_TFU_MAT: __bang_mlp / __bang_conv / __bang_matmul)
    OP_BANG_MATMUL      = 6'h10, // Dense NRAM x WRAM -> NRAM Matrix Multiply-Accumulate
    OP_BANG_CONV2D      = 6'h11, // Implicit Im2Col Convolution on NRAM x WRAM
    OP_BANG_SPARSE_MM   = 6'h12, // Cambricon-S/X 2:4 & Block-Sparse Matrix Multiply
    OP_BANG_QUANT_MM    = 6'h13, // Cambricon-Q Bit-Split & Statistical Quantized MatMul
    // Vector & Special Function Unit Opcodes (ENG_VFU_VEC: __bang_*)
    OP_BANG_VADD        = 6'h20, // Elementwise Vector Addition
    OP_BANG_VMUL        = 6'h21, // Elementwise Vector Multiplication
    OP_BANG_SOFTMAX     = 6'h22, // FlashAttention Online Safe Softmax (Max + Exp + Rescale)
    OP_BANG_ROPE        = 6'h23, // Rotary Position Embedding (RoPE Sin/Cos Complex Rotate)
    OP_BANG_RMSNORM     = 6'h24, // Root-Mean-Square Layer Normalization (Variance + Rsqrt)
    OP_BANG_SWIGLU      = 6'h25, // Fused SiLU(Gate) * Up-Projection Activation
    OP_BANG_QUANT_STAT  = 6'h26, // Cambricon-Q Dynamic Min/Max/AbsMax & Scale/ZeroPoint
    // Memory Function Unit DMA Opcodes (ENG_MFU_DMA: __memcpy_async)
    OP_BANG_MEMCPY_1D   = 6'h30, // Contiguous 1D DMA Transfer (Any Space -> Any Space)
    OP_BANG_MEMCPY_2D   = 6'h31, // 2D Strided Tensor Tile Transfer (src_stride, dst_stride)
    OP_BANG_GATHER      = 6'h32, // Indirect Indexed Gather DMA (Embedding / Sparse KV)
    OP_BANG_SCATTER     = 6'h33, // Indirect Indexed Scatter DMA
    OP_BANG_DECOMP_DMA  = 6'h34, // LZ4 / Zero-Bitmap Hardware Decompression DMA to WRAM/NRAM
    OP_BANG_TRANSPOSE   = 6'h35, // NRAM On-the-Fly 2D Matrix Transpose
    // Collective & Cambricon-LLM Opcodes (ENG_MPU_COL / ENG_LLM_KV)
    OP_MPU_BCAST_SRAM   = 6'h38, // MPU Shared SRAM Multi-Cast Broadcast to 4 IPU WRAM/NRAMs
    OP_MPU_ALLREDUCE    = 6'h39, // Intra-Cluster & Inter-Chiplet MLU-Link Ring AllReduce
    OP_LLM_KV_PACK      = 6'h3A, // Cambricon-LLM INT4/FP8 Per-Token KV-Cache Quant-Pack
    OP_LLM_SPEC_VERIFY  = 6'h3B  // Speculative Decoding Draft-Token Tree Verification
  } mlu_opcode_e;

  // ---------------------------------------------------------------------------
  // 6. 128-Bit BANG ISA Instruction Format (mlu_inst_t)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    mlu_opcode_e      opcode;       // [127:122] 6-bit BANG Opcode
    mlu_engine_e      engine;       // [121:119] 3-bit Target Functional Unit Queue
    mlu_prec_e        prec;         // [118:116] 3-bit Precision Mode
    mlu_sparse_mode_e sparse_mode;  // [115:114] 2-bit Sparsity Mode
    mlu_mem_space_e   src_space;    // [113:111] 3-bit Source Memory Space
    mlu_mem_space_e   dst_space;    // [110:108] 3-bit Destination Memory Space
    logic [3:0]       dep_mask;     // [107:104] 4-bit Explicit Queue Dependency Mask
    logic [7:0]       tag_id;       // [103:96]  8-bit Scoreboard Instruction Tag
    logic [31:0]      dst_addr;     // [95:64]   32-bit Destination Base Address / Reg
    logic [31:0]      src0_addr;    // [63:32]   32-bit Source 0 Base Address (NRAM/SRAM/GDRAM)
    logic [15:0]      src1_or_strd; // [31:16]   16-bit Source 1 Offset (WRAM) or Stride
    logic [15:0]      len_or_dims;  // [15:0]    16-bit Transfer Length or Matrix M/N/K Tile Dim
  } mlu_inst_t;

  // ---------------------------------------------------------------------------
  // 7. 128-Bit MLU-Link Coherent Packetized NoC Flit (mlu_noc_flit_t)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    FLIT_HEAD_TAIL = 2'b00, // Single-Flit Atomic Packet
    FLIT_HEAD      = 2'b01, // Multi-Flit Header
    FLIT_BODY      = 2'b10, // Multi-Flit Payload Body
    FLIT_TAIL      = 2'b11  // Multi-Flit Tail + CRC-16 Checksum
  } mlu_flit_type_e;

  typedef struct packed {
    mlu_flit_type_e   flit_type;    // [127:126] Flit Framing Type
    logic             vc_id;        // [125]     Virtual Channel (0=Req/Data, 1=Resp/AllReduce)
    logic [3:0]       src_id;       // [124:121] Source Node ID (Cluster/Die/Chip)
    logic [3:0]       dst_id;       // [120:117] Destination Node ID (XY/Ring Routing)
    logic [4:0]       pkt_seq;      // [116:112] Packet Sequence Number for Link Replay
    logic [15:0]      crc16_or_cmd; // [111:96]  CRC-16-CCITT or AllReduce/DMA Command
    logic [31:0]      addr;         // [95:64]   Target Memory Address
    logic [63:0]      payload;      // [63:0]    64-bit Tensor Data Payload
  } mlu_noc_flit_t;

  /* verilator lint_on UNUSEDPARAM */
endpackage : mlu_pkg
`endif // MLU_PKG_SV
