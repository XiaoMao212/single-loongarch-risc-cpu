`include "mycpu.h"

module mycpu_top(
    input         aclk   ,
    input         aresetn,
 
    // ar 
    output [ 3:0] arid   , // master -> slave
    output [31:0] araddr , // master -> slave
    output [ 7:0] arlen  , // master -> slave, 8'b0
    output [ 2:0] arsize , // master -> slave
    output [ 1:0] arburst, // master -> slave, 2'b1
    output [ 1:0] arlock , // master -> slave, 2'b0
    output [ 3:0] arcache, // master -> slave, 4'b0
    output [ 2:0] arprot , // master -> slave, 3'b0
    output        arvalid, // master -> slave
    input         arready, // slave  -> master

    // r
    input  [ 3:0] rid    , // slave  -> master
    input  [31:0] rdata  , // slave  -> master
    input  [ 1:0] rresp  , // slave  -> master, ignore
    input         rlast  , // slave  -> master, ignore
    input         rvalid , // slave  -> master
    output        rready , // master -> slave

    // aw
    output [ 3:0] awid   , // master -> slave, 4'b1
    output [31:0] awaddr , // master -> slave
    output [ 7:0] awlen  , // master -> slave, 8'b0
    output [ 2:0] awsize , // master -> slave
    output [ 1:0] awburst, // master -> slave, 2'b1
    output [ 1:0] awlock , // master -> slave, 2'b0
    output [ 3:0] awcache, // master -> slave, 4'b0
    output [ 2:0] awprot , // master -> slave, 3'b0
    output        awvalid, // master -> slave
    input         awready, // slave  -> master

    // w
    output [ 3:0] wid    , // master -> slave, 4'b1
    output [31:0] wdata  , // master -> slave
    output [ 3:0] wstrb  , // master -> slave
    output        wlast  , // master -> slave, 1'b1
    output        wvalid , // master -> slave
    input         wready , // slave  -> master

    // b
    input  [ 3:0] bid    , // slave  -> master, ignore
    input  [ 1:0] bresp  , // slave  -> master, ignore
    input         bvalid , // slave  -> master
    output        bready , // master -> slave
    
    // trace debug interface
    output [31:0] debug_wb_pc      ,
    output [ 3:0] debug_wb_rf_we  ,
    output [ 4:0] debug_wb_rf_wnum ,
    output [31:0] debug_wb_rf_wdata
);

// inst sram interface    
wire        inst_sram_req    ;
wire        inst_sram_wr     ;
wire [ 1:0] inst_sram_size   ;
wire [ 3:0] inst_sram_wstrb  ;
wire [31:0] inst_sram_addr   ;
wire [31:0] inst_sram_wdata  ;
wire [31:0] inst_sram_rdata  ;
wire        inst_sram_addr_ok;
wire        inst_sram_data_ok;

// data sram interface
wire        data_sram_req    ;
wire        data_sram_wr     ;
wire [ 3:0] data_sram_wstrb  ;
wire [ 1:0] data_sram_size   ;
wire [31:0] data_sram_addr   ;
wire [31:0] data_sram_wdata  ;
wire [31:0] data_sram_rdata  ;
wire        data_sram_addr_ok;
wire        data_sram_data_ok;

mycpu_core u_core(
    .clk               (aclk             ),
    .resetn            (aresetn          ),
  
    .inst_sram_req     (inst_sram_req    ),
    .inst_sram_wr      (inst_sram_wr     ),
    .inst_sram_size    (inst_sram_size   ),
    .inst_sram_wstrb   (inst_sram_wstrb  ),
    .inst_sram_addr    (inst_sram_addr   ),
    .inst_sram_wdata   (inst_sram_wdata  ),
    .inst_sram_rdata   (inst_sram_rdata  ),
    .inst_sram_addr_ok (inst_sram_addr_ok),
    .inst_sram_data_ok (inst_sram_data_ok),
    
    .data_sram_req     (data_sram_req    ),
    .data_sram_wr      (data_sram_wr     ),
    .data_sram_wstrb   (data_sram_wstrb  ),
    .data_sram_size    (data_sram_size   ),
    .data_sram_addr    (data_sram_addr   ),
    .data_sram_wdata   (data_sram_wdata  ),
    .data_sram_rdata   (data_sram_rdata  ),
    .data_sram_addr_ok (data_sram_addr_ok),
    .data_sram_data_ok (data_sram_data_ok),
     
    .debug_wb_pc       (debug_wb_pc      ),
    .debug_wb_rf_we   (debug_wb_rf_we  ),
    .debug_wb_rf_wnum  (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata (debug_wb_rf_wdata)
);

axi_bridge u_bridge(
    .clk               (aclk             ),
    .resetn            (aresetn          ),

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

    .inst_sram_en     (inst_sram_req    ),
    .inst_sram_wr      (inst_sram_wr     ),
    .inst_sram_size    (inst_sram_size   ),
    .inst_sram_wstrb   (inst_sram_wstrb  ),
    .inst_sram_addr    (inst_sram_addr   ),
    .inst_sram_wdata   (inst_sram_wdata  ),
    .inst_sram_rdata   (inst_sram_rdata  ),
    .inst_sram_addr_ok (inst_sram_addr_ok),
    .inst_sram_data_ok (inst_sram_data_ok),

    .data_sram_en     (data_sram_req    ),
    .data_sram_wr      (data_sram_wr     ),
    .data_sram_wstrb   (data_sram_wstrb  ),
    .data_sram_size    (data_sram_size   ),
    .data_sram_addr    (data_sram_addr   ),
    .data_sram_wdata   (data_sram_wdata  ),
    .data_sram_rdata   (data_sram_rdata  ),
    .data_sram_addr_ok (data_sram_addr_ok),
    .data_sram_data_ok (data_sram_data_ok)
);

endmodule