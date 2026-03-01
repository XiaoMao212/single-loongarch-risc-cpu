`include "mycpu.h"

module mem_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ws_allowin    ,
    output                         ms_allowin    ,
    //from es
    input                          es_to_ms_valid,
    input  [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
    //to ws
    output                         ms_to_ws_valid,
    output [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus  ,
    
    //from data-sram
    input  [31                 :0] data_sram_rdata,
    //exp14
    input                          data_sram_data_ok_l,
    input                          data_sram_data_ok_s,    

    output ms_to_ds_inst_no_dest,
    output ms_to_ds_load_op,
    //the reg address for id stage
    output [ 36:0] ms_forward_reg,
    output ms_ex,
    //input  ws_ex,
    input                          ms_reflush,
    output                          ms_csr_re,
    // for tlb
    input                          s1_found,   // from tlb
    input  [ 3:0]                  s1_index,   // from tlb
    output                         ms_tlb_forward ,
    //exp23
    // [新增] CACOP 接口 (连接到 mycpu_core/top)
    output                         ms_cacop_req_i,   // 请求 I-Cache
    output                         ms_cacop_req_d,   // 请求 D-Cache
    output [ 4:0]                  ms_cacop_op_code, // CACOP 操作码
    output [31:0]                  ms_cacop_addr,    // CACOP 操作地址 (虚地址)
    input                          icache_cacop_done,// I-Cache 完成信号
    input                          dcache_cacop_done, // D-Cache 完成信号
    output                         ms_need_mem
    
);
//wire        ms_need_mem;
wire        ms_mem_we ;
reg         ms_valid;
wire        ms_ready_go;

reg [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus_r;
wire        ms_res_from_mem;
wire        ms_gr_we;
wire [ 4:0] ms_dest;
wire [31:0] ms_alu_result;
wire [31:0] ms_pc;

wire [31:0] mem_result;
wire [31:0] ms_final_result;
//wire ms_inst_no_dest;
wire [2: 0] ms_load_op;
//wire [81:0] ms_exception;
wire [128:0] ms_exception;

wire         ms_inst_tlbsrch;
wire         ms_inst_tlbrd;
wire         ms_inst_tlbwr;
wire         ms_inst_tlbfill;
// TLB search result
wire        ms_tlbsrch_hit;
wire [ 3:0] ms_tlbsrch_hit_index;
wire         csr_re;
wire         csr_we;
wire [ 31:0] csr_wmask;
wire [ 31:0] csr_wvalue;
wire [ 13:0] csr_num;
wire         es_ex;
wire         es_ertn;
wire [ 31:0] ms_wrong_addr;
wire [  5:0] ms_ecode;
wire [  8:0] ms_esubcode;
wire [  5:0] ms_exc_ecode;
wire        ms_adem;

//exp 23
wire   ms_inst_cacop;
wire [ 4:0] ms_cacop_op;

assign {ms_adem,
        ms_exc_ecode,
        ms_inst_tlbsrch,
        ms_inst_tlbrd,
        ms_inst_tlbwr,
        ms_inst_tlbfill,
        ms_mem_we      ,
         ms_load_op     ,
       // ms_inst_no_dest    ,
        ms_res_from_mem,  //70:70
        ms_gr_we       ,  //69:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        ms_pc         ,    //31:0
        ms_exception   ,
        ms_inst_cacop   ,
        ms_cacop_op
       } = es_to_ms_bus_r;

assign ms_to_ws_bus = {ms_inst_tlbsrch,
                       ms_inst_tlbrd,
                       ms_inst_tlbwr,
                       ms_inst_tlbfill,
                       ms_tlbsrch_hit,
                       ms_tlbsrch_hit_index,
                        //ms_inst_no_dest    ,
                       ms_gr_we       ,  //69:69
                       ms_dest        ,  //68:64
                       ms_final_result,  //63:32
                       ms_pc          ,   //31:0
                       ms_exception
                      };

//assign ms_ready_go    = 1'b1;
assign ms_allowin     = !ms_valid || ms_ready_go && ws_allowin;
assign ms_to_ws_valid = ms_valid && ms_ready_go&& (~ms_reflush);
always @(posedge clk) begin
    if (reset) begin
        ms_valid <= 1'b0;
    end
    else if (ms_allowin) begin
        ms_valid <= es_to_ms_valid;
    end

    if (es_to_ms_valid && ms_allowin) begin
        es_to_ms_bus_r  = es_to_ms_bus;
    end
end
wire [7 :0] ld_b_result;
wire [15:0] ld_h_result;
//取需要的内容
assign ld_b_result = ms_alu_result[1:0] == 2'b00 ? data_sram_rdata[ 7: 0] :
                     ms_alu_result[1:0] == 2'b01 ? data_sram_rdata[15: 8] :
                     ms_alu_result[1:0] == 2'b10 ? data_sram_rdata[23:16] : data_sram_rdata[31:24];
assign ld_h_result = ms_alu_result[1:0] == 2'b00 ? data_sram_rdata[15: 0] : data_sram_rdata[31:16];
//32位扩展
assign mem_result   = ms_load_op == 3'b001 ? {{24{ld_b_result[7]}}, ld_b_result} :
                      ms_load_op == 3'b010 ? {24'b0, ld_b_result} :
                      ms_load_op == 3'b011 ? {{16{ld_h_result[15]}}, ld_h_result}:
                      ms_load_op == 3'b100 ? {16'b0, ld_h_result} : data_sram_rdata;

assign ms_final_result = ms_res_from_mem ? mem_result : ms_alu_result;

assign ms_forward_reg = {{ms_dest, ms_final_result} & {37{ms_valid}}};
assign ms_to_ds_inst_no_dest = {ms_valid & ~ms_gr_we};
assign ms_ex = (ms_exception[48] | ms_exception[47]) & ms_valid;
assign ms_csr_re = ms_exception[128] & ms_valid;

//exp14
assign ms_need_mem    = ms_valid && (ms_res_from_mem || ms_mem_we);
//exp22
//assign ms_ready_go    = ms_res_from_mem && (data_sram_data_ok_l || (|ms_exc_ecode) || ms_adem || ms_ex)  || ~ms_need_mem || ms_mem_we && (data_sram_data_ok_s || (|ms_exc_ecode) || ms_adem || ms_ex)  ;

assign ms_to_ds_load_op=  ms_load_op != 3'b000 && (~data_sram_data_ok_l);


assign {csr_re, csr_we, csr_wmask, csr_wvalue, csr_num, es_ex, es_ertn, 
                       ms_wrong_addr, ms_ecode, ms_esubcode} = ms_exception;
assign ms_tlbsrch_hit       = s1_found;
assign ms_tlbsrch_hit_index = s1_index;
assign ms_tlb_forward       = ((csr_num == `CSR_ASID || csr_num == `CSR_TLBEHI) && 
                                csr_we || ms_inst_tlbrd ) && ms_valid;
                                
//exp23
// [新增] CACOP 控制逻辑

wire cacop_target_i = (ms_cacop_op[2:0] == 3'b000);
wire cacop_target_d = (ms_cacop_op[2:0] == 3'b001);

// 输出请求信号：必须有效、无异常、无刷新
assign ms_cacop_req_i = ms_valid && ms_inst_cacop && cacop_target_i && !ms_ex && !ms_reflush;
assign ms_cacop_req_d = ms_valid && ms_inst_cacop && cacop_target_d && !ms_ex && !ms_reflush;

// 输出操作码
//地址来自TLB的虚拟地址
assign ms_cacop_op_code = ms_cacop_op;

// [新增] CACOP 正在进行且未完成时，需要 Stall
wire cacop_stall;
assign cacop_stall =  ms_inst_cacop && !ms_ex && !ms_reflush && (
    (cacop_target_i && !icache_cacop_done) || 
    (cacop_target_d && !dcache_cacop_done)
);

assign ms_ready_go    = ms_res_from_mem && (data_sram_data_ok_l || (|ms_exc_ecode) || ms_adem || ms_ex)  
                        || (~ms_need_mem && ~ms_inst_cacop) || ms_mem_we && (data_sram_data_ok_s || (|ms_exc_ecode) || ms_adem || ms_ex) 
                        || ms_inst_cacop && !cacop_stall ;
assign ms_cacop_addr    = ms_alu_result;
endmodule
