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
    input         data_sram_data_ok,
    // trace debug interface
    output [31:0] debug_wb_pc,
    output [ 3:0] debug_wb_rf_we,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata
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
wire ertn_flush;
wire [31:0] csr_rvalue;
wire [31:0] ex_entry;
wire [31:0] era_entry;
wire es_csr_re;
wire ms_csr_re;
wire ws_reflush;
wire has_int;
wire es_to_ds_inst_no_dest;
wire ms_to_ds_inst_no_dest;
wire ws_to_ds_inst_no_dest;

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
    .fs_reflush     (ws_reflush)
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
    .es_csr_re(es_csr_re)
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
    .data_sram_data_ok(data_sram_data_ok),
    .ms_to_ds_inst_no_dest(ms_to_ds_inst_no_dest),
    .ms_to_ds_load_op(ms_to_ds_load_op),
    //the reg address for id stage
    .ms_forward_reg  (ms_forward_reg),
    .ms_ex           (ms_ex),
    .ms_reflush      (ws_reflush),
    .ms_csr_re       (ms_csr_re)
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
    .csr_rvalue       (csr_rvalue)
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
    .has_int        (has_int)
);

endmodule
