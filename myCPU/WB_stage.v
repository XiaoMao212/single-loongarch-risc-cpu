`include "mycpu.h"

module wb_stage(
    input                           clk           ,
    input                           reset         ,
    //allowin
    output                          ws_allowin    ,
    //from ms
    input                           ms_to_ws_valid,
    input  [`MS_TO_WS_BUS_WD -1:0]  ms_to_ws_bus  ,
    //to rf: for write back
    output [`WS_TO_RF_BUS_WD -1:0]  ws_to_rf_bus  ,
    //trace debug interface
    output [31:0] debug_wb_pc     ,
    output [ 3:0] debug_wb_rf_we  ,
    output [ 4:0] debug_wb_rf_wnum,
    output [31:0] debug_wb_rf_wdata,

    output ws_to_ds_inst_no_dest,
    //the reg address for id stage
    output [ 36:0] ws_forward_reg,
    output ws_ex,
    output ertn_flush,
    output                          ws_reflush,
    output [`WS_TO_CSR_BUS -1:0] ws_to_csr_bus,
    input [31:0] csr_rvalue,
    //exp18
    input  [ 3:0]                   csr_tlbidx_index, 
    // tlbrd
    output                          tlbrd_we, // to csr
    output [ 3:0]                   r_index,  // to tlb
    // tlbwr and tlbfill
    output [ 3:0]                   w_index,  // to tlb
    output                          we,       // to tlb
    // tlbsrch, to csr
    output                          tlbsrch_we,         // to csr
    output                          tlbsrch_hit,        // to csr
    output [ 3:0]                   tlbsrch_hit_index,  // to csr
    output                          ws_tlb_forward
);

reg         ws_valid;
wire        ws_ready_go;
//wire ws_inst_no_dest;
reg [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus_r;
wire        ws_gr_we;
wire [ 4:0] ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;
//wire [81:0] ws_exception;
wire [128:0] ws_exception;
wire        csr_re;
wire        csr_we;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;
wire [13:0] csr_num;
wire [ 5:0] wb_ecode;
wire [ 8:0] wb_esubcode;
wire         ipi_int_in = 1'b0;
wire [  7:0] hw_int_in  = 8'b0;
wire [ 31:0] wb_vaddr;
wire [ 31:0] core_id    = 32'b0;

wire        ws_inst_tlbsrch;
wire        ws_inst_tlbrd;
wire        ws_inst_tlbwr;
wire        ws_inst_tlbfill;
wire        ws_tlbsrch_hit;
wire [ 3:0] ws_tlbsrch_hit_index;
// tlb random index
reg  [  3:0] rand_idx;

assign {ws_inst_tlbsrch,
        ws_inst_tlbrd,
        ws_inst_tlbwr,
        ws_inst_tlbfill,
        ws_tlbsrch_hit,
        ws_tlbsrch_hit_index,
        //ws_inst_no_dest    ,
        ws_gr_we       ,  //69:69
        ws_dest        ,  //68:64
        ws_final_result,  //63:32
        ws_pc          ,   //31:0
        ws_exception
       } = ms_to_ws_bus_r;

wire        rf_we;
wire [4 :0] rf_waddr;
wire [31:0] rf_wdata;
assign ws_to_rf_bus = {rf_we   ,  //37:37
                       rf_waddr,  //36:32
                       rf_wdata   //31:0
                      };

assign ws_ready_go = 1'b1;
assign ws_allowin  = !ws_valid || ws_ready_go;
always @(posedge clk) begin
    if (reset) begin
        ws_valid <= 1'b0;
    end
    else if(ws_ex | ertn_flush) begin
        ws_valid <= 1'b0;
    end
    else if (ws_allowin) begin
        ws_valid <= ms_to_ws_valid;
    end

    if (ms_to_ws_valid && ws_allowin) begin
        ms_to_ws_bus_r <= ms_to_ws_bus;
    end
end

//assign rf_we    = ws_gr_we && ws_valid;
assign rf_we    = ws_gr_we && ws_valid && (~ws_ex);
assign rf_waddr = ws_dest;
//assign rf_wdata = ws_final_result;
assign rf_wdata = csr_re ? csr_rvalue : ws_final_result;
// debug info generate
assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = ws_dest;
//assign debug_wb_rf_wdata = ws_final_result;
assign debug_wb_rf_wdata = csr_re ? csr_rvalue : ws_final_result;

assign ws_forward_reg = {{ws_dest, rf_wdata} & {37{ws_valid}}};
assign ws_to_ds_inst_no_dest = {ws_valid & ~ws_gr_we};

assign ws_reflush = ws_ex | ertn_flush;
assign {csr_re, csr_we, csr_wmask, csr_wvalue, csr_num, ws_ex, ertn_flush, 
        wb_vaddr, wb_ecode, wb_esubcode} = ws_exception & {129{ws_valid}};
assign ws_to_csr_bus = {csr_re, csr_we, csr_wmask, csr_wvalue, csr_num, ws_pc, wb_ecode, wb_esubcode, ipi_int_in, hw_int_in, core_id, wb_vaddr};



/**
    tlb

    @para rand_idx use        this to gengrate an index randomly
    @para tlbrd_we            if the tlb is valid then write write information to csr
    @para r_index             the read tlb's index
    @para w_index             tlb write index
    @para we                  tlb write enable
    @para tlbsrch_we          if the tlb is hit, then write index to csr
    @para tlbsrch_hit         if the tlb is hit or not
    @para tlbsrch_hit_index   the hit's index
    @para ws_tlb_forward      if the tlb happen write-to-read situation
*/
always @ (posedge clk) begin
    if (reset) begin
        rand_idx <= 4'b0;
    end else begin
        rand_idx <= {rand_idx[1:0], 2'b0} + 4'd8; // 4*rand_idx+8 mod 16
    end
end
// tlbrd
assign tlbrd_we = ws_inst_tlbrd;
assign r_index  = csr_tlbidx_index;
// tlbwr and tlbfill
assign w_index  = ws_inst_tlbwr ? csr_tlbidx_index : rand_idx;
assign we       = ws_inst_tlbwr | ws_inst_tlbfill;
// tlbsrch
assign tlbsrch_we        = ws_inst_tlbsrch;
assign tlbsrch_hit       = ws_tlbsrch_hit;
assign tlbsrch_hit_index = ws_tlbsrch_hit_index;          
assign ws_tlb_forward    = ((csr_num == `CSR_ASID || csr_num == `CSR_TLBEHI) && 
                             csr_we || ws_inst_tlbrd ) && ws_valid;//TLBWE,TLBFILL，INVTLB对TLB进行了修改，会出现关于TLB的写后读，不止是关于SRCH指令，还有取指和访存指令的冲突，我们将采用标记重取的方式

endmodule
