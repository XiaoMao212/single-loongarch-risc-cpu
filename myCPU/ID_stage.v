`include "mycpu.h"

module id_stage(
    input                          clk           ,
    input                          reset         ,
    //allowin
    input                          es_allowin    ,
    output                         ds_allowin    ,
    //from fs
    input                          fs_to_ds_valid,
    input  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus  ,
    //to es
    output                         ds_to_es_valid,
    output [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus  ,
    //to fs
    output [`BR_BUS_WD       -1:0] br_bus        ,
    //to rf: for write back
    input  [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus ,

    //load op
    input es_to_ds_load_op,
    input ms_to_ds_load_op,
    //store op bne beq b
    input es_to_ds_inst_no_dest,
    input ms_to_ds_inst_no_dest,
    input ws_to_ds_inst_no_dest,
    //the reg address and data from es ms ws
    input [ 36:0] es_forward_reg,
    input [ 36:0] ms_forward_reg,
    input [ 36:0] ws_forward_reg,
    //input ws_ex,//实例化的时候传入的是ws_ex|ertn_flush
    input                          ds_reflush      ,
    input wire es_csr_re,
    input wire ms_csr_re,
    input                          ds_has_int//有软件中断、硬件中断或者定时器中断
);

wire        br_taken;
wire [31:0] br_target;

wire [31:0] ds_pc;
wire [31:0] ds_inst;

reg         ds_valid   ;
wire        ds_ready_go;

wire [18:0] alu_op;


wire        src1_is_pc;
wire        src2_is_imm;
wire        res_from_mem;
wire        dst_is_r1;
wire        gr_we;
wire        mem_we;
wire        src_reg_is_rd;
wire [4: 0] dest;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] imm;
wire [31:0] br_offs;
wire [31:0] jirl_offs;

wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;

//exp10
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_srl_w;
wire        inst_sra_w;
wire        inst_pcaddu12i;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_div_w;
wire        inst_mod_w;
wire        inst_div_wu;
wire        inst_mod_wu;


//exp11
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;

//exp12
wire        inst_csrrd;
wire        inst_csrwr;
wire        inst_csrxchg;
wire        inst_ertn;
wire        inst_syscall;

//exp13
wire        inst_break;
wire        inst_rdcntvl;
wire        inst_rdcntvh;
wire        inst_rdcntid;

//exp18
wire        inst_tlbsrch;
wire        inst_tlbrd;
wire        inst_tlbwr;
wire        inst_tlbfill;
wire        inst_invtlb;


//exp23
wire        inst_cacop;

wire        need_ui5;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;
wire        need_ui12;

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;

wire        rf_we   ;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;



wire [31:0] mem_result;
wire [31:0] final_result;

// inst_no_dest;
wire src_no_rj;
wire src_no_rk;
wire src_no_rd;
wire rj_wait;
wire rk_wait;
wire rd_wait;

wire [ 4:0] es_to_ds_dest;
wire [ 4:0] ms_to_ds_dest;
wire [ 4:0] ws_to_ds_dest;
wire [31:0] es_to_ds_result;
wire [31:0] ms_to_ds_result;
wire [31:0] ws_to_ds_result;
assign es_to_ds_dest = es_forward_reg[36:32];
assign ms_to_ds_dest = ms_forward_reg[36:32];
assign ws_to_ds_dest = ws_forward_reg[36:32];
assign es_to_ds_result = es_forward_reg[31:0];
assign ms_to_ds_result = ms_forward_reg[31:0];
assign ws_to_ds_result = ws_forward_reg[31:0];

assign op_31_26  = ds_inst[31:26];
assign op_25_22  = ds_inst[25:22];
assign op_21_20  = ds_inst[21:20];
assign op_19_15  = ds_inst[19:15];

assign rd   = ds_inst[ 4: 0];
assign rj   = ds_inst[ 9: 5];
assign rk   = ds_inst[14:10];

assign i12  = ds_inst[21:10];
assign i20  = ds_inst[24: 5];
assign i16  = ds_inst[25:10];
assign i26  = {ds_inst[ 9: 0], ds_inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~ds_inst[25];


//exp10
assign inst_slti   = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui  = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi   = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori    = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori   = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_sll_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
assign inst_srl_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_sra_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_pcaddu12i= op_31_26_d[6'h07] & ~ds_inst[25];
assign inst_mul_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_div_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
assign inst_mod_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
assign inst_div_wu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
assign inst_mod_wu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];


//exp11
assign inst_blt    = op_31_26_d[6'h18];
assign inst_bge    = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];
assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];

//exp12
assign inst_csrrd  = op_31_26_d[6'h01] & (op_25_22[3:2] == 2'b00) & (rj == 5'h00);
assign inst_csrwr  = op_31_26_d[6'h01] & (op_25_22[3:2] == 2'b00) & (rj == 5'h01);
assign inst_csrxchg= op_31_26_d[6'h01] & (op_25_22[3:2] == 2'b00) & ~inst_csrrd & ~inst_csrwr;
assign inst_ertn   = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'h0e) & (rj == 5'h00) & (rd == 5'h00);
assign inst_syscall= op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h16];


//exp13
assign inst_break    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h14];
assign inst_rdcntvl  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & (rk == 5'h18) & (rj == 5'h00);
assign inst_rdcntvh  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & (rk == 5'h19) & (rj == 5'h00);
assign inst_rdcntid  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h00] & (rk == 5'h18) & (rd == 5'h00);


//exp18  前面四个指令与ri,rk,rd无关，只是csr与tlb交互，invtlb需要rk（指定VA）,rj（ASID），还有个op
assign inst_tlbsrch = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'h0a) & (rj == 5'h00) & (rd == 5'h00); 
assign inst_tlbrd   = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'h0b) & (rj == 5'h00) & (rd == 5'h00); 
assign inst_tlbwr   = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'h0c) & (rj == 5'h00) & (rd == 5'h00); 
assign inst_tlbfill = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & (rk == 5'h0d) & (rj == 5'h00) & (rd == 5'h00); 
assign inst_invtlb  = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h13];

//exp23
assign inst_cacop   = op_31_26_d[6'h01] & op_25_22_d[4'h8];

assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w
                    | inst_jirl | inst_bl |  inst_pcaddu12i | inst_ld_b
                    | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h | inst_cacop;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltui;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_slli_w | inst_sll_w;
assign alu_op[ 9] = inst_srli_w | inst_srl_w;
assign alu_op[10] = inst_srai_w | inst_sra_w;
assign alu_op[11] = inst_lu12i_w;
assign alu_op[12] = inst_mul_w;
assign alu_op[13] = inst_mulh_w;
assign alu_op[14] = inst_mulh_wu;
assign alu_op[15] = inst_div_w;
assign alu_op[16] = inst_mod_w;
assign alu_op[17] = inst_div_wu;
assign alu_op[18] = inst_mod_wu;

assign need_ui5   =  inst_slli_w | inst_srli_w | inst_srai_w;
assign need_si12  =  inst_addi_w | inst_ld_w | inst_st_w | inst_slti | inst_sltui | inst_ld_b 
                     | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_st_b | inst_st_h;
assign need_si16  =  inst_jirl | inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_cacop;
assign need_si20  =  inst_lu12i_w | inst_pcaddu12i;
assign need_si26  =  inst_b | inst_bl;
assign src2_is_4  =  inst_jirl | inst_bl;
assign need_ui12  =  inst_andi | inst_ori | inst_xori;



assign imm = src2_is_4 ? 32'h4                      :
             need_si20 ? {i20[19:0], 12'b0}         :
             need_ui5  ? rk                         :
             need_ui12 ? {20'b0,i12[11:0]}        :
            /*need_si12*/{{20{i12[11]}}, i12[11:0]} ;


assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                              {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

//cacop_code
wire  [4:0] invtlb_op;
assign invtlb_op  = rd;


assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w | inst_blt | inst_bge 
                       | inst_bltu | inst_bgeu | inst_st_b | inst_st_h| inst_csrwr | inst_csrxchg;


assign src1_is_pc    = inst_jirl | inst_bl |inst_pcaddu12i;


assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_ld_w   |
                       inst_st_w   |
                       inst_lu12i_w|
                       inst_jirl   |
                       inst_bl     |
                       inst_slti   |
                       inst_sltui  |
                       inst_andi   |
                       inst_ori    |
                       inst_xori   |
                       inst_pcaddu12i |
                       inst_ld_b   |
                       inst_ld_h   | 
                       inst_ld_bu  | 
                       inst_ld_hu  |
                       inst_st_b   | 
                       inst_st_h   |
                       inst_cacop;

//结果来自dataRAM
assign res_from_mem  =inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;
//目的寄存器是R1
assign dst_is_r1     = inst_bl;
//目的寄存器是rj
wire dst_is_rj;
assign dst_is_rj     = inst_rdcntid;
//寄存器堆写使能
assign gr_we         = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b & ~inst_blt 
                       & ~inst_bge & ~inst_bltu & ~inst_bgeu & ~inst_st_b & ~inst_st_h 
                       & ~inst_syscall & ~inst_ertn& ~inst_break 
                       & ~inst_tlbrd & ~inst_tlbwr & ~inst_tlbfill & ~inst_tlbsrch 
                       & ~inst_invtlb & ~inst_cacop;
//内存写使能
assign mem_we        = inst_st_w | inst_st_b | inst_st_h;
//目的寄存器
assign dest          = dst_is_r1 ? 5'd1 : (dst_is_rj ? rj : rd);


assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd :rk;

//以下四条指令没有目的操作数，当inst_no_dest为1时，表明没有目的操作数需要比较
//assign inst_no_dest = inst_st_w | inst_bne | inst_beq | inst_b | inst_st_b | inst_st_h | inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_syscall | inst_ertn;
//判断当前译码指令的源操作数是哪些
assign src_no_rj    = inst_b | inst_bl | inst_lu12i_w | inst_pcaddu12i | inst_tlbsrch | inst_tlbrd | inst_tlbwr | inst_tlbfill ;
assign src_no_rk    = inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | 
                      inst_b | inst_bl | inst_beq | inst_bne | inst_lu12i_w |inst_slti | inst_sltui | inst_andi | 
                      inst_ori | inst_xori | inst_pcaddu12i | inst_blt |inst_bge | inst_bltu | inst_bgeu | inst_ld_b | inst_ld_h | inst_ld_bu|
                      inst_ld_hu | inst_st_b | inst_st_h | inst_tlbsrch | inst_tlbrd | inst_tlbwr | inst_tlbfill | inst_cacop;
//以下三种指令的源操作数有rd，其他指令rd均不作为源操作数
assign src_no_rd    = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_st_b & ~inst_st_h & ~inst_blt & ~inst_bge & ~inst_bltu & ~inst_bgeu & ~inst_csrwr & ~inst_csrxchg
                      & ~inst_tlbsrch & ~inst_tlbrd & ~inst_tlbwr & ~inst_tlbfill & ~inst_invtlb;
//判断当前译码指令的三个寄存器是否发生写后读的情况，如果发生，以下三个信号为1
//0号寄存器恒为0
assign rj_wait = ~src_no_rj && (rj != 5'b00000) && ((rj == es_to_ds_dest && ~es_to_ds_inst_no_dest) || (rj == ms_to_ds_dest & {5{~ms_to_ds_inst_no_dest}}) || (rj == ws_to_ds_dest & {5{~ws_to_ds_inst_no_dest}}));
assign rk_wait = ~src_no_rk && (rk != 5'b00000) && ((rk == es_to_ds_dest & {5{~es_to_ds_inst_no_dest}}) || (rk == ms_to_ds_dest & {5{~ms_to_ds_inst_no_dest}}) || (rk == ws_to_ds_dest & {5{~ws_to_ds_inst_no_dest}}));
assign rd_wait = ~src_no_rd && (rd != 5'b00000) && ((rd == es_to_ds_dest & {5{~es_to_ds_inst_no_dest}}) || (rd == ms_to_ds_dest & {5{~ms_to_ds_inst_no_dest}}) || (rd == ws_to_ds_dest & {5{~ws_to_ds_inst_no_dest}}));

assign rj_value  = rj_wait ? ((rj == es_to_ds_dest) ? es_to_ds_result :
                              (rj == ms_to_ds_dest) ? ms_to_ds_result : ws_to_ds_result)
                            : rf_rdata1;
assign rkd_value = rk_wait ? ((rk == es_to_ds_dest) ? es_to_ds_result :
                            (rk == ms_to_ds_dest) ? ms_to_ds_result : ws_to_ds_result) : 
                   rd_wait ? ((rd == es_to_ds_dest) ? es_to_ds_result :
                            (rd == ms_to_ds_dest) ? ms_to_ds_result : ws_to_ds_result) :
                   rf_rdata2;
regfile u_regfile(
    .clk    (clk      ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
    );
//跳转条件判断
wire [31:0] adder_result;
wire        adder_cout;
assign {adder_cout, adder_result} = rj_value + (~rkd_value) + 1'b1;

wire rj_eq_rd;
wire rj_le_rd_s;
wire rj_le_rd_u;

//跳转条件
assign rj_eq_rd = (rj_value == rkd_value);
assign  rj_le_rd_s = (rj_value[31]&~rkd_value[31]) | ((rj_value[31]~^rkd_value[31])& adder_result[31]); 
assign  rj_le_rd_u = adder_cout;
assign br_taken = (   inst_beq  &&  rj_eq_rd
                   || inst_bne  && !rj_eq_rd
                   || inst_jirl
                   || inst_bl
                   || inst_b
                   || inst_blt  && rj_le_rd_s
                   || inst_bge  && !rj_le_rd_s
                   || inst_bltu && rj_le_rd_u
                   || inst_bgeu && !rj_le_rd_u
                )  && ds_valid & ds_ready_go;
//beq bne bl b blt bge bltu bgeu：pc+偏移值jirl：rj_value+jirl_offs
assign br_target = (inst_beq || inst_bne || inst_bl || inst_b || inst_blt || inst_bge || inst_bltu || inst_bgeu) ? (ds_pc + br_offs) :
                                                   /*inst_jirl*/ (rj_value + jirl_offs);


assign br_bus     = {br_stall, br_taken, br_target};

reg  [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus_r;

wire [  5:0] fs_exc_ecode;
assign {fs_exc_ecode,
        ds_adef_data,
        ds_inst,
        ds_pc  } = fs_to_ds_bus_r;
assign {ds_adef, ds_wrong_addr}       = ds_adef_data;
assign {rf_we   ,  //37:37
        rf_waddr,  //36:32
        rf_wdata   //31:0
       } = ws_to_rf_bus;
wire [2:0] load_op;
assign load_op = inst_ld_b ? 3'b001 : inst_ld_bu ? 3'b010 : 
                 inst_ld_h ? 3'b011 : inst_ld_hu ? 3'b100 : 
                 inst_ld_w ? 3'b101 : 3'b000;    
                 
wire   [1:0]   store_op;  
assign store_op = inst_st_b ? 2'b01 : (inst_st_h ? 2'b10 : (inst_st_w ? 2'b11 : 2'b00));

assign ds_to_es_bus = {fs_tlb_ex   ,
                       alu_op       ,   // 19
                       load_op      ,   // 3
                       store_op     ,  //2
                      // inst_no_dest ,
                       src1_is_pc   ,   // 1
                       src2_is_imm  ,   // 1
                       src2_is_4    ,   // 1
                       gr_we        ,   // 1
                       mem_we       ,   // 1
                       dest         ,   // 5
                       imm          ,   // 32
                       rj_value     ,   // 32
                       rkd_value    ,   // 32
                       ds_pc        ,    // 32
                       res_from_mem ,
                       ds_exception ,
                       time_op      ,
                       inst_tlbsrch ,//exp18
                       inst_tlbrd   ,
                       inst_tlbwr   ,
                       inst_tlbfill ,
                       inst_invtlb  ,
                       invtlb_op    ,
                       inst_cacop
                    };


//assign ds_ready_go    = 1'b1;
//assign ds_ready_go    = no_wait;
wire load_stall;
wire csr_stall;
assign csr_stall  = (es_csr_re & (((rj == es_to_ds_dest) & rj_wait) |
	                             ((rk == es_to_ds_dest) & rk_wait)  |
	                             ((rd == es_to_ds_dest) & rd_wait)))|
                    (ms_csr_re & (((rj == ms_to_ds_dest) & rj_wait) |
	                            ((rk == ms_to_ds_dest) & rk_wait)   |
	                            ((rd == ms_to_ds_dest) & rd_wait)));
assign ds_ready_go    = (~load_stall & ~csr_stall) || ds_reflush;
assign ds_allowin     = !ds_valid || ds_ready_go &&   es_allowin;
assign ds_to_es_valid =  ds_valid && ds_ready_go && (~ds_reflush);
always @(posedge clk) begin
   if (reset) begin
   //if (reset || ds_reflush || br_taken) begin//exp21
        ds_valid <= 1'b0;
    end
    else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid;
    end

    if (fs_to_ds_valid && ds_allowin) begin
        fs_to_ds_bus_r <= fs_to_ds_bus;
    end
end






assign load_stall = es_to_ds_load_op & (((rj == es_to_ds_dest) & rj_wait) |
	                                    ((rk == es_to_ds_dest) & rk_wait) |
	                                    ((rd == es_to_ds_dest) & rd_wait))|
                    ms_to_ds_load_op & (((rj == ms_to_ds_dest) & rj_wait) |
	                                    ((rk == ms_to_ds_dest) & rk_wait) |
	                                    ((rd == ms_to_ds_dest) & rd_wait)); 

//assign br_stall   = ( load_stall | csr_stall ) & br_taken & ds_valid;
//assign br_stall   = 1'b0;
//exp14
wire        br_stall;
wire        ds_br;
assign ds_br      = inst_beq | inst_bne | inst_jirl | inst_blt | inst_bge | inst_bltu | inst_bgeu;
assign br_stall   = (load_stall | csr_stall) & ds_br & ds_valid & ~ds_reflush;


wire        inst_csrrd;
wire        inst_csrwr;
wire        inst_csrxchg;
wire        inst_ertn;
wire        inst_syscall;
//wire [81:0] ds_exception;
wire [129:0] ds_exception;
//csr读使能，写使能，写掩码，写数据，写地址
wire        csr_re;
wire        csr_we;
wire [31:0] csr_wmask;
wire [31:0] csr_wvalue;
wire [13:0] csr_num;
//exp13
wire [  5:0] ds_ecode;
wire [  8:0] ds_esubcode;
wire [ 32:0] ds_adef_data;
wire         ds_adef;
wire [ 31:0] ds_wrong_addr;
wire         ds_ine;
wire         ds_ertn;
wire         ds_ex;
wire         fs_tlb_ex;
wire [  1:0] time_op;
assign csr_re     = inst_csrrd | inst_csrwr | inst_csrxchg |inst_rdcntid;
assign csr_we     = inst_csrwr | inst_csrxchg;
assign csr_wmask  = {32{inst_csrxchg}} & rj_value | {32{inst_csrwr}};
assign csr_wvalue = rkd_value;
assign csr_num     = {14{inst_rdcntid}} & `CSR_TID | {14{~inst_rdcntid}} & ds_inst[23:10];
assign ds_ine      = ~(inst_add_w     | inst_sub_w   | inst_slt     | inst_sltu      |
                       inst_nor       | inst_and     | inst_or      | inst_xor       |   
                       inst_slli_w    | inst_srli_w  | inst_srai_w  | inst_addi_w    | 
                       inst_ld_w      | inst_st_w    | inst_jirl    | inst_b         |
                       inst_bl        | inst_beq     | inst_bne     | inst_lu12i_w   |
                       inst_slti      | inst_sltui   | inst_andi    | inst_ori       | 
                       inst_xori      | inst_sll_w   | inst_srl_w   | inst_sra_w     |
                       inst_mul_w     | inst_mulh_w  | inst_mulh_wu | inst_div_w     | 
                       inst_mod_w     | inst_div_wu  | inst_mod_wu  | inst_pcaddu12i |
                       inst_blt       | inst_bge     | inst_bltu    | inst_bgeu      | 
                       inst_ld_b      | inst_ld_h    | inst_ld_bu   | inst_ld_hu     |
                       inst_st_b      | inst_st_h    | inst_csrrd   | inst_csrwr     |
                       inst_csrxchg   | inst_ertn    | inst_syscall | inst_break     |
                       inst_rdcntvl   | inst_rdcntvh | inst_rdcntid | inst_tlbsrch   |
                       inst_tlbrd     | inst_tlbwr   | inst_tlbfill | inst_invtlb    |
                       inst_cacop)    |inst_invtlb & (invtlb_op > 5'd6);

assign ds_ex       = ds_valid & (inst_syscall | inst_break | ds_ine | ds_has_int | ds_adef| (|fs_exc_ecode));
assign fs_tlb_ex   = |fs_exc_ecode;

assign ds_ertn     = inst_ertn & ds_valid;
assign ds_ecode    = ds_has_int   ? `ECODE_INT
                   : ds_adef      ? `ECODE_ADE
                   : ds_ine       ? `ECODE_INE
                   : inst_break   ? `ECODE_BRK
                   : inst_syscall ? `ECODE_SYS 
                   : fs_exc_ecode[0] ? `ECODE_TLBR   
                   : fs_exc_ecode[3] ? `ECODE_PIF
                   : fs_exc_ecode[1] ? `ECODE_PPI :  6'b0;
assign ds_esubcode = ds_adef ? `ESUBCODE_ADEF : 9'b0;
assign time_op     = {inst_rdcntvh, inst_rdcntvl}; 

//assign ds_exception = {csr_re, csr_we, csr_wmask, csr_wvalue, csr_num, inst_syscall, inst_ertn};
assign ds_exception = {csr_re, csr_we, csr_wmask, csr_wvalue, csr_num, ds_ex, ds_ertn, 
                       ds_adef, ds_wrong_addr, ds_ecode, ds_esubcode};
endmodule
