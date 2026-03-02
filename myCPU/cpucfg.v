module cpucfg(
    input  wire [31:0] rj_value,    // rj 寄存器的值 (索引)
    output reg  [31:0] cpucfg_data  // 返回给 rd 的配置字
);

    //================================================================
    // 基础参数配置 
    //================================================================
    // 此频率与您 Vivado Block Design 中的 pll 输出频率一致
    localparam CPU_FREQ_HZ    = 32'd100_000_000; 

    // 物理/虚拟地址宽度 
    localparam PHY_ADDR_WIDTH = 32; 
    localparam VIRT_ADDR_WIDTH= 32;
    
    // Cache 参数 (根据 dcache.v/icache.v 确认)
    // 2路组相联, Index=8bit(256组), Offset=4bit(16字节/行)
    localparam L1_WAY_NUM     = 2;              
    localparam L1_INDEX_LOG2  = 8;  // input [7:0] index
    localparam L1_LINE_LOG2   = 4;  // input [3:0] offset -> 16 Bytes

    //================================================================
    // 配置字生成逻辑
    //================================================================
    always @(*) begin
        cpucfg_data = 32'b0;

        case (rj_value)
            //--------------------------------------------------------
            // 0x00: PRID (Processor ID)
            //--------------------------------------------------------
            //32'h00: cpucfg_data = 32'h14C01000; // 标准 LA32 ID
            32'h00: cpucfg_data = 32'h00000000;
            //--------------------------------------------------------
            // 0x01: ARCH (架构特性)
            //--------------------------------------------------------
            32'h01: begin
                // [1:0] ARCH:LA精简指令集
                cpucfg_data[1:0]   = 2'b00; 
                // [2] PGMMU: 1 (mmu.v 存在)
                cpucfg_data[2]     = 1'b1;
                // [3] IOCSR: 1 (LA32 标准要求)
                cpucfg_data[3]     = 1'b1;
                // [11:4] PALEN: 32-1 = 31 (mmu.v 输出 32位 pa)
                cpucfg_data[11:4]  = PHY_ADDR_WIDTH[7:0] - 8'd1;
                // [19:12] VALEN: 32-1 = 31 (mmu.v 输入 32位 va)
                cpucfg_data[19:12] = VIRT_ADDR_WIDTH[7:0] - 8'd1;
                // [20] UAL: 0 (EXE_stage.v 显示不支持硬解非对齐，会报 ALE 异常)
                cpucfg_data[20]    = 1'b0; 
                // [21] RI: 1 (TLB 支持读保护)
                cpucfg_data[21]    = 1'b1;
                // [22] EP: 1 (TLB 支持执行保护)
                cpucfg_data[22]    = 1'b1;
            end

            //--------------------------------------------------------
            // 0x02: Feature (扩展功能)
            //--------------------------------------------------------
            32'h02: begin
                // [2:0] FP: 不支持浮点数指令
                cpucfg_data[2:0]   = 3'b000; 
                // [14] LLFTP: 1 (csr.v 实现了 timer)
                cpucfg_data[14]    = 1'b1;
                // [17:15] LLFTP_ver: 1
                cpucfg_data[17:15] = 3'd1;
            end

            //--------------------------------------------------------
            // 0x03: Cache Coherency (一致性)
            //--------------------------------------------------------
            32'h03: begin
                cpucfg_data[1] = 1'b0; // 不支持 SFB
            end

            //--------------------------------------------------------
            // 0x04: CC_FREQ (基准频率 Hz) - Linux 计时依赖此值
            //--------------------------------------------------------
            32'h04: cpucfg_data = CPU_FREQ_HZ; 

            //--------------------------------------------------------
            // 0x05: CC_MUL/DIV (定时器倍频系数)
            //--------------------------------------------------------
            32'h05: begin
                // 1:1 关系 (Timer频率 = CPU主频)
                cpucfg_data[15:0]  = 16'd1; // MUL
                cpucfg_data[31:16] = 16'd1; // DIV
            end

            //--------------------------------------------------------
            // 0x10: L1 Cache 存在位图
            //--------------------------------------------------------
            32'h10: begin
                cpucfg_data[0] = 1'b1; // L1 I-Cache 存在 (icache.v)
                cpucfg_data[1] = 1'b0; // 独立 Cache (非统一)
                cpucfg_data[2] = 1'b1; // L1 D-Cache 存在 (dcache.v)
            end

            //--------------------------------------------------------
            // 0x11: L1 I-Cache 参数
            //--------------------------------------------------------
            32'h11: begin
                // [15:0] Way-1: 2-1 = 1
                cpucfg_data[15:0]  = L1_WAY_NUM - 16'd1;
                // [23:16] Index-log2: 8
                cpucfg_data[23:16] = L1_INDEX_LOG2[7:0];
                // [30:24] Linesize-log2: 4 (16字节)
                cpucfg_data[30:24] = L1_LINE_LOG2[6:0];
            end

            //--------------------------------------------------------
            // 0x12: L1 D-Cache 参数
            //--------------------------------------------------------
            32'h12: begin
                // [15:0] Way-1: 2-1 = 1
                cpucfg_data[15:0]  = L1_WAY_NUM - 16'd1;
                // [23:16] Index-log2: 8
                cpucfg_data[23:16] = L1_INDEX_LOG2[7:0];
                // [30:24] Linesize-log2: 4 (16字节)
                cpucfg_data[30:24] = L1_LINE_LOG2[6:0];
            end

            default: cpucfg_data = 32'b0;
        endcase
    end

endmodule