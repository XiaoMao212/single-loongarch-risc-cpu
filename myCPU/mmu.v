`include "mycpu.h"

module MMU(
    input wire  [1:0]                 flag,//10:inst;01:data
    input wire  [31:0]                csr_crmd_rvalue,
    input wire  [31:0]                csr_asid_rvalue,
    input wire  [31:0]                csr_dmw0_rvalue,
    input wire  [31:0]                csr_dmw1_rvalue,

    // from tlb
    input  wire                       s_found,
    input  wire [ 3:0]                s_index,
    input  wire [19:0]                s_ppn,
    input  wire [ 5:0]                s_ps,
    input  wire [ 1:0]                s_plv,
    input  wire [ 1:0]                s_mat,
    input  wire                       s_d,
    input  wire                       s_v, 

    //interface 
    input  wire [31:0]               va,
    output wire [ 5:0]               exc_ecode,
    output wire                      dmw_hit,
    output wire [ 1:0]               plv,//10:adef,01:adem
    output wire [31:0]               pa,
    output wire [ 9:0]               s_asid,
    output wire                      uncached,
    output wire                      tlb_excp_cancel_req
);

wire        csr_crmd_da;
wire        csr_crmd_pg;
wire [1:0]  csr_crmd_plv;
wire [9:0]  csr_asid_asid;

assign csr_crmd_pg   = csr_crmd_rvalue[`CSR_CRMD_PG  ]; 
assign csr_crmd_da   = csr_crmd_rvalue[`CSR_CRMD_DA  ]; 
assign csr_crmd_plv  = csr_crmd_rvalue[`CSR_CRMD_PLV ]; 
assign csr_asid_asid = csr_asid_rvalue[`CSR_ASID_ASID]; 

wire        direct; 
wire        dmw_hit0  ;
wire        dmw_hit1  ;
wire [31:0] dmw_paddr0;
wire [31:0] dmw_paddr1;
wire [31:0] tlb_paddr ;
wire        tlb_trans;
wire        ecode_pil ; 
wire        ecode_pis ;
wire        ecode_pif ;
wire        ecode_pme ;
wire        ecode_ppi ;
wire        ecode_tlbr;

/**
直接地址翻译
*/
assign direct = csr_crmd_da & ~csr_crmd_pg;


//直接地址映射是否命中
assign dmw_hit0 = csr_dmw0_rvalue[csr_crmd_plv] && (csr_dmw0_rvalue[31:29] == va[31:29]); 
assign dmw_hit1 = csr_dmw1_rvalue[csr_crmd_plv] && (csr_dmw1_rvalue[31:29] == va[31:29]);
assign dmw_paddr0 = {csr_dmw0_rvalue[`CSR_DMW_PSEG], va[28:0]}; 
assign dmw_paddr1 = {csr_dmw1_rvalue[`CSR_DMW_PSEG], va[28:0]}; 
/**
直接地址映射未命中并且当前不是直接地址翻译模式
*/
assign tlb_trans = ~dmw_hit0 & ~dmw_hit1 & ~direct;
assign tlb_paddr = (s_ps == 6'd12) ? {s_ppn[19:0], va[11:0]} : {s_ppn[19:10], va[21:0]};

/**
TLB相关例外?
*/
assign ecode_pif  = flag[0] ? 1'b0 : tlb_trans & ~s_v;                     // 取指操作页无效
assign ecode_ppi  = tlb_trans & ((csr_crmd_plv > s_plv)); // 页特权等级不合规
assign ecode_tlbr = tlb_trans & ~s_found;                 // TLB重填例外
assign ecode_pil  = flag[1] ? 1'b0 : tlb_trans & ~s_v;    // load?操作页无效
assign ecode_pis  = flag[1] ? 1'b0 : tlb_trans & ~s_v;    // store?操作页无效
assign ecode_pme  = flag[1] ? 1'b0 : tlb_trans & ~s_d;    // 页修改例外?


//TODO:if it is direct ,it should also consider the error inst!
assign exc_ecode = direct ? 6'b0 : {ecode_pil, ecode_pis, ecode_pif, ecode_pme, ecode_ppi, ecode_tlbr};
//assign tlb_excp_cancel_req = ecode_tlbr || ecode_pil || ecode_pis || ecode_ppi || ecode_pme;
assign tlb_excp_cancel_req = 1'b0;
//paddr最后物理地址确定
assign pa = ({32{direct}} & va) | 
            ({32{~direct & dmw_hit0}} & dmw_paddr0) | 
            ({32{~direct & ~dmw_hit0 & dmw_hit1}} & dmw_paddr1) | 
            ({32{~direct & ~dmw_hit0 & ~dmw_hit1}} & tlb_paddr);
                  
assign s_asid  = csr_asid_asid;
assign dmw_hit = dmw_hit0 | dmw_hit1;
assign plv     = csr_crmd_plv;

wire [1:0] mat_result;

// 逻辑：
// 1. direct 模式下：如果命中 DMW0/1，取对应的 MAT 位；如果都没命中，默认为 0 (Uncached)
// 2. TLB 模式下：取 s_mat
/*
assign mat_result = direct ? 2'b0:(dmw_hit0 ? csr_dmw0_rvalue[`CSR_DMW_MAT] : 
                              dmw_hit1 ? csr_dmw1_rvalue[`CSR_DMW_MAT] : 
                              s_mat); // 复位或物理地址模式默认 Uncached
*/
assign mat_result = direct ? 2'b0 : (
                      dmw_hit0 ? csr_dmw0_rvalue[`CSR_DMW_MAT] : 
                      dmw_hit1 ? csr_dmw1_rvalue[`CSR_DMW_MAT] : 
                      (s_found ? s_mat : 2'b0) // <--- 关键修改：加了 s_found 判断
                    );              

assign uncached = (mat_result == 2'd0); 
//assign uncached = 0; 
endmodule
