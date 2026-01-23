`include "mycpu.h"

module exe_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          ms_allowin    ,
    output                         es_allowin    ,
    //from ds
    input                          ds_to_es_valid,
    input  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to ms
    output                         es_to_ms_valid,
    output [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus  ,
/*
    // data sram interface(write)
    output        data_sram_en   ,
    output [ 3:0] data_sram_we   ,
    output [31:0] data_sram_addr ,
    output [31:0] data_sram_wdata,
    */
    //exp14
    output                         data_sram_en   ,
    output                         data_sram_wr   ,
    output [ 3:0]                  data_sram_we   ,
    output [ 1:0]                  data_sram_size ,
    output [31:0]                  data_sram_addr ,
    output [31:0]                  data_sram_wdata,
    input                          data_sram_addr_ok,
    input  [31:0]                  data_sram_rdata,
    //load op
    output es_to_ds_load_op,
    //store op
    output es_to_ds_inst_no_dest,
    //the reg address for id stage
    output [ 36:0] es_forward_reg,
   // input  [31                 :0] data_sram_rdata,
    input ms_ex,
    //input ws_ex,
    input                          es_reflush,
    output                          es_csr_re,
        // to tlb
    output [19:0]                  s1_va_highbits,
    output [ 9:0]                  s1_asid,
    output                         invtlb_valid,
    output [ 4:0]                  invtlb_op,
    // from csr, used for tlbsrch
    input  [ 9:0]                  csr_asid_asid,
    input  [18:0]                  csr_tlbehi_vppn,
    // the tlb forward signal for tlbsrch
    input                          ms_tlb_forward,
    input                          ws_tlb_forward,
        // from mmu
    input  [ 5:0]                  es_exc_ecode,
    output [31:0]                  va,
    output [ 1:0]                  mmu_en,
    input  [31:0]                  pa,
    input  [ 1:0]                  plv,
    input                          dmw_hit  ,
    output [2:0] exe_need_mem_forward,
    input        ms_need_mem
);

reg         es_valid      ;
wire        es_ready_go   ;
//14
wire        es_need_mem;
reg  [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus_r;

wire [18:0] alu_op      ;
wire [2: 0]  es_load_op;
wire        src1_is_pc;
wire        src2_is_imm;
wire        src2_is_4;
wire        res_from_mem;
wire        dst_is_r1;
wire        gr_we;
wire        es_mem_we;
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] es_pc;
//wire        es_inst_no_dest;
wire [1:0]  es_store_op;
wire        es_inst_tlbsrch;
wire        es_inst_tlbrd;
wire        es_inst_tlbwr;
wire        es_inst_tlbfill;
wire        es_inst_invtlb;
wire [ 4:0] es_invtlb_op;

// Stable Counter
reg  [63:0] counter;

// csr and exception signal
wire [129:0] ds_exception;
wire [128:0] es_exception;
wire [ 1: 0] time_op;
wire [31: 0] es_final_result;
wire         ld_ale;
wire         st_ale;
wire         csr_re;
wire         csr_we;
wire [ 31:0] csr_wmask;
wire [ 31:0] csr_wvalue;
wire [ 13:0] csr_num;
wire         ds_ex;
wire         es_ertn;
wire         es_adef;
wire [ 31:0] ds_wrong_addr;
wire [  5:0] ds_ecode;
wire [  8:0] ds_esubcode;
wire [  8:0] es_esubcode;
wire         es_ex;
wire [  5:0] es_ecode;
wire [ 31:0] es_wrong_addr;
wire [  5:0] es_tlb_ecode;
wire         fs_tlb_ex;
wire         ecode_pil;
wire         ecode_pis;
wire         ecode_pme;


//exp23
wire       es_inst_cacop;
wire [4:0] es_cacop_op;
assign{ fs_tlb_ex,
        alu_op,
        es_load_op,
        es_store_op,
       // es_inst_no_dest,
        src1_is_pc,
        src2_is_imm,
        src2_is_4,
        gr_we,
        es_mem_we,
        dest,
        imm,
        rj_value,
        rkd_value,
        es_pc,
        res_from_mem,
        ds_exception,
        time_op ,
        es_inst_tlbsrch,   //exp18
        es_inst_tlbrd,   
        es_inst_tlbwr,     
        es_inst_tlbfill,   
        es_inst_invtlb,   
        es_invtlb_op  ,
        es_inst_cacop
       } = ds_to_es_bus_r;
//exp23
assign  es_cacop_op = es_invtlb_op;
wire es_ipe;
assign es_ipe = (es_inst_cacop) & (plv != 2'd0);


wire [31:0] alu_src1   ;
wire [31:0] alu_src2   ;
wire [31:0] alu_result ;
wire [31:0] alu_res    ;


//assign es_inst_no_dest = ~gr_we;


assign es_to_ms_bus ={es_adem,
                       es_tlb_ecode, 
                       es_inst_tlbsrch,
                       es_inst_tlbrd,
                       es_inst_tlbwr,
                       es_inst_tlbfill,
                        es_mem_we,
                        es_load_op,
                     //  es_inst_no_dest,
                       res_from_mem,  //70:70 1
                       gr_we       ,  //69:69 1
                       dest        ,  //68:64 5
                       es_final_result,  //63:32 32
                       es_pc       ,    //31:0  32
                       es_exception,
                       es_inst_cacop,
                       es_cacop_op
                      };

assign tlbsrch_blk    = es_inst_tlbsrch & (ms_tlb_forward | ws_tlb_forward);
//assign s1_va_highbits = invtlb_valid ? rkd_value[31:12] : {csr_tlbehi_vppn, 1'b0};
//assign s1_asid        = invtlb_valid ? rj_value [ 9: 0] : csr_asid_asid;
assign s1_va_highbits = es_need_mem ? alu_result[31:12] : invtlb_valid ? rkd_value[31:12] : {csr_tlbehi_vppn, 1'b0};
assign s1_asid        = (es_need_mem | ~es_need_mem & ~invtlb_valid) ? csr_asid_asid : rj_value[9:0];
assign invtlb_valid   = es_inst_invtlb;
assign invtlb_op      = es_invtlb_op;

//dout_tvalid为1时，除法运算完成
//assign es_ready_go    = inst_is_div ? (dout_tvalid | doutu_tvalid) : 1'b1;
assign es_allowin     = !es_valid || es_ready_go && ms_allowin  ;
assign es_to_ms_valid =  es_valid && es_ready_go && (~es_reflush);
always @(posedge clk) begin
    if (reset) begin
        es_valid <= 1'b0;
    end
    else if (es_allowin) begin
        es_valid <= ds_to_es_valid;
    end

    if (ds_to_es_valid && es_allowin) begin
        ds_to_es_bus_r <= ds_to_es_bus;
    end
end


assign alu_src1 = src1_is_pc  ? es_pc  : rj_value;
assign alu_src2 = src2_is_imm ? imm : rkd_value;

alu u_alu(
    .alu_op     (alu_op    ),
    .alu_src1   (alu_src1  ),
    .alu_src2   (alu_src2  ),
    .alu_result (alu_res)
    );
wire [31:0] div_result;
wire        inst_is_div;
assign alu_result = inst_is_div ? div_result : alu_res;

wire [31:0] st_b_result;
wire [31:0] st_h_result;
wire [ 3:0] st_b;
wire [ 3:0] st_h;
//assign st_b_result = alu_result[1:0] == 2'b00 ? {data_sram_rdata[31:8], rkd_value[7:0]} :
//                     alu_result[1:0] == 2'b01 ? {data_sram_rdata[31:16], rkd_value[7:0], data_sram_rdata[7:0]} :
 //                    alu_result[1:0] == 2'b10 ? {data_sram_rdata[31:24], rkd_value[7:0], data_sram_rdata[15:0]} :
 //                    {rkd_value[7:0], data_sram_rdata[23:0]} ;
//assign st_h_result = alu_result[1:0] == 2'b00 ? {data_sram_rdata[31:16], rkd_value[15:0]} :
 //                    {rkd_value[15:0], data_sram_rdata[15:0]} ;
assign st_b_result     = {4{rkd_value[ 7:0]}};
assign st_h_result     = {2{rkd_value[15:0]}};
assign st_b            = alu_result[1:0] == 2'b00 ? 4'b0001 :
                         alu_result[1:0] == 2'b01 ? 4'b0010 :
                         alu_result[1:0] == 2'b10 ? 4'b0100 : 4'b1000;
assign st_h            = alu_result[1:0] == 2'b00 ? 4'b0011 : 4'b1100;
//assign data_sram_en    = 1'b1;
//assign data_sram_we    = es_mem_we && es_valid ? 4'hf : 4'h0;
/*
assign data_sram_we    = es_mem_we && (es_valid & ~ms_ex & ~es_reflush & ~st_ale) ? 
                        (es_store_op == 2'b01 ? st_b : (es_store_op == 2'b10 ? st_h : 4'hf)) : 4'h0;
assign data_sram_addr  = alu_result;
assign data_sram_wdata = es_store_op == 2'b01 ? st_b_result :
                         es_store_op == 2'b10 ? st_h_result : rkd_value;
                         */

assign es_to_ds_load_op = es_load_op == 3'b000 ? {es_valid & 1'b0} : {es_valid & 1'b1};
assign es_to_ds_inst_no_dest = {es_valid & ~gr_we};
assign es_forward_reg = {{dest, alu_result} & {37{es_valid}}}; 

reg signed_valid_control;
reg unsigned_valid_control;
always @(posedge clk) begin
    if(reset) begin
        signed_valid_control <= 1'b0;
    end
    else if(inst_is_div & dividend_tready & divisor_tready) begin
        signed_valid_control <= 1'b1;
    end
    else if(es_valid & es_allowin) begin
        signed_valid_control <= 1'b0;
    end
end

always @(posedge clk) begin
    if(reset) begin
        unsigned_valid_control <= 1'b0;
    end
    else if(inst_is_div & dividendu_tready & divisoru_tready) begin
        unsigned_valid_control <= 1'b1;
    end
    else if(es_valid & es_allowin) begin
        unsigned_valid_control <= 1'b0;
    end
end

//division
wire [31:0] divisor_tdata;
wire        divisor_tready;
wire        divisor_tvalid;
wire        divisoru_tready;
wire        divisoru_tvalid;
//琚櫎鏁?
wire [31:0] dividend_tdata;
wire        dividend_tready;
wire        dividend_tvalid;
wire        dividendu_tready;
wire        dividendu_tvalid;
//鍟嗗拰浣欐暟
wire         dout_tvalid;
wire  [63:0] dout_tdata;
wire         doutu_tvalid;
wire  [63:0] doutu_tdata;
assign inst_is_div = alu_op[15] | alu_op[16] | alu_op[17] | alu_op[18];
assign divisor_tdata   = alu_src2;
assign dividend_tdata  = alu_src1;

assign divisor_tvalid   = es_valid & (alu_op[15] | alu_op[16]) & inst_is_div & (~signed_valid_control);
assign dividend_tvalid  = es_valid & (alu_op[15] | alu_op[16]) & inst_is_div & (~signed_valid_control);

assign divisoru_tvalid  = es_valid & (alu_op[17] | alu_op[18]) & inst_is_div & (~unsigned_valid_control);
assign dividendu_tvalid = es_valid & (alu_op[17] | alu_op[18]) & inst_is_div & (~unsigned_valid_control);

assign div_result =  alu_op[15] ? {dout_tdata[63:32]  & {32{dout_tvalid}}}  :
                     alu_op[16] ? {dout_tdata[31: 0]  & {32{dout_tvalid}}}  :
                     alu_op[17] ? {doutu_tdata[63:32] & {32{doutu_tvalid}}} : {doutu_tdata[31:0] & {32{doutu_tvalid}}};


//division
my_div my_div(
    .aclk(clk),
    .s_axis_divisor_tdata  (divisor_tdata  ),
    .s_axis_divisor_tready (divisor_tready ),
    .s_axis_divisor_tvalid (divisor_tvalid ),
    .s_axis_dividend_tdata (dividend_tdata ),
    .s_axis_dividend_tready(dividend_tready),
    .s_axis_dividend_tvalid(dividend_tvalid),
    .m_axis_dout_tdata     (dout_tdata     ),
    .m_axis_dout_tvalid    (dout_tvalid    )
);

my_divu my_divu(
    .aclk(clk),
    .s_axis_divisor_tdata  (divisor_tdata   ),
    .s_axis_divisor_tready (divisoru_tready ),
    .s_axis_divisor_tvalid (divisoru_tvalid ),
    .s_axis_dividend_tdata (dividend_tdata  ),
    .s_axis_dividend_tready(dividendu_tready),
    .s_axis_dividend_tvalid(dividendu_tvalid),
    .m_axis_dout_tdata     (doutu_tdata     ),
    .m_axis_dout_tvalid    (doutu_tvalid    )
);

wire es_adem;
assign es_csr_re = csr_re & es_valid & gr_we;


assign {csr_re, csr_we, csr_wmask, csr_wvalue, csr_num, ds_ex, es_ertn, 
        es_adef, ds_wrong_addr, ds_ecode, ds_esubcode} = ds_exception;
assign ld_ale  =  (es_load_op == 3'b011) & alu_result[0]   //load_h
                | (es_load_op == 3'b100) & alu_result[0]                  
                | (es_load_op == 3'b101) & (alu_result[1] | alu_result[0]); //load_w       
assign st_ale  =  (es_store_op == 2'b10) & alu_result[0]           //store_h           
                | (es_store_op == 2'b11) & (alu_result[1] | alu_result[0]);  //store_w
assign es_ale  = ld_ale | st_ale;
assign es_adem = es_need_mem & alu_result[31] & (plv == 2'd3) & ~(dmw_hit);//AI说是用户态地址试图访问内核地址空间
assign es_wrong_addr = (es_adef || fs_tlb_ex) ? ds_wrong_addr : alu_result;//传递adef指令是为了方便判断wrong_addr，后续csr可以通过一级编码二级编码判断adef异常，所以不需要再传这个信号了
assign es_ecode      = ds_ex    ? ds_ecode
                     : es_adem  ? `ECODE_ADE
                     : es_ale   ? `ECODE_ALE
                     : es_tlb_ecode[0] ? `ECODE_TLBR
                     : es_tlb_ecode[5] ? `ECODE_PIL
                     : es_tlb_ecode[4] ? `ECODE_PIS
                     : es_tlb_ecode[1] ? `ECODE_PPI
                     : es_tlb_ecode[2] ? `ECODE_PME
                     : es_ipe  ?  `ECODE_IPE  //exp23
                     : 6'h0;
assign es_esubcode   =  es_adem ? `ESUBCODE_ADEM : ds_esubcode;
assign es_ex         = (ds_ex | es_ale | es_adem | (|es_tlb_ecode)) & es_valid;
assign es_exception  = {csr_re, csr_we, csr_wmask, csr_wvalue, csr_num, es_ex, es_ertn, 
                        es_wrong_addr, es_ecode, es_esubcode};
                        
assign mmu_en         = {{1'b0},{es_need_mem}};
assign ecode_pil      = es_exc_ecode[5] & (res_from_mem|| es_inst_cacop);
assign ecode_pis      = es_exc_ecode[4] & es_mem_we;
assign ecode_pme      = es_exc_ecode[2] & es_mem_we;
assign es_tlb_ecode   = {ecode_pil , ecode_pis, es_exc_ecode[3] , ecode_pme , es_exc_ecode[1] , es_exc_ecode[0]} & {6{es_need_mem}};
assign va             = alu_result;
always @(posedge clk) begin
    if (reset)
        counter <= 64'b0;
    else 
        counter <= counter + 1'b1;
end
assign es_final_result  = {32{time_op[0]}}                & counter[31: 0]
                        | {32{time_op[1]}}                & counter[63:32]
                        | {32{~time_op[0] & ~time_op[1]}} & alu_result;
                        
//exp14
assign es_need_mem    = es_valid && (res_from_mem || es_mem_we || es_inst_cacop && es_cacop_op[4:3] == 2'b10) ;
assign es_esubcode   =  es_adem ? `ESUBCODE_ADEM : ds_esubcode;
//assign es_ex         = (ds_ex | es_ale | es_adem | (|es_tlb_ecode)) & es_valid;
//exp22
assign es_ready_go = es_reflush ? 1 :
                     es_need_mem ? (data_sram_en && data_sram_addr_ok && !tlbsrch_blk || es_ex || tlbsrch_blk || es_inst_cacop) :
                     inst_is_div ? (dout_tvalid | doutu_tvalid) : (es_valid && !tlbsrch_blk); 

//exp22   
assign data_sram_en    = ms_allowin && es_need_mem && ~ms_ex && ~es_reflush && ~es_ex  && ~tlbsrch_blk && !es_inst_cacop;
assign data_sram_we    = es_mem_we && (es_valid & ~ms_ex & ~es_reflush & ~st_ale & ~(|es_tlb_ecode)) ? 
                        (es_store_op == 2'b01 ? st_b : (es_store_op == 2'b10 ? st_h : 4'hf)) : 4'h0;
assign data_sram_addr  = pa;
assign data_sram_wdata = es_store_op == 2'b01 ? st_b_result :
                         es_store_op == 2'b10 ? st_h_result : rkd_value;
assign data_sram_size  = (es_store_op == 2'b01 | es_load_op == 3'b001 | es_load_op == 3'b010) ? 2'b00   // load b, bu or store b
                       : (es_store_op == 2'b10 | es_load_op == 3'b011 | es_load_op == 3'b100) ? 2'b01   // load h, hu or store h
                       : 2'b10;
assign data_sram_wr    =  |es_store_op;                        


assign exe_need_mem_forward = {es_need_mem & es_valid, data_sram_addr_ok, data_sram_en};
                                           
endmodule
