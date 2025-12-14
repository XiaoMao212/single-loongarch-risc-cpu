`include "mycpu.h"

module mycpu_core(
    input         clk,
    input         resetn,
    /*
    // inst sram interface
    output        inst_sram_en,
    output [ 3:0] inst_sram_we,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata,
    // data sram interface
    output        data_sram_en,
    output [ 3:0] data_sram_we,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input  [31:0] data_sram_rdata,
    */
    // inst sram interface
    output        inst_sram_req,
    output        inst_sram_wr,
    output [ 1:0] inst_sram_size,
    output [ 3:0] inst_sram_wstrb,
    output [31:0] inst_sram_addr,
    output [31:0] inst_sram_wdata,
    input  [31:0] inst_sram_rdata,
    input         inst_sram_addr_ok,
    input         inst_sram_data_ok,
    // data sram interface
    output        data_sram_req,
    output        data_sram_wr,
    output [ 3:0] data_sram_wstrb,
    output [ 1:0] data_sram_size,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata,
    input  [31:0] data_sram_rdata,
    input         data_sram_addr_ok,
    input         data_sram_data_ok_l,
    input         data_sram_data_ok_s,
    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_we,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata,
    output [31:0] fs_va,
    output ws_reflush,
    output uncached,
    output data_uncached  

);
reg         reset;
always @(posedge clk) reset <= ~resetn;

wire         ds_allowin;
wire         es_allowin;
wire         ms_allowin;
wire         ws_allowin;
wire         fs_to_ds_valid;
wire         ds_to_es_valid;
wire         es_to_ms_valid;
wire         ms_to_ws_valid;
wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
wire [`BR_BUS_WD       -1:0] br_bus;
wire [36:0] es_forward_reg;
wire [36:0] ms_forward_reg;
wire [36:0] ws_forward_reg;
wire es_to_ds_load_op;
wire ms_to_ds_load_op;
wire [`WS_TO_CSR_BUS -1:0] ws_to_csr_bus;
wire ms_ex;
wire ws_ex;
wire [31:0] csr_rvalue;
wire [31:0] ex_entry;
wire [31:0] era_entry;
wire es_csr_re;
wire ms_csr_re;

wire ertn_flush;
wire has_int;
wire es_to_ds_inst_no_dest;
wire ms_to_ds_inst_no_dest;
wire ws_to_ds_inst_no_dest;


wire [ 9:0] csr_asid_asid;
wire [18:0] csr_tlbehi_vppn;
wire [ 3:0] csr_tlbidx_index;

wire        ms_tlb_forward;
wire        ws_tlb_forward;

wire        tlbrd_we;
wire        tlbsrch_we;
wire        tlbsrch_hit;
wire [ 3:0] tlbsrch_hit_index;


// TLB ports
wire [18:0] s0_vppn;
wire        s0_va_bit12;
wire [ 9:0] s0_asid;
wire        s0_found;
wire [ 3:0] s0_index;
wire [19:0] s0_ppn;
wire [ 5:0] s0_ps;
wire [ 1:0] s0_plv;
wire [ 1:0] s0_mat;
wire        s0_d;
wire        s0_v;
wire [18:0] s1_vppn;
wire        s1_va_bit12;
wire [ 9:0] s1_asid;
wire        s1_found;
wire [ 3:0] s1_index;
wire [19:0] s1_ppn;
wire [ 5:0] s1_ps;
wire [ 1:0] s1_plv;
wire [ 1:0] s1_mat;
wire        s1_d;
wire        s1_v;
wire [ 4:0] invtlb_op;
wire        invtlb_valid;
wire        we;
wire [ 3:0] w_index;
wire        w_e;
wire [18:0] w_vppn;
wire [ 5:0] w_ps;
wire [ 9:0] w_asid;
wire        w_g;
wire [19:0] w_ppn0;
wire [ 1:0] w_plv0;
wire [ 1:0] w_mat0;
wire        w_d0;
wire        w_v0;
wire [19:0] w_ppn1;
wire [ 1:0] w_plv1;
wire [ 1:0] w_mat1;
wire        w_d1;
wire        w_v1;
wire [ 3:0] r_index;
wire        r_e;
wire [18:0] r_vppn;
wire [ 5:0] r_ps;
wire [ 9:0] r_asid;
wire        r_g;
wire [19:0] r_ppn0;
wire [ 1:0] r_plv0;
wire [ 1:0] r_mat0;
wire        r_d0;
wire        r_v0;
wire [19:0] r_ppn1;
wire [ 1:0] r_plv1;
wire [ 1:0] r_mat1;
wire        r_d1;
wire        r_v1;


//exp19

wire [31:0] csr_crmd_rvalue;
wire [31:0] csr_asid_rvalue;
wire [31:0] csr_dmw0_rvalue;
wire [31:0] csr_dmw1_rvalue;

wire[31:0] fs_va;
wire[31:0] fs_pa;
wire[9 :0] fs_asid;
wire[5 :0] fs_exc_ecode;
wire[5 :0] es_exc_ecode;

wire[1 :0] fs_plv;
wire       fs_dmwhit;
wire[31:0] es_va;
wire[31:0] es_pa;
wire[1 :0] es_plv;
wire       es_dmwhit;
wire[1 :0] es_mmu_en;

//exp21
wire [2:0] exe_need_mem_forward;
// IF stage
if_stage if_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ds_allowin     (ds_allowin     ),
    //brbus
    .br_bus         (br_bus         ),
    //outputs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    // inst sram interface
    .inst_sram_en   (inst_sram_req   ),
    .inst_sram_wr(inst_sram_wr),
    .inst_sram_we   (inst_sram_wstrb ),
    .inst_sram_size(inst_sram_size),
    .inst_sram_addr (inst_sram_addr ),
    .inst_sram_wdata(inst_sram_wdata),
    .inst_sram_rdata(inst_sram_rdata),
    .inst_sram_addr_ok(inst_sram_addr_ok),
    .inst_sram_data_ok(inst_sram_data_ok),
    .ws_ex          (ws_ex),
    .ertn_flush     (ertn_flush),
    .ex_entry       (ex_entry),
    .era_entry      (era_entry),
    .fs_reflush     (ws_reflush),
    
    .va                     (fs_va),
    .pa                     (fs_pa),
    .plv                    (fs_plv),
    .dmw_hit                (fs_dmwhit),
    .mmu_asid               (fs_asid),
    .fs_exc_ecode           (fs_exc_ecode),
    .s0_va_highbits         ({s0_vppn, s0_va_bit12}),
    .s0_asid                (s0_asid),
    .exe_need_mem_forward   (exe_need_mem_forward)
);

MMU IF_mmu(
  .flag(2'b10),
  
  .csr_crmd_rvalue          (csr_crmd_rvalue),
  .csr_asid_rvalue          (csr_asid_rvalue),
  .csr_dmw0_rvalue          (csr_dmw0_rvalue),
  .csr_dmw1_rvalue          (csr_dmw1_rvalue),

  .s_found                  (s0_found),
  .s_index                  (s0_index),
  .s_ppn                    (s0_ppn),
  .s_ps                     (s0_ps),
  .s_plv                    (s0_plv),
  .s_mat                    (s0_mat),
  .s_d                      (s0_d),
  .s_v                      (s0_v),
  
    //mmu module
  .dmw_hit                  (fs_dmwhit),
  .plv                      (fs_plv),
  .va                       (fs_va),
  .exc_ecode                (fs_exc_ecode),
  .s_asid                   (fs_asid),
  .pa                       (fs_pa),
  .uncached                 (uncached)
);
// ID stage
id_stage id_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .es_allowin     (es_allowin     ),
    .ds_allowin     (ds_allowin     ),
    //from fs
    .fs_to_ds_valid (fs_to_ds_valid ),
    .fs_to_ds_bus   (fs_to_ds_bus   ),
    //to es
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to fs
    .br_bus         (br_bus         ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    //load op
    .es_to_ds_load_op  (es_to_ds_load_op  ),
    .ms_to_ds_load_op  (ms_to_ds_load_op),
    .es_to_ds_inst_no_dest (es_to_ds_inst_no_dest),
    .ms_to_ds_inst_no_dest (ms_to_ds_inst_no_dest),
    .ws_to_ds_inst_no_dest (ws_to_ds_inst_no_dest),
    //the reg address and data from es ms ws
    .es_forward_reg  (es_forward_reg  ),
    .ms_forward_reg  (ms_forward_reg  ),
    .ws_forward_reg  (ws_forward_reg  ),
    .ds_reflush      (ws_reflush),
    .es_csr_re(es_csr_re),
    .ms_csr_re(ms_csr_re),
    .ds_has_int(has_int)
);
// EXE stage
exe_stage exe_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ms_allowin     (ms_allowin     ),
    .es_allowin     (es_allowin     ),
    //from ds
    .ds_to_es_valid (ds_to_es_valid ),
    .ds_to_es_bus   (ds_to_es_bus   ),
    //to ms
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    // data sram interface
    .data_sram_en   (data_sram_req   ),
    .data_sram_wr(data_sram_wr),
    .data_sram_we   (data_sram_wstrb ),
    .data_sram_size(data_sram_size),
    .data_sram_addr (data_sram_addr ),
    .data_sram_wdata(data_sram_wdata),
    .data_sram_addr_ok(data_sram_addr_ok),
    .data_sram_rdata (data_sram_rdata),
    //load op
    .es_to_ds_load_op  (es_to_ds_load_op  ),
    .es_to_ds_inst_no_dest(es_to_ds_inst_no_dest),
    //the reg address for id stage
    .es_forward_reg  (es_forward_reg),

    .ms_ex           (ms_ex),
    .es_reflush      (ws_reflush),
    .es_csr_re(es_csr_re),
    
    
    .s1_va_highbits  ({s1_vppn, s1_va_bit12}),
    .s1_asid         (s1_asid),
    .invtlb_valid    (invtlb_valid),
    .invtlb_op       (invtlb_op),
    .csr_asid_asid   (csr_asid_asid),
    .csr_tlbehi_vppn (csr_tlbehi_vppn),
    .ms_tlb_forward  (ms_tlb_forward),
    .ws_tlb_forward  (ws_tlb_forward),
    
    // exp 19
    .es_exc_ecode           (es_exc_ecode),
    .dmw_hit                (es_dmwhit),
    .plv                    (es_plv),
    .va                     (es_va),
    .pa                     (es_pa),
    .mmu_en                 (es_mmu_en),
    .exe_need_mem_forward   (exe_need_mem_forward)
);

MMU EXE_mmu(
    .flag                   (es_mmu_en),
    .csr_crmd_rvalue        (csr_crmd_rvalue),
    .csr_asid_rvalue        (csr_asid_rvalue),
    .csr_dmw0_rvalue        (csr_dmw0_rvalue),
    .csr_dmw1_rvalue        (csr_dmw1_rvalue),
    
    .s_found                (s1_found),
    .s_index                (s1_index),
    .s_ppn                  (s1_ppn),
    .s_ps                   (s1_ps),
    .s_plv                  (s1_plv),
    .s_mat                  (s1_mat),
    .s_d                    (s1_d),
    .s_v                    (s1_v),
    
    .va                     (es_va),
    .exc_ecode              (es_exc_ecode),
    .dmw_hit                (es_dmwhit),
    .plv                    (es_plv),
    .pa                     (es_pa),
    .uncached               (data_uncached)
);

// MEM stage
mem_stage mem_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    .ms_allowin     (ms_allowin     ),
    //from es
    .es_to_ms_valid (es_to_ms_valid ),
    .es_to_ms_bus   (es_to_ms_bus   ),
    //to ws
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //from data-sram
    .data_sram_rdata(data_sram_rdata),
    .data_sram_data_ok_l(data_sram_data_ok_l),
    .data_sram_data_ok_s(data_sram_data_ok_s),
    .ms_to_ds_inst_no_dest(ms_to_ds_inst_no_dest),
    .ms_to_ds_load_op(ms_to_ds_load_op),
    //the reg address for id stage
    .ms_forward_reg  (ms_forward_reg),
    .ms_ex           (ms_ex),
    .ms_reflush      (ws_reflush),
    .ms_csr_re       (ms_csr_re),
    .s1_found         (s1_found),
    .s1_index         (s1_index),
    .ms_tlb_forward   (ms_tlb_forward)
);
// WB stage
wb_stage wb_stage(
    .clk            (clk            ),
    .reset          (reset          ),
    //allowin
    .ws_allowin     (ws_allowin     ),
    //from ms
    .ms_to_ws_valid (ms_to_ws_valid ),
    .ms_to_ws_bus   (ms_to_ws_bus   ),
    //to rf: for write back
    .ws_to_rf_bus   (ws_to_rf_bus   ),
    //trace debug interface
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_we   (debug_wb_rf_we   ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata),
    .ws_to_ds_inst_no_dest(ws_to_ds_inst_no_dest),
    //the reg address for id stage
    .ws_forward_reg(ws_forward_reg),
    .ws_ex            (ws_ex),
    .ertn_flush       (ertn_flush),
    .ws_reflush       (ws_reflush),
    .ws_to_csr_bus    (ws_to_csr_bus),
    .csr_rvalue       (csr_rvalue),
    //exp18
    .r_index          (r_index),
    .tlbrd_we         (tlbrd_we),
    .csr_tlbidx_index (csr_tlbidx_index),

    .w_index          (w_index),
    .we               (we),
    
    .tlbsrch_we       (tlbsrch_we),
    .tlbsrch_hit      (tlbsrch_hit),
    .tlbsrch_hit_index(tlbsrch_hit_index),
    .ws_tlb_forward   (ws_tlb_forward)
);

csr u_csr(
    .clk            (clk),
    .reset          (reset),
    .ws_to_csr_bus  (ws_to_csr_bus),
    .ws_ex          (ws_ex),
    .ertn_flush     (ertn_flush),
    .csr_rvalue     (csr_rvalue),
    .ex_entry       (ex_entry),
    .era_entry      (era_entry),
    .has_int        (has_int),

    .csr_asid_asid   (csr_asid_asid),
    .csr_tlbehi_vppn (csr_tlbehi_vppn),
    .csr_tlbidx_index(csr_tlbidx_index),

    .tlbsrch_we        (tlbsrch_we),
    .tlbsrch_hit       (tlbsrch_hit),
    .tlbsrch_hit_index (tlbsrch_hit_index),
    .tlbrd_we          (tlbrd_we),

    .r_tlb_e         (r_e),
    .r_tlb_ps        (r_ps),
    .r_tlb_vppn      (r_vppn),
    .r_tlb_asid      (r_asid),
    .r_tlb_g         (r_g),
    .r_tlb_ppn0      (r_ppn0),
    .r_tlb_plv0      (r_plv0),
    .r_tlb_mat0      (r_mat0),
    .r_tlb_d0        (r_d0),
    .r_tlb_v0        (r_v0),
    .r_tlb_ppn1      (r_ppn1),
    .r_tlb_plv1      (r_plv1),
    .r_tlb_mat1      (r_mat1),
    .r_tlb_d1        (r_d1),
    .r_tlb_v1        (r_v1),

    .w_tlb_e         (w_e),
    .w_tlb_ps        (w_ps),
    .w_tlb_vppn      (w_vppn),
    .w_tlb_asid      (w_asid),
    .w_tlb_g         (w_g),
    .w_tlb_ppn0      (w_ppn0),
    .w_tlb_plv0      (w_plv0),
    .w_tlb_mat0      (w_mat0),
    .w_tlb_d0        (w_d0),
    .w_tlb_v0        (w_v0),
    .w_tlb_ppn1      (w_ppn1),
    .w_tlb_plv1      (w_plv1),
    .w_tlb_mat1      (w_mat1),
    .w_tlb_d1        (w_d1),
    .w_tlb_v1        (w_v1),
    .csr_crmd_rvalue (csr_crmd_rvalue),
    .csr_asid_rvalue (csr_asid_rvalue),
    .csr_dmw0_rvalue (csr_dmw0_rvalue),
    .csr_dmw1_rvalue (csr_dmw1_rvalue)
);

tlb #(.TLBNUM(16)) u_tlb(
    .clk        (clk),
    
    .s0_vppn    (s0_vppn),
    .s0_va_bit12(s0_va_bit12),
    .s0_asid    (s0_asid),
    .s0_found   (s0_found),
    .s0_index   (s0_index),
    .s0_ppn     (s0_ppn),
    .s0_ps      (s0_ps),
    .s0_plv     (s0_plv),
    .s0_mat     (s0_mat),
    .s0_d       (s0_d),
    .s0_v       (s0_v),

    .s1_vppn    (s1_vppn),
    .s1_va_bit12(s1_va_bit12),
    .s1_asid    (s1_asid),
    .s1_found   (s1_found),
    .s1_index   (s1_index),
    .s1_ppn     (s1_ppn),
    .s1_ps      (s1_ps),
    .s1_plv     (s1_plv),
    .s1_mat     (s1_mat),
    .s1_d       (s1_d),
    .s1_v       (s1_v),

    .invtlb_op  (invtlb_op),
    .invtlb_valid(invtlb_valid),
    
    .we         (we),
    .w_index    (w_index),
    .w_e        (w_e),
    .w_vppn     (w_vppn),
    .w_ps       (w_ps),
    .w_asid     (w_asid),
    .w_g        (w_g),

    .w_ppn0     (w_ppn0),
    .w_plv0     (w_plv0),
    .w_mat0     (w_mat0),
    .w_d0       (w_d0),
    .w_v0       (w_v0),

    .w_ppn1     (w_ppn1),
    .w_plv1     (w_plv1),
    .w_mat1     (w_mat1),
    .w_d1       (w_d1),
    .w_v1       (w_v1),

    .r_index    (r_index),
    .r_e        (r_e),
    .r_vppn     (r_vppn),
    .r_ps       (r_ps),
    .r_asid     (r_asid),
    .r_g        (r_g),

    .r_ppn0     (r_ppn0),
    .r_plv0     (r_plv0),
    .r_mat0     (r_mat0),
    .r_d0       (r_d0),
    .r_v0       (r_v0),

    .r_ppn1     (r_ppn1),
    .r_plv1     (r_plv1),
    .r_mat1     (r_mat1),
    .r_d1       (r_d1),
    .r_v1       (r_v1)
);

endmodule

