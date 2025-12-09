`include "mycpu.h"

module csr (
	input		            	clk,
	input		               	reset,

    input  [`WS_TO_CSR_BUS -1:0] ws_to_csr_bus,
    input           ws_ex,
    input           ertn_flush,
	output [31:0]	csr_rvalue,	// value read
	output [31:0]   ex_entry, 	// exception entry
    output [31:0]   era_entry,
    output          has_int ,
     // exp18
    output [ 9:0]      csr_asid_asid,
    output [18:0]      csr_tlbehi_vppn,
    output [ 3:0]      csr_tlbidx_index,

    input  tlbsrch_we,
    input  tlbsrch_hit,
    input  tlbrd_we,
    input  [ 3:0]      tlbsrch_hit_index,
    
    input               r_tlb_e,
    input  [ 5:0]      r_tlb_ps,
    input  [18:0]      r_tlb_vppn,
    input  [ 9:0]      r_tlb_asid,
    input               r_tlb_g,

    input  [19:0]      r_tlb_ppn0,
    input  [ 1:0]      r_tlb_plv0,
    input  [ 1:0]      r_tlb_mat0,
    input               r_tlb_d0,
    input               r_tlb_v0,

    input   [19:0]      r_tlb_ppn1,
    input   [ 1:0]      r_tlb_plv1,
    input   [ 1:0]      r_tlb_mat1,
    input               r_tlb_d1,
    input               r_tlb_v1,

    output             w_tlb_e,
    output [ 5:0]      w_tlb_ps,
    output [18:0]      w_tlb_vppn,
    output [ 9:0]      w_tlb_asid,
    output             w_tlb_g,

    output [19:0]      w_tlb_ppn0,
    output [ 1:0]      w_tlb_plv0,
    output [ 1:0]      w_tlb_mat0,
    output             w_tlb_d0,
    output             w_tlb_v0,

    output [19:0]      w_tlb_ppn1,
    output [ 1:0]      w_tlb_plv1,
    output [ 1:0]      w_tlb_mat1,
    output             w_tlb_d1,
    output             w_tlb_v1,
    
    // exp19
    output [31:0]                  csr_crmd_rvalue,
    output [31:0]                  csr_asid_rvalue,
    output [31:0]                  csr_dmw0_rvalue,
    output [31:0]                  csr_dmw1_rvalue 
);

wire        csr_re;
wire        csr_we;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;
wire [13:0] csr_num;
wire [31:0] ws_pc;
wire [ 5:0] wb_ecode;
wire [ 8:0] wb_esubcode;
wire        ipi_int_in;
wire [ 7:0] hw_int_in;
wire [31:0] wb_vaddr;
wire [31:0] coreid;

assign {csr_re, csr_we, csr_wmask, csr_wvalue, csr_num, ws_pc, wb_ecode, 
        wb_esubcode, ipi_int_in, hw_int_in, coreid, wb_vaddr} = ws_to_csr_bus;

// 0x00: CRMD
reg [1:0] csr_crmd_plv;//其值为0～3分别表示CPU正处于PLV0～PLV3四种运行模式
reg       csr_crmd_ie;//触发异常后置0，保证陷入后屏蔽中断
// Wires below haven't been implemented
reg      csr_crmd_da;
reg      csr_crmd_pg;
reg [1:0] csr_crmd_datf;
reg [1:0] csr_crmd_datm;

// 0x01: PRMD
//当触发例外时，硬件会将此时处理器核的特权等级和全局中断使能位保存至例外前模式信息寄存器中，用于例外返回时恢复处理器核的现场。
reg [1:0] csr_prmd_pplv;
reg csr_prmd_pie;

// 0x04: ECFG  Exception ConFiGuration register，即 异常配置寄存器
//局部中断使能位 这些局部中断使能位与 CSR.ESTAT 中 IS 域记录的 13 个中断源一一对应，每一位控制一个中断源。
reg [12:0] csr_ecfg_lie;

// 0x05: ESTAT  Exception Status Register
reg [12:0] csr_estat_is;//中断类型
reg [5: 0] csr_estat_ecode;//一级编码
reg [8: 0] csr_estat_esubcode;//二级编码，通过一级二级编码记录当前发生了什么例外

// 0x06: ERA
//例外程序返回地址
//如果是 TLB 重填例外或机器错误例外，该域保持不变；否则，硬件会将触发例外的指令的 PC 记录到这里。对于 LA64 架构，在这种情况下，如果触发例外的特权等级处于 32 位地址模式，那么记录的 PC 值的高 32 位强制置为0。
reg [31:0] csr_era_pc;

// 0x07: BADV
//当触发地址错误相关例外时，硬件将出错的虚地址记录于此。对于 LA64 架构，在这种情况下，如果触发例外的特权等级处于 32 位地址模式，那么记录的虚地址的高 32位强制置为 0。
//本次实验只涉及到 ADEF 和 ALE
reg [31:0] csr_badv_vaddr;

// 0x0c: EENTRY
//该寄存器用于配置除 TLB 重填例外之外的例外和中断的入口地址，只有 VA 域会被 CSR 指令更新。 
reg [25:0] csr_eentry_va;

// 0x30~0x33: SAVE0~3
//数据保存控制状态寄存器用于给系统软件暂存数据。每个数据保存寄存器可以存放一个通用寄存器的数据。
reg [31:0] csr_save0_data;
reg [31:0] csr_save1_data;
reg [31:0] csr_save2_data;
reg [31:0] csr_save3_data;

// 0x40: TID
//（定时器编号）
reg [31:0] csr_tid_tid;

// 0x41: TCFG
//软件配置定时器的接口，从低到高依次为定时器使能位、循环模式控制位、初始值、只读位。需要支持 CSR 指令的读写，并用对应位控制定时器 TVAL。
reg csr_tcfg_en;
//定时器循环模式控制位。若该位为 1，定时器在倒计时自减至 0 时，在置起定时中断信号的同时，还会自动定时器重新装载成 InitVal 域中配置的初始值，然后再下一个
//时钟周期继续自减。若该位为 0，定时器在倒计时自减至 0 时，将停止计数直至软件再次配置该定时器。
reg csr_tcfg_periodic;
//自减初始值，只能是4的倍数，硬件自动在该域最低位补00
reg [29:0] csr_tcfg_initval;
//只读位恒为0
wire [31:0] csr_tcfg_next_value;

// 0x42: TVAL
//TVAL 存储定时器的值，初值为 TCFG 中的 InitVal 域，在 TCFG 的 En 域为 1 时递减。 减到 0 后，如果 TCFG 的 Periodic 域为 1，则从初始值开始重新倒计时，否则保持不变
wire [31:0] csr_tval_timeval;

// Timer counter
reg [31:0] timer_ymr;

// Stable Counter
reg  [31:0] time_cnt;

wire ws_ex_addr_err;

//exp18
reg [ 9:0] csr_asid_asid;
reg [18:0] csr_tlbehi_vppn;
reg [ 3:0] csr_tlbidx_index;


// TLBIDX
//手册P130
wire [31:0] csr_tlbidx_rvalue;
reg  [ 5:0] csr_tlbidx_ps;
reg         csr_tlbidx_ne;

// TLBEHI
//VPPN
wire [31:0] csr_tlbehi_rvalue;

// TLELO0
wire [31:0] csr_tlbelo0_rvalue;
reg         csr_tlbelo0_v;
reg         csr_tlbelo0_d;
reg  [ 1:0] csr_tlbelo0_plv;
reg  [ 1:0] csr_tlbelo0_mat;
reg         csr_tlbelo0_g;
reg  [23:0] csr_tlbelo0_ppn;

// TLELO1
wire [31:0] csr_tlbelo1_rvalue;
reg         csr_tlbelo1_v;
reg         csr_tlbelo1_d;
reg  [ 1:0] csr_tlbelo1_plv;
reg  [ 1:0] csr_tlbelo1_mat;
reg         csr_tlbelo1_g;
reg  [23:0] csr_tlbelo1_ppn;

// ASID
wire [31:0] csr_asid_rvalue;
//ASID域的位宽
wire [ 7:0] csr_asid_asidbits;

// TLBRENTRY
//该寄存器用于配置 TLB 重填例外的入口地址。由于触发 TLB 重填例外之后，处理器核将进入直接地址翻译模式，所以此处所填入口地址应当是物理地址。
wire [31:0] csr_tlbrentry_rvalue;
reg  [25:0] csr_tlbrentry_pa;

//DMW0-1
reg         csr_dmw0_plv0;
reg         csr_dmw0_plv3;
reg  [ 1:0] csr_dmw0_mat ;
reg  [ 2:0] csr_dmw0_pseg;
reg  [ 2:0] csr_dmw0_vseg;

reg         csr_dmw1_plv0;
reg         csr_dmw1_plv3;
reg  [ 1:0] csr_dmw1_mat ;
reg  [ 2:0] csr_dmw1_pseg;
reg  [ 2:0] csr_dmw1_vseg;

// Value read from CSR.
wire [31:0] rval_crmd, rval_prmd, rval_ecfg, rval_estat, rval_era,
            rval_badv, rval_eentry, rval_save0, rval_save1, rval_save2,
            rval_save3, rval_tid, rval_tcfg, rval_tval, rval_ticlr,
             rval_tlbidx, rval_tlbehi, rval_tlbelo0, rval_tlbelo1,
            rval_asid, rval_tlbrentry, rval_dmw0, rval_dmw1;

//CRMD
always @(posedge clk) begin
    if (reset) begin
        csr_crmd_plv <= 2'd0;
        csr_crmd_ie  <= 1'd0;
    end
    else if (ws_ex) begin
        csr_crmd_plv <= 2'd0;//发生异常特权模式置为0
        csr_crmd_ie  <= 1'd0;
    end
    else if (ertn_flush) begin//退出异常时恢复原有的特权等级
        csr_crmd_plv <= csr_prmd_pplv;
        csr_crmd_ie  <= csr_prmd_pie;
    end
    else if (csr_we && csr_num == `CSR_CRMD) begin
        csr_crmd_plv <= (csr_wmask[`CSR_CRMD_PLV] & csr_wvalue[`CSR_CRMD_PLV])
                        | (~csr_wmask[`CSR_CRMD_PLV] & csr_crmd_plv);
        csr_crmd_ie  <= (csr_wmask[`CSR_CRMD_IE] & csr_wvalue[`CSR_CRMD_IE])
                        | (~csr_wmask[`CSR_CRMD_IE] & csr_crmd_ie);
    end
end

// CRMD: DA, PG, DATF, DATM
always @(posedge clk) begin
    if(reset) begin
        csr_crmd_da   <= 1'd1;
        csr_crmd_pg   <= 1'd0;
        csr_crmd_datf <= 2'd0;
        csr_crmd_datm <= 2'd0;
    end
    else if (ws_ex && wb_ecode == `ECODE_TLBR) begin
        csr_crmd_da <= 1'b1;//发生TLB重填例外转成直接地址翻译模式，防止TLB重填例外套TLB重填例外，因为没寄存器能再保存现场了
        csr_crmd_pg <= 1'b0;
    end
    else if(ertn_flush && csr_estat_ecode == `ECODE_TLBR) begin
        csr_crmd_da   <= 1'b0;//TLB重填例外解决后再转回映射地址翻译模式
        csr_crmd_pg   <= 1'b1;
    end
    else if (csr_we && csr_num == `CSR_CRMD) begin
        csr_crmd_da <= csr_wmask[`CSR_CRMD_DA] & csr_wvalue[`CSR_CRMD_DA] |
                        ~csr_wmask[`CSR_CRMD_DA] & csr_crmd_da;
        csr_crmd_pg <= csr_wmask[`CSR_CRMD_PG] & csr_wvalue[`CSR_CRMD_PG] |
                        ~csr_wmask[`CSR_CRMD_PG] & csr_crmd_pg;
        csr_crmd_datf <= csr_wmask[`CSR_CRMD_DATF] & csr_wvalue[`CSR_CRMD_DATF] |
                        ~csr_wmask[`CSR_CRMD_DATF] & csr_crmd_datf;
        csr_crmd_datm <= csr_wmask[`CSR_CRMD_DATM] & csr_wvalue[`CSR_CRMD_DATM] |
                        ~csr_wmask[`CSR_CRMD_DATM] & csr_crmd_datm;
    end
end

//  PPLV, PIE
always @(posedge clk) begin
    if (ws_ex) begin
        csr_prmd_pplv <= csr_crmd_plv;
        csr_prmd_pie  <= csr_crmd_ie;
    end
    else if (csr_we && csr_num == `CSR_PRMD) begin
        csr_prmd_pplv <= (csr_wmask[`CSR_PRMD_PPLV] & csr_wvalue[`CSR_PRMD_PPLV])
                        | (~csr_wmask[`CSR_PRMD_PPLV] & csr_prmd_pplv);
        csr_prmd_pie  <= (csr_wmask[`CSR_PRMD_PIE] & csr_wvalue[`CSR_PRMD_PIE])
                        | (~csr_wmask[`CSR_PRMD_PIE] & csr_prmd_pie);
    end
end

//  LIE  与 CSR.ESTAT 中 IS 域记录的 13 个中断源一一对应，每一位控制一个中断源。
always @(posedge clk) begin
    if (reset) begin
        csr_ecfg_lie <= 13'd0;
    end
    else if (csr_we && csr_num ==`CSR_ECFG) begin
        csr_ecfg_lie <= csr_wmask[`CSR_ECFG_LIE] & 13'h1bff & csr_wvalue[`CSR_ECFG_LIE]
                        | ~csr_wmask[`CSR_ECFG_LIE] & 13'h1bff & csr_ecfg_lie;
    end
end

// ESTAT IS, Ecode, Esubcode  该寄存器记录例外的状态信息，包括所触发例外的一二级编码，以及各中断的状态。
always @(posedge clk) begin
    // Software interrupt
    if (reset) begin
        csr_estat_is[1:0] <= 2'd0;
    end
    else if (csr_we && csr_num == `CSR_ESTAT) begin
        csr_estat_is[1:0] <= (csr_wmask[`CSR_ESTAT_IS10] & csr_wvalue[`CSR_ESTAT_IS10])
                            | (~csr_wmask[`CSR_ESTAT_IS10] & csr_estat_is[1:0]);
    end
    //Hardware interrupt
    csr_estat_is[9:2] <= hw_int_in;//仅靠硬件中断输入引脚更新
    csr_estat_is[ 10] <= 1'b0;//无效位
    //Timer interrupt

    if(reset) begin
        csr_estat_is[11] <= 1'd0;
    end
    else if(csr_tcfg_en && time_cnt == 32'b0) begin//定时器中断
        csr_estat_is[11] <= 1'd1;
    end
    else if (csr_we && csr_num == `CSR_TICLR && (csr_wmask[`CSR_TICLR_CLR] && csr_wvalue[`CSR_TICLR_CLR])) begin
        csr_estat_is[11] <= 1'd0;
    end
    //IPI interrupt
    csr_estat_is[ 12] <= ipi_int_in;

    if (ws_ex) begin
        csr_estat_ecode    <= wb_ecode;
        csr_estat_esubcode <= wb_esubcode;
    end
end

// ERA: PC
always @(posedge clk) begin
    if (ws_ex) begin
        csr_era_pc <= ws_pc;
    end
    else if (csr_we && csr_num == `CSR_ERA) begin
        csr_era_pc <= (csr_wmask[31:0] & csr_wvalue[31:0])
                    | (~csr_wmask[31:0] & csr_era_pc);
    end
end

// 发生错误的虚拟地址
assign ws_ex_addr_err = ws_ex && (wb_ecode == `ECODE_ADE || wb_ecode == `ECODE_ALE || wb_ecode == `ECODE_PIL
                          || wb_ecode == `ECODE_PIS || wb_ecode == `ECODE_PIF || wb_ecode == `ECODE_PME
                          || wb_ecode == `ECODE_PPI || wb_ecode == `ECODE_TLBR);
always @(posedge clk) begin
    if (ws_ex_addr_err) begin
        csr_badv_vaddr <= (wb_ecode == `ECODE_ADE && wb_esubcode == `ESUBCODE_ADEF)
                        ? ws_pc : wb_vaddr;
    end
    else if (csr_we && csr_num == `CSR_BADV) begin
        csr_badv_vaddr <= csr_wmask[31:0] & csr_wvalue[31:0]
                        | ~csr_wmask[31:0] & csr_badv_vaddr;
    end
end

// EENTRY: VA 发生异常的入口地址
always @(posedge clk) begin
    if (csr_we && (csr_num == `CSR_EENTRY)) begin
        csr_eentry_va <= csr_wmask[`CSR_EENTRY_VA] & csr_wvalue[`CSR_EENTRY_VA]
                        | ~csr_wmask[`CSR_EENTRY_VA] & csr_eentry_va;
    end
end

// SAVE0~3供软件使用的寄存器: Data

always @(posedge clk) begin
    if (csr_we && csr_num == `CSR_SAVE0) begin
        csr_save0_data <= (csr_wmask[31:0] & csr_wvalue[31:0])
                        | (~csr_wmask[31:0] & csr_save0_data);
    end
    if (csr_we && csr_num == `CSR_SAVE1) begin
        csr_save1_data <= (csr_wmask[31:0] & csr_wvalue[31:0])
                        | (~csr_wmask[31:0] & csr_save1_data);
    end
    if (csr_we && csr_num == `CSR_SAVE2) begin
        csr_save2_data <= (csr_wmask[31:0] & csr_wvalue[31:0])
                        | (~csr_wmask[31:0] & csr_save2_data);
    end
    if (csr_we && csr_num == `CSR_SAVE3) begin
        csr_save3_data <= (csr_wmask[31:0] & csr_wvalue[31:0])
                        | (~csr_wmask[31:0] & csr_save3_data);
    end
end


// 恒定计时器的编号ID（计时器在EXE设计）TID
assign coreid = 32'b0;
always @(posedge clk) begin
    if (reset) begin
        csr_tid_tid <= coreid;
    end
    else if (csr_we && csr_num == `CSR_TID) begin
        csr_tid_tid <= csr_wmask[31:0] & csr_wvalue[31:0]
                    | ~csr_wmask[31:0] & csr_tid_tid;
    end
end

// TCFG?: En, Periodic, InitVal
always @(posedge clk) begin
    // En
    if (reset) begin
        csr_tcfg_en <= 1'd0;
    end
    else if (csr_we && csr_num == `CSR_TCFG) begin
        csr_tcfg_en <= csr_wmask[`CSR_TCFG_EN] & csr_wvalue[`CSR_TCFG_EN]
                    | ~csr_wmask[`CSR_TCFG_EN] & csr_tcfg_en;
    end

    // Periodic, InitVal
    if (csr_we && csr_num == `CSR_TCFG) begin
        csr_tcfg_periodic <= csr_wmask[`CSR_TCFG_PERIODIC] & csr_wvalue[`CSR_TCFG_PERIODIC]
                            | ~csr_wmask[`CSR_TCFG_PERIODIC] & csr_tcfg_periodic;
    end
    if (csr_we && csr_num == `CSR_TCFG) begin
        csr_tcfg_initval <= csr_wmask[`CSR_TCFG_INITVAL] & csr_wvalue[`CSR_TCFG_INITVAL]
                            | ~csr_wmask[`CSR_TCFG_INITVAL] & csr_tcfg_initval;
    end
end


// TimeVal
assign csr_tval_timeval = time_cnt[31:0];

// TICLR: CLR （对该bit写1清除时钟中断标记，但不是真的写入）
assign csr_ticlr_clr = 1'b0;

// TCFG
assign csr_tcfg_next_value =  csr_wmask[31:0] & csr_wvalue[31:0]
                        | ~csr_wmask[31:0] & {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en};
// time Counter
always @(posedge clk) begin
    if (reset) begin
        /*
            * timer_ymr being -1 (32'hffffffff) means that either timer
            * hasn't been initialized or it has decreased to 0 and
            * Periodic is not enabled. So it should stop decreasing.
            * Note that the low 2 bits of TCFG::InitVal must be 0, so
            * InitVal cannot be 32'hffffffff.
            */
        time_cnt <= 32'hffffffff;
    end
    
    else if (csr_we && csr_num == `CSR_TCFG && csr_tcfg_next_value[`CSR_TCFG_EN]) begin //要写入计时器的初始值
        time_cnt <= {csr_tcfg_next_value[`CSR_TCFG_INITVAL], 2'd0};
    end

    else if (csr_tcfg_en && time_cnt != 32'hffffffff) begin
        if (time_cnt == 32'd0 && csr_tcfg_periodic) begin
            time_cnt <= {csr_tcfg_initval, 2'd0}; //到0且periodic有效，重新开始计时
        end
        else begin
            time_cnt <= time_cnt - 32'd1;
        end
    end
end

assign rval_crmd	= {23'd0, csr_crmd_datm, csr_crmd_datf, csr_crmd_pg, csr_crmd_da, csr_crmd_ie, csr_crmd_plv};
assign rval_prmd	= {29'd0, csr_prmd_pie, csr_prmd_pplv};
assign rval_ecfg	= {19'd0, csr_ecfg_lie};
assign rval_estat	= {1'd0, csr_estat_esubcode, csr_estat_ecode, 3'd0, csr_estat_is};
assign rval_era		=  csr_era_pc;
assign rval_badv	=  csr_badv_vaddr;
assign rval_eentry	= {csr_eentry_va, 6'd0};
assign rval_save0	=  csr_save0_data;
assign rval_save1	=  csr_save1_data;
assign rval_save2	=  csr_save2_data;
assign rval_save3	=  csr_save3_data;
assign rval_tid     =  csr_tid_tid;
assign rval_tcfg	= {csr_tcfg_initval, csr_tcfg_periodic, csr_tcfg_en};
assign rval_tval	=  csr_tval_timeval;
assign rval_ticlr	=  32'd0;

assign csr_rvalue = {32{csr_num == `CSR_CRMD	}} & rval_crmd
				  | {32{csr_num == `CSR_PRMD	}} & rval_prmd
				  | {32{csr_num == `CSR_ECFG	}} & rval_ecfg
				  | {32{csr_num == `CSR_ESTAT	}} & rval_estat
				  | {32{csr_num == `CSR_ERA	    }} & rval_era
				  | {32{csr_num == `CSR_BADV	}} & rval_badv
				  | {32{csr_num == `CSR_EENTRY  }} & rval_eentry
				  | {32{csr_num == `CSR_SAVE0	}} & rval_save0
				  | {32{csr_num == `CSR_SAVE1	}} & rval_save1
				  | {32{csr_num == `CSR_SAVE2	}} & rval_save2
				  | {32{csr_num == `CSR_SAVE3	}} & rval_save3
				  | {32{csr_num == `CSR_TID	    }} & rval_tid
				  | {32{csr_num == `CSR_TCFG	}} & rval_tcfg
				  | {32{csr_num == `CSR_TVAL	}} & rval_tval
				  | {32{csr_num == `CSR_TICLR	}} & rval_ticlr
				  | {32{csr_num == `CSR_TLBIDX  }} & csr_tlbidx_rvalue
                  | {32{csr_num == `CSR_TLBEHI  }} & csr_tlbehi_rvalue
                  | {32{csr_num == `CSR_TLBELO0 }} & csr_tlbelo0_rvalue
                  | {32{csr_num == `CSR_TLBELO1 }} & csr_tlbelo1_rvalue
                  | {32{csr_num == `CSR_ASID    }} & csr_asid_rvalue
                  | {32{csr_num == `CSR_TLBRENTRY}} & csr_tlbrentry_rvalue
                  | {32{csr_num == `CSR_DMW0    }} & rval_dmw0
                  | {32{csr_num == `CSR_DMW1    }} & rval_dmw1;

wire [31: 0] tlb_ex_entry;
assign tlb_ex_entry = csr_tlbrentry_rvalue;
assign ex_entry  = (wb_ecode == `ECODE_TLBR) ? tlb_ex_entry : rval_eentry;
assign era_entry = rval_era;
//目前只有定时器中断
assign has_int = ((csr_estat_is[12:0] & csr_ecfg_lie[12:0]) != 13'd0) && (csr_crmd_ie == 1'd1);//发生中断

// exp18
// TLBIDX
always @ (posedge clk) begin
    if (reset) begin
        csr_tlbidx_index <= 4'b0;
        csr_tlbidx_ps    <= 6'b0;
        csr_tlbidx_ne    <= 1'b1;
    end else if (tlbrd_we) begin
        if (r_tlb_e)
            csr_tlbidx_ps <= r_tlb_ps;
        else
            csr_tlbidx_ps <= 6'b0;
            csr_tlbidx_ne <= ~r_tlb_e;//两个条件都会执行
    end else if (tlbsrch_we) begin
        csr_tlbidx_index <= tlbsrch_hit ? tlbsrch_hit_index : csr_tlbidx_index;
        csr_tlbidx_ne <= ~tlbsrch_hit;
    end else if (csr_we && csr_num == `CSR_TLBIDX) begin
        csr_tlbidx_index <= csr_wmask[`CSR_TLBIDX_INDEX] & csr_wvalue[`CSR_TLBIDX_INDEX] |
                            ~csr_wmask[`CSR_TLBIDX_INDEX] & csr_tlbidx_index;
        csr_tlbidx_ps <= csr_wmask[`CSR_TLBIDX_PS] & csr_wvalue[`CSR_TLBIDX_PS] |
                        ~csr_wmask[`CSR_TLBIDX_PS] & csr_tlbidx_ps;
        csr_tlbidx_ne <= csr_wmask[`CSR_TLBIDX_NE] & csr_wvalue[`CSR_TLBIDX_NE] |
                        ~csr_wmask[`CSR_TLBIDX_NE] & csr_tlbidx_ne;
    end
end

// TLBEHI
always @ (posedge clk) begin
    if (reset) begin
        csr_tlbehi_vppn <= 19'b0;
    end else if (tlbrd_we) begin
        csr_tlbehi_vppn <= {19{r_tlb_e}} & r_tlb_vppn;
    end else if(wb_ecode == `ECODE_PIL || wb_ecode == `ECODE_PIS || wb_ecode == `ECODE_PIF 
            || wb_ecode == `ECODE_PME || wb_ecode == `ECODE_PPI || wb_ecode == `ECODE_TLBR) begin
        csr_tlbehi_vppn <= wb_vaddr[31:13];
    end else if (csr_we && csr_num == `CSR_TLBEHI) begin
        csr_tlbehi_vppn <= csr_wmask[`CSR_TLBEHI_VPPN] & csr_wvalue[`CSR_TLBEHI_VPPN] |
                            ~csr_wmask[`CSR_TLBEHI_VPPN] & csr_tlbehi_vppn;
    end
end

// TLBELO0 and TLBELO1
always @ (posedge clk) begin
    if (reset | tlbrd_we & ~r_tlb_e) begin
        csr_tlbelo0_v   <= 1'b0;
        csr_tlbelo0_d   <= 1'b0;
        csr_tlbelo0_plv <= 2'b0;
        csr_tlbelo0_mat <= 2'b0;
        csr_tlbelo0_g   <= 1'b0;
        csr_tlbelo0_ppn <= 24'b0;

        csr_tlbelo1_v   <= 1'b0;
        csr_tlbelo1_d   <= 1'b0;
        csr_tlbelo1_plv <= 2'b0;
        csr_tlbelo1_mat <= 2'b0;
        csr_tlbelo1_g   <= 1'b0;
        csr_tlbelo1_ppn <= 24'b0;
    end else if (tlbrd_we && r_tlb_e) begin
        csr_tlbelo0_v   <= r_tlb_v0;
        csr_tlbelo0_d   <= r_tlb_d0;
        csr_tlbelo0_plv <= r_tlb_plv0;
        csr_tlbelo0_mat <= r_tlb_mat0;
        csr_tlbelo0_g   <= r_tlb_g;
        csr_tlbelo0_ppn <= {4'b0, r_tlb_ppn0};

        csr_tlbelo1_v   <= r_tlb_v1;
        csr_tlbelo1_d   <= r_tlb_d1;
        csr_tlbelo1_plv <= r_tlb_plv1;
        csr_tlbelo1_mat <= r_tlb_mat1;
        csr_tlbelo1_g   <= r_tlb_g;
        csr_tlbelo1_ppn <= {4'b0, r_tlb_ppn1};
    end else if (csr_we) begin
        if (csr_num == `CSR_TLBELO0) begin
            csr_tlbelo0_v   <= csr_wmask[`CSR_TLBELO_V]   & csr_wvalue[`CSR_TLBELO_V]   |
                                ~csr_wmask[`CSR_TLBELO_V]   & csr_tlbelo0_v;
            csr_tlbelo0_d   <= csr_wmask[`CSR_TLBELO_D]   & csr_wvalue[`CSR_TLBELO_D]   |
                                ~csr_wmask[`CSR_TLBELO_D]   & csr_tlbelo0_d;
            csr_tlbelo0_plv <= csr_wmask[`CSR_TLBELO_PLV] & csr_wvalue[`CSR_TLBELO_PLV] |
                                ~csr_wmask[`CSR_TLBELO_PLV] & csr_tlbelo0_plv;
            csr_tlbelo0_mat <= csr_wmask[`CSR_TLBELO_MAT] & csr_wvalue[`CSR_TLBELO_MAT] |
                                ~csr_wmask[`CSR_TLBELO_MAT] & csr_tlbelo0_mat;
            csr_tlbelo0_g   <= csr_wmask[`CSR_TLBELO_G]   & csr_wvalue[`CSR_TLBELO_G]   |
                                ~csr_wmask[`CSR_TLBELO_G]   & csr_tlbelo0_g;
            csr_tlbelo0_ppn <= csr_wmask[`CSR_TLBELO_PPN] & csr_wvalue[`CSR_TLBELO_PPN] |
                                ~csr_wmask[`CSR_TLBELO_PPN] & csr_tlbelo0_ppn;
        end else if (csr_num == `CSR_TLBELO1) begin
            csr_tlbelo1_v   <= csr_wmask[`CSR_TLBELO_V]   & csr_wvalue[`CSR_TLBELO_V]   |
                                ~csr_wmask[`CSR_TLBELO_V]   & csr_tlbelo1_v;
            csr_tlbelo1_d   <= csr_wmask[`CSR_TLBELO_D]   & csr_wvalue[`CSR_TLBELO_D]   |
                                ~csr_wmask[`CSR_TLBELO_D]   & csr_tlbelo1_d;
            csr_tlbelo1_plv <= csr_wmask[`CSR_TLBELO_PLV] & csr_wvalue[`CSR_TLBELO_PLV] |
                                ~csr_wmask[`CSR_TLBELO_PLV] & csr_tlbelo1_plv;
            csr_tlbelo1_mat <= csr_wmask[`CSR_TLBELO_MAT] & csr_wvalue[`CSR_TLBELO_MAT] |
                                ~csr_wmask[`CSR_TLBELO_MAT] & csr_tlbelo1_mat;
            csr_tlbelo1_g   <= csr_wmask[`CSR_TLBELO_G]   & csr_wvalue[`CSR_TLBELO_G]   |
                                ~csr_wmask[`CSR_TLBELO_G]   & csr_tlbelo1_g;
            csr_tlbelo1_ppn <= csr_wmask[`CSR_TLBELO_PPN] & csr_wvalue[`CSR_TLBELO_PPN] |
                                ~csr_wmask[`CSR_TLBELO_PPN] & csr_tlbelo1_ppn;
        end
    end
end

// ASID
always @ (posedge clk) begin
    if (reset | tlbrd_we & ~r_tlb_e) begin
        csr_asid_asid <= 10'b0;
    end else if (tlbrd_we && r_tlb_e) begin
        csr_asid_asid <= r_tlb_asid;
    end else if (csr_we && csr_num == `CSR_ASID) begin
        csr_asid_asid <= csr_wmask[`CSR_ASID_ASID] & csr_wvalue[`CSR_ASID_ASID] |
                        ~csr_wmask[`CSR_ASID_ASID] & csr_asid_asid;
    end
end

assign csr_asid_asidbits = 8'd10;

// TLBRENTRY
always @ (posedge clk) begin
    if (reset) begin
        csr_tlbrentry_pa <= 26'b0;
    end else if (csr_we && csr_num == `CSR_TLBRENTRY) begin
        csr_tlbrentry_pa <= csr_wmask[`CSR_TLBRENTRY_PA] & csr_wvalue[`CSR_TLBRENTRY_PA] |
                            ~csr_wmask[`CSR_TLBRENTRY_PA] & csr_tlbrentry_pa;
    end
end

//DMW0-1
always @(posedge clk ) begin
    if(reset) begin
        csr_dmw0_plv0 <= 1'b0;
        csr_dmw0_plv3 <= 1'b0;
        csr_dmw0_mat  <= 2'b0;
        csr_dmw0_pseg <= 3'b0;
        csr_dmw0_vseg <= 3'b0;
    end
    else if(csr_we && csr_num == `CSR_DMW0)begin
        csr_dmw0_plv0  <= csr_wmask[`CSR_DMW_PLV0] & csr_wvalue[`CSR_DMW_PLV0]
                    | ~csr_wmask[`CSR_DMW_PLV0] & csr_dmw0_plv0; 
        csr_dmw0_plv3  <= csr_wmask[`CSR_DMW_PLV3] & csr_wvalue[`CSR_DMW_PLV3]
                    | ~csr_wmask[`CSR_DMW_PLV3] & csr_dmw0_plv3; 
        csr_dmw0_mat   <= csr_wmask[`CSR_DMW_MAT] & csr_wvalue[`CSR_DMW_MAT]
                    | ~csr_wmask[`CSR_DMW_MAT] & csr_dmw0_mat; 
        csr_dmw0_pseg  <= csr_wmask[`CSR_DMW_PSEG] & csr_wvalue[`CSR_DMW_PSEG]
                    | ~csr_wmask[`CSR_DMW_PSEG] & csr_dmw0_pseg;
        csr_dmw0_vseg  <= csr_wmask[`CSR_DMW_VSEG] & csr_wvalue[`CSR_DMW_VSEG]
                    | ~csr_wmask[`CSR_DMW_VSEG] & csr_dmw0_vseg;   
    end
end

always @(posedge clk ) begin
    if(reset) begin
        csr_dmw1_plv0 <= 1'b0;
        csr_dmw1_plv3 <= 1'b0;
        csr_dmw1_mat  <= 2'b0;
        csr_dmw1_pseg <= 3'b0;
        csr_dmw1_vseg <= 3'b0;
    end
    else if(csr_we && csr_num == `CSR_DMW1)begin
        csr_dmw1_plv0  <= csr_wmask[`CSR_DMW_PLV0] & csr_wvalue[`CSR_DMW_PLV0]
                    | ~csr_wmask[`CSR_DMW_PLV0] & csr_dmw1_plv0; 
        csr_dmw1_plv3  <= csr_wmask[`CSR_DMW_PLV3] & csr_wvalue[`CSR_DMW_PLV3]
                    | ~csr_wmask[`CSR_DMW_PLV3] & csr_dmw1_plv3; 
        csr_dmw1_mat   <= csr_wmask[`CSR_DMW_MAT] & csr_wvalue[`CSR_DMW_MAT]
                    | ~csr_wmask[`CSR_DMW_MAT] & csr_dmw1_mat; 
        csr_dmw1_pseg  <= csr_wmask[`CSR_DMW_PSEG] & csr_wvalue[`CSR_DMW_PSEG]
                    | ~csr_wmask[`CSR_DMW_PSEG] & csr_dmw1_pseg;
        csr_dmw1_vseg  <= csr_wmask[`CSR_DMW_VSEG] & csr_wvalue[`CSR_DMW_VSEG]
                    | ~csr_wmask[`CSR_DMW_VSEG] & csr_dmw1_vseg;   
    end
end


// exp 18
assign csr_tlbidx_rvalue = {csr_tlbidx_ne, 1'b0, csr_tlbidx_ps, 20'b0, csr_tlbidx_index};
assign csr_tlbehi_rvalue = {csr_tlbehi_vppn, 13'b0};
assign csr_tlbelo0_rvalue = {csr_tlbelo0_ppn, 1'b0, csr_tlbelo0_g, csr_tlbelo0_mat, csr_tlbelo0_plv, csr_tlbelo0_d, csr_tlbelo0_v};
assign csr_tlbelo1_rvalue = {csr_tlbelo1_ppn, 1'b0, csr_tlbelo1_g, csr_tlbelo1_mat, csr_tlbelo1_plv, csr_tlbelo1_d, csr_tlbelo1_v};
assign csr_asid_rvalue = {8'b0, csr_asid_asidbits, 6'b0, csr_asid_asid};
assign csr_tlbrentry_rvalue = {csr_tlbrentry_pa, 6'b0};

// TLB entry
assign w_tlb_e    = ~csr_tlbidx_ne;
assign w_tlb_ps   =  csr_tlbidx_ps;
assign w_tlb_vppn =  csr_tlbehi_vppn;
assign w_tlb_asid =  csr_asid_asid;
assign w_tlb_g    =  csr_tlbelo0_g & csr_tlbelo1_g;

assign w_tlb_ppn0 = csr_tlbelo0_ppn[19:0];
assign w_tlb_plv0 = csr_tlbelo0_plv;
assign w_tlb_mat0 = csr_tlbelo0_mat;
assign w_tlb_d0   = csr_tlbelo0_d;
assign w_tlb_v0   = csr_tlbelo0_v;

assign w_tlb_ppn1 = csr_tlbelo1_ppn[19:0];
assign w_tlb_plv1 = csr_tlbelo1_plv;
assign w_tlb_mat1 = csr_tlbelo1_mat;
assign w_tlb_d1   = csr_tlbelo1_d;
assign w_tlb_v1   = csr_tlbelo1_v;

//exp19
assign rval_dmw0 = {csr_dmw0_vseg, 1'b0, csr_dmw0_pseg, 19'b0, csr_dmw0_mat, csr_dmw0_plv3, 2'b0, csr_dmw0_plv0};
assign rval_dmw1 = {csr_dmw1_vseg, 1'b0, csr_dmw1_pseg, 19'b0, csr_dmw1_mat, csr_dmw1_plv3, 2'b0, csr_dmw1_plv0};

// To MMU
assign csr_crmd_rvalue = rval_crmd;
assign csr_asid_rvalue = rval_asid;
assign csr_dmw0_rvalue = rval_dmw0;
assign csr_dmw1_rvalue = rval_dmw1;
endmodule
