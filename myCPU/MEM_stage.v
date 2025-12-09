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
    input                          data_sram_data_ok,

    output ms_to_ds_inst_no_dest,
    output ms_to_ds_load_op,
    //the reg address for id stage
    output [ 36:0] ms_forward_reg,
    output ms_ex,
    //input  ws_ex,
    input                          ms_reflush,
    output ms_csr_re
);
wire        ms_need_mem;
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
assign {ms_mem_we      ,
         ms_load_op     ,
       // ms_inst_no_dest    ,
        ms_res_from_mem,  //70:70
        ms_gr_we       ,  //69:69
        ms_dest        ,  //68:64
        ms_alu_result  ,  //63:32
        ms_pc         ,    //31:0
        ms_exception
       } = es_to_ms_bus_r;

assign ms_to_ws_bus = {//ms_inst_no_dest    ,
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
assign ms_ready_go    = ms_need_mem && data_sram_data_ok || ~ms_need_mem;

assign ms_to_ds_load_op=  ms_load_op != 3'b000 && (~data_sram_data_ok);

endmodule
