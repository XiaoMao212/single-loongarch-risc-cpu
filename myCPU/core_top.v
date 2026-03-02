`include "mycpu.h"

module core_top(
    input           aclk,
    input           aresetn,
    input    [ 7:0] intrpt,  // 标准接口要求的中断输入
    
    // AXI interface 
    // read reqest
    output   [ 3:0] arid,
    output   [31:0] araddr,
    output   [ 7:0] arlen,
    output   [ 2:0] arsize,
    output   [ 1:0] arburst,
    output   [ 1:0] arlock,
    output   [ 3:0] arcache,
    output   [ 2:0] arprot,
    output          arvalid,
    input           arready,
    // read back
    input    [ 3:0] rid,
    input    [31:0] rdata,
    input    [ 1:0] rresp,
    input           rlast,
    input           rvalid,
    output          rready,
    // write request
    output   [ 3:0] awid,
    output   [31:0] awaddr,
    output   [ 7:0] awlen,
    output   [ 2:0] awsize,
    output   [ 1:0] awburst,
    output   [ 1:0] awlock,
    output   [ 3:0] awcache,
    output   [ 2:0] awprot,
    output          awvalid,
    input           awready,
    // write data
    output   [ 3:0] wid,
    output   [31:0] wdata,
    output   [ 3:0] wstrb,
    output          wlast,
    output          wvalid,
    input           wready,
    // write back
    input    [ 3:0] bid,
    input    [ 1:0] bresp,
    input           bvalid,
    output          bready,

    input  wire        break_point,  // 改为 input
    input  wire        infor_flag,   // 改为 input
    input  wire [ 4:0] reg_num,      // 改为 input

    output wire        ws_valid,     // 保持 output
    output wire [31:0] rf_rdata,     // 保持 output

    // debug info
    output [31:0] debug0_wb_pc,
    output [ 3:0] debug0_wb_rf_wen, // 注意：标准接口叫 wen
    output [ 4:0] debug0_wb_rf_wnum,
    output [31:0] debug0_wb_rf_wdata


);

    assign ws_valid    = 1'b0;  // 如果你有写回级有效信号，可以连这里
    assign rf_rdata    = 32'b0;
    // -----------------------------------------------------------
    // 内部信号定义
    // -----------------------------------------------------------

    // 调试信号连接线 (用于连接 u_core 输出到 core_top 输出)
    wire [31:0] debug_wb_pc;
    wire [ 3:0] debug_wb_rf_we;
    wire [ 4:0] debug_wb_rf_wnum;
    wire [31:0] debug_wb_rf_wdata;

    // === 核心适配逻辑 ===
    assign debug0_wb_pc       = debug_wb_pc;
    assign debug0_wb_rf_wen   = debug_wb_rf_we; // 映射 we 到 wen
    assign debug0_wb_rf_wnum  = debug_wb_rf_wnum;
    assign debug0_wb_rf_wdata = debug_wb_rf_wdata;




    // Inst SRAM Interface (CPU <-> I-Cache)
    wire        inst_sram_req    ;
    wire        inst_sram_wr     ;
    wire [ 1:0] inst_sram_size   ;
    wire [ 3:0] inst_sram_wstrb  ;
    wire [31:0] inst_sram_addr   ;
    wire [31:0] inst_sram_wdata  ;
    wire [31:0] icache_rdata     ; 
    wire        icache_addr_ok   ;
    wire        icache_data_ok   ;

    // Data SRAM Interface (CPU <-> D-Cache)
    wire        data_sram_req    ;
    wire        data_sram_wr     ;
    wire [ 3:0] data_sram_wstrb  ;
    wire [ 1:0] data_sram_size   ;
    wire [31:0] data_sram_addr   ;
    wire [31:0] data_sram_wdata  ;
    wire [31:0] dcache_rdata     ;
    wire        dcache_addr_ok   ;
    wire        dcache_data_ok   ;

    // I-Cache <-> Bridge Interface
    wire        icache_rd_req   ;
    wire [ 2:0] icache_rd_type  ;
    wire [31:0] icache_rd_addr  ;
    wire        icache_rd_rdy   ;
    wire        icache_ret_valid;
    wire        icache_ret_last ;
    wire [31:0] icache_ret_data ;

    // D-Cache <-> Bridge Interface
    wire        dcache_rd_req   ;
    wire [ 2:0] dcache_rd_type  ;
    wire [31:0] dcache_rd_addr  ;
    wire        dcache_rd_rdy   ;
    wire        dcache_ret_valid;
    wire        dcache_ret_last ;
    wire [31:0] dcache_ret_data ;
    
    wire        dcache_wr_req   ;
    wire [ 2:0] dcache_wr_type  ;
    wire [31:0] dcache_wr_addr  ;
    wire [ 3:0] dcache_wr_wstrb ;
    wire [127:0]dcache_wr_data  ;
    wire        dcache_wr_rdy   ;
    
    wire        write_buffer_empty;
    wire        inst_wr_rdy;

    // Core Control Signals
    wire [31:0] fs_va;
    wire        ws_reflush;
    wire        inst_uncached;
    wire        data_uncached; 
    
    wire        data_finish;
wire  [2:0] size;
wire  [1:0] cacop_op_mode;
wire        tlb_excp_cancel_req;
wire        dcache_empty;
wire        cache_miss;
    // cacop related
    wire         ms_cacop_req_i;   
    wire         ms_cacop_req_d;   
    wire [ 4:0]  ms_cacop_op_code; 
    wire         icache_cacop_done;
    wire         dcache_cacop_done; 
    wire [31:0]  ms_cacop_addr;
    wire [31:0]  es_va;

    // -----------------------------------------------------------
    // 1. CPU Core 实例化
    // -----------------------------------------------------------
    mycpu_core u_core(
        .clk               (aclk             ),
        .resetn            (aresetn          ),
        
        // TODO: 如果你的 mycpu_core 已经实现了中断接口，请在此处连接
        // .intrpt         (intrpt           ), 

        // I-Cache 接口
        .inst_sram_req     (inst_sram_req    ),
        .inst_sram_wr      (inst_sram_wr     ),
        .inst_sram_size    (inst_sram_size   ),
        .inst_sram_wstrb   (inst_sram_wstrb  ),
        .inst_sram_addr    (inst_sram_addr   ),
        .inst_sram_wdata   (inst_sram_wdata  ),
        .inst_sram_rdata   (icache_rdata     ), 
        .inst_sram_addr_ok (icache_addr_ok   ), 
        .inst_sram_data_ok (icache_data_ok   ), 
        
        // D-Cache 接口
        .data_sram_req     (data_sram_req    ),
        .data_sram_wr      (data_sram_wr     ),
        .data_sram_wstrb   (data_sram_wstrb  ),
        .data_sram_size    (data_sram_size   ),
        .data_sram_addr    (data_sram_addr   ),
        .data_sram_wdata   (data_sram_wdata  ),
        .data_sram_rdata   (dcache_rdata     ), 
        .data_sram_addr_ok (dcache_addr_ok   ), 
        .data_sram_data_ok_l (dcache_data_ok ), 
        .data_sram_data_ok_s (dcache_data_ok ), 
        
        // 调试与控制
        .debug_wb_pc       (debug_wb_pc      ),
        .debug_wb_rf_we    (debug_wb_rf_we   ),
        .debug_wb_rf_wnum  (debug_wb_rf_wnum ),
        .debug_wb_rf_wdata (debug_wb_rf_wdata),
        .fs_va             (fs_va            ),
        .ws_reflush        (ws_reflush       ),
        
        // Uncached 属性
        .uncached          (inst_uncached    ), 
        .data_uncached     (data_uncached)   , 
        .es_va             (es_va),
        .ms_cacop_req_i    (ms_cacop_req_i),
        .ms_cacop_req_d    (ms_cacop_req_d),
        .ms_cacop_addr     (ms_cacop_addr),
        .ms_cacop_op_code  (ms_cacop_op_code),
        .icache_cacop_done (icache_cacop_done),
        .dcache_cacop_done (dcache_data_ok),
        .size(size),
        .cacop_op_mode(cacop_op_mode),
        .tlb_excp_cancel_req(tlb_excp_cancel_req)
    );

    // -----------------------------------------------------------
    // 2. I-Cache 实例化 
    // -----------------------------------------------------------
    icache icache(
        .clk    (aclk),
        .resetn (aresetn),
        
        // CPU Side
        .uncached   (inst_uncached),
        .valid      (inst_sram_req         ),
        .op         (1'b0                  ), // 永远是读
        .index      (fs_va[11:4]           ), // VIPT: Index 用 VA
        .tag        (inst_sram_addr[31:12]), // PIPT: Tag 用 PA
        .offset     (fs_va[3:0]            ),
        .wstrb      (inst_sram_wstrb       ), // 虽不用，但接上
        .wdata      (inst_sram_wdata       ),
        
        .addr_ok    (icache_addr_ok        ),
        .data_ok    (icache_data_ok        ),
        .rdata      (icache_rdata          ),
        
        // AXI Side
        .rd_req     (icache_rd_req         ),
        .rd_type    (icache_rd_type        ),
        .rd_addr    (icache_rd_addr        ),
        .rd_rdy     (icache_rd_rdy         ),
        .ret_valid  (icache_ret_valid      ),
        .ret_last   (icache_ret_last       ),
        .ret_data   (icache_ret_data       ),
        
        // I-Cache 写接口悬空 (Bridge 不处理 I-Cache 写)
        .wr_req     (),
        .wr_type    (),
        .wr_addr    (),
        .wr_wstrb   (),
        .wr_data    (),
        .wr_rdy     (1'b1) ,
        .cacop_req  (ms_cacop_req_i        ),
        .cacop_op   (ms_cacop_op_code      ),
        .cacop_addr (ms_cacop_addr         ),
        .cacop_complete(icache_cacop_done)
    );

    // -----------------------------------------------------------
    // 3. D-Cache 实例化 
    // -----------------------------------------------------------
    dcache dcache(
        .clk    (aclk),
        .resetn (aresetn),
        
        // CPU Side
       // .uncached   (data_uncached),
        .valid      (data_sram_req         ),
        .op         (data_sram_wr          ),
        .size       (size                  ),
        .index      (es_va[11:4] ), 
        .tag        (data_sram_addr[31:12]),
        .offset     (es_va[3:0]  ),
        .wstrb      (data_sram_wstrb       ),
        .wdata      (data_sram_wdata       ),
        
        .addr_ok    (dcache_addr_ok        ),
        .data_ok    (dcache_data_ok        ),
        .rdata      (dcache_rdata          ),
        .uncache_en   (data_uncached),
        .dcacop_op_en  (ms_cacop_req_d        ),
        .cacop_op_mode  (cacop_op_mode),
        .preld_hint     (5'b0),
        .preld_en       (1'b0),
        .tlb_excp_cancel_req    (1'b0),
        .sc_cancel_req  (1'b0),
        .dcache_empty(dcache_empty),
        //.cacop_op   (ms_cacop_op_code      ),
        // AXI Side
        .rd_req     (dcache_rd_req         ),
        .rd_type    (dcache_rd_type        ),
        .rd_addr    (dcache_rd_addr        ),
        .rd_rdy     (dcache_rd_rdy         ),
        .ret_valid  (dcache_ret_valid      ),
        .ret_last   (dcache_ret_last       ),
        .ret_data   (dcache_ret_data       ),
        
        .wr_req     (dcache_wr_req         ),
        .wr_type    (dcache_wr_type        ),
        .wr_addr    (dcache_wr_addr        ),
        .wr_wstrb   (dcache_wr_wstrb       ),
        .wr_data    (dcache_wr_data        ),
        .wr_rdy     (dcache_wr_rdy         ),
        .cache_miss (cache_miss)
      //  .data_finish (data_finish          ),
       // .cacop_req  (ms_cacop_req_d        ),
        
        //.cacop_addr (ms_cacop_addr         ),
        //.cacop_complete(dcache_cacop_done)
    );

    // -----------------------------------------------------------
    // 4. AXI Bridge 实例化 
    // -----------------------------------------------------------
    axi_bridge u_bridge(
        .clk               (aclk             ),
        .resetn            (aresetn          ),

        // AXI Master Interface
        .arid              (arid             ),
        .araddr            (araddr           ),
        .arlen             (arlen            ),
        .arsize            (arsize           ),
        .arburst           (arburst          ),
        .arlock            (arlock           ),
        .arcache           (arcache          ),
        .arprot            (arprot           ),
        .arvalid           (arvalid          ),
        .arready           (arready          ),

        .rid               (rid              ),
        .rdata             (rdata            ),
        .rresp             (rresp            ),
        .rlast             (rlast            ),
        .rvalid            (rvalid           ),
        .rready            (rready           ),

        .awid              (awid             ),
        .awaddr            (awaddr           ),
        .awlen             (awlen            ),
        .awsize            (awsize           ),
        .awburst           (awburst          ),
        .awlock            (awlock           ),
        .awcache           (awcache          ),
        .awprot            (awprot           ),
        .awvalid           (awvalid          ),
        .awready           (awready          ),

        .wid               (wid              ),
        .wdata             (wdata            ),
        .wstrb             (wstrb            ),
        .wlast             (wlast            ),
        .wvalid            (wvalid           ),
        .wready            (wready           ),

        .bid               (bid              ),
        .bresp             (bresp            ),
        .bvalid            (bvalid           ),
        .bready            (bready           ),

        // I-Cache Interface
        .inst_rd_req     (icache_rd_req    ),
        .inst_rd_type    (icache_rd_type   ),
        .inst_rd_addr    (icache_rd_addr   ),
        .inst_rd_rdy     (icache_rd_rdy    ),
        .inst_ret_valid  (icache_ret_valid ),
        .inst_ret_last   (icache_ret_last  ),
        .inst_ret_data   (icache_ret_data  ),
        .inst_wr_req    (1'b0    ),
        .inst_wr_type   (3'b0   ),
        .inst_wr_addr   (32'b0   ),
        .inst_wr_wstrb  (4'b0  ),
        .inst_wr_data   (128'b0   ),
        .inst_wr_rdy    (inst_wr_rdy       ),
        // D-Cache Interface
        .data_rd_req     (dcache_rd_req    ),
        .data_rd_type    (dcache_rd_type   ),
        .data_rd_addr    (dcache_rd_addr   ),
        .data_rd_rdy     (dcache_rd_rdy    ),
        .data_ret_valid  (dcache_ret_valid ),
        .data_ret_last   (dcache_ret_last  ),
        .data_ret_data   (dcache_ret_data  ),
        
        .data_wr_req     (dcache_wr_req    ),
        .data_wr_type    (dcache_wr_type   ),
        .data_wr_addr    (dcache_wr_addr   ),
        .data_wr_wstrb   (dcache_wr_wstrb  ),
        .data_wr_data    (dcache_wr_data   ),
        .data_wr_rdy     (dcache_wr_rdy    ),
        
       // .data_sram_size    (data_sram_size   ),
       .write_buffer_empty (write_buffer_empty),
       .data_finish       (data_finish      )
    );

endmodule