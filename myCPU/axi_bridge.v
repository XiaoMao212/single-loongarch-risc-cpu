module axi_bridge(
    input          clk    ,
    input          resetn ,
 

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


    input  [ 3:0] rid   , // slave  -> master
    input  [31:0] rdata , // slave  -> master
    input  [ 1:0] rresp , // slave  -> master, ignore
    input         rlast , // slave  -> master, ignore
    input         rvalid, // slave  -> master
    output        rready, // master -> slave


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


    output [ 3:0] wid   , // master -> slave, 4'b1
    output [31:0] wdata , // master -> slave
    output [ 3:0] wstrb , // master -> slave
    output        wlast , // master -> slave, 1'b1
    output        wvalid, // master -> slave
    input         wready, // slave  -> master


    input  [ 3:0] bid   , // slave  -> master, ignore
    input  [ 1:0] bresp , // slave  -> master, ignore
    input         bvalid, // slave  -> master
    output        bready, // master -> slave

    // inst sram interface    
    // input         inst_sram_en    ,
    // input         inst_sram_wr     ,
    // input  [ 1:0] inst_sram_size   ,
    // input  [ 3:0] inst_sram_wstrb  ,
    // input  [31:0] inst_sram_addr   ,
    // input  [31:0] inst_sram_wdata  ,
    // output [31:0] inst_sram_rdata  ,
    // output        inst_sram_addr_ok,
    // output        inst_sram_data_ok,
    // ICache
    input         icache_rd_req    ,
    input  [ 2:0] icache_rd_type   ,
    input  [31:0] icache_rd_addr   ,
    output        icache_rd_rdy    ,
    output        icache_ret_valid ,
    output        icache_ret_last  ,
    output [31:0] icache_ret_data  ,
    
    // data sram interface
    input         data_sram_en     ,
    input         data_sram_wr     ,
    input  [ 3:0] data_sram_wstrb  ,
    input  [ 1:0] data_sram_size   , 
    input  [31:0] data_sram_addr   ,
    input  [31:0] data_sram_wdata  ,
    output [31:0] data_sram_rdata  ,
    output        data_sram_addr_ok,
    output        data_sram_data_ok_l,
    output        data_sram_data_ok_s,
    
    input         ws_reflush
);

reg     ws_reflush_reg;
always @(posedge clk) begin
    if(reset) 
        ws_reflush_reg <= 1'b0;
    else if(ws_reflush & (ar_cur_state != READ_REQ_INIT || rresp_cur_state != READ_RESP_INIT || aww_cur_state != WRITE_INIT || wresp_cur_state !=  WRITE_RESP_INIT)) 
        ws_reflush_reg <= 1'b1;
    else if(ar_cur_state == READ_REQ_INIT & rresp_cur_state == READ_RESP_INIT & aww_cur_state == WRITE_INIT & wresp_cur_state ==  WRITE_RESP_INIT)
        ws_reflush_reg <= 1'b0;
end

reg         reset;
always @(posedge clk) begin
    reset <= ~resetn;
end

// 状�?�机划分
parameter READ_REQ_INIT         = 5'b00001; 
parameter READ_DATA_REQ_START   = 5'b00010; 
parameter READ_INST_REQ_START   = 5'b00100; 
parameter READ_DATA_REQ_CHECK   = 5'b01000; 
parameter READ_REQ_END          = 5'b10000; 

parameter READ_RESP_INIT        = 4'b0001; 
parameter READ_RESP_START       = 4'b0010; 
parameter READ_RESP_MID         = 4'b0100;
parameter READ_RESP_END         = 4'b1000; 

parameter WRITE_INIT            = 3'b001; 
parameter WRITE_START           = 3'b010; 
parameter WRITE_END             = 3'b100; 

parameter WRITE_RESP_INIT       = 3'b001; 
parameter WRITE_RESP_START      = 3'b010; 
parameter WRITE_RESP_END        = 3'b100; 

reg  [ 4:0] ar_cur_state;
reg  [ 4:0] ar_next_state;
reg  [ 3:0] rresp_cur_state;
reg  [ 3:0] rresp_next_state;
reg  [ 3:0] aww_cur_state;
reg  [ 3:0] aww_next_state;
reg  [ 2:0] wresp_cur_state;
reg  [ 2:0] wresp_next_state;

reg r_inst_count;
reg r_data_count;

// 状�?�切�?
always @(posedge clk) begin
    if(reset) begin
        ar_cur_state    <= READ_REQ_INIT;
        rresp_cur_state <= READ_RESP_INIT;
        aww_cur_state   <= WRITE_INIT;
        wresp_cur_state <= WRITE_RESP_INIT;
    end    
    else begin
        ar_cur_state    <= ar_next_state;
        rresp_cur_state <= rresp_next_state;
        aww_cur_state   <= aww_next_state;
        wresp_cur_state <= wresp_next_state;
    end 
end

// ar
reg [ 3:0] arid_reg;
reg [31:0] araddr_reg;
reg [ 2:0] arsize_reg;
reg        arvalid_reg;
reg [ 7:0] arlen_reg;
assign arburst  = 2'b01;
assign arlock   = 2'b0;
assign arcache  = 4'b0;
assign arprot   = 3'b0;

wire block;
reg [31:0] awaddr_block;
always @(posedge clk) begin
    if(reset)
        awaddr_block <= 32'b0;
    else if(awaddr != 32'b0)
        awaddr_block <= awaddr;
    else if(bvalid & bready)
        awaddr_block <= 32'b0;
end

assign block = (data_sram_addr == awaddr_block) && araddr != 32'b0;


always @(*) begin
    case(ar_cur_state)
        READ_REQ_INIT: begin
           // if(data_sram_en & ~data_sram_wr &rresp_next_state == READ_RESP_INIT & ~ws_reflush_reg)
           if(data_sram_en & ~data_sram_wr &rresp_next_state == READ_RESP_INIT )
                ar_next_state = READ_DATA_REQ_CHECK;
          //  else if(icache_rd_req & rresp_next_state == READ_RESP_INIT & ~ws_reflush_reg)
          else if(icache_rd_req & rresp_next_state == READ_RESP_INIT )
                ar_next_state = READ_INST_REQ_START;
            else
                ar_next_state = ar_cur_state;
        end
        
        READ_DATA_REQ_CHECK: begin
            if(block)
                ar_next_state = ar_cur_state;
            else
                ar_next_state = READ_DATA_REQ_START;
        end
        
        READ_DATA_REQ_START, READ_INST_REQ_START: begin
            if(arvalid & arready)
                ar_next_state = READ_REQ_END;
            else
                ar_next_state = ar_cur_state;
        end
        
        READ_REQ_END: begin
            ar_next_state = READ_REQ_INIT;
        end
        default:
            ar_next_state = READ_REQ_INIT;
    endcase
end

always @(posedge clk) begin
    if(reset) begin
        arid_reg    <= 4'b0;
        araddr_reg  <= 32'b0;
        arsize_reg  <= 3'b010;
        arvalid_reg <= 1'b0;
        arlen_reg   <= 8'b0;
    end 
    else if(arready) begin
        arvalid_reg <= 1'b0;
    end
    else if(ar_cur_state == READ_DATA_REQ_START) begin
        arid_reg    <= 4'b1;
        araddr_reg  <= data_sram_addr;
        arsize_reg  <= {1'b0, data_sram_size};
        arvalid_reg <= 1'b1;
        arlen_reg   <= 8'b0;
    end 
    else if(ar_cur_state == READ_INST_REQ_START) begin
        arid_reg    <= 4'b0;
        araddr_reg  <= icache_rd_addr;
        arsize_reg  <= 3'b010;
        arvalid_reg <= 1'b1;
        arlen_reg   <= {6'b0, {2{icache_rd_type[2]}}};
    end 
    else begin
        arid_reg   <= 4'b0;
        araddr_reg <= 32'b0;
        arsize_reg <= 3'b0;
        arlen_reg   <= 8'b0;
    end
end

assign arid    = arid_reg;
assign araddr  = araddr_reg;
assign arsize  = arsize_reg;
assign arvalid = arvalid_reg;
assign arlen   = arlen_reg;


// r
// ???
assign rready = rresp_cur_state[1] || rresp_cur_state[2];


always @(*) begin
    case(rresp_cur_state)
        READ_RESP_INIT: begin
            if(((arready && arvalid) || r_inst_count != 1'b0 || r_data_count != 1'b0))
                rresp_next_state = READ_RESP_START;
            else 
                rresp_next_state = rresp_cur_state;
        end

        READ_RESP_START: begin
            if(rvalid && rready && rlast)
                rresp_next_state = READ_RESP_END;
            else if(rvalid && rready)
                rresp_next_state = READ_RESP_MID;
            else 
                rresp_next_state = rresp_cur_state;
        end
  
        // ???
        READ_RESP_MID:begin
            if(rvalid && rready && rlast)
                rresp_next_state = READ_RESP_END;
            else if(rvalid && rready)
                rresp_next_state = rresp_cur_state;
            else
                rresp_next_state = READ_RESP_START;
        end
    
        READ_RESP_END: begin
            if((arready && arvalid) || r_inst_count != 1'b0 || r_data_count != 1'b0)
                rresp_next_state = READ_RESP_START;
            else
                rresp_next_state = READ_RESP_INIT;
        end

        default:
            rresp_next_state = READ_RESP_INIT;
    endcase
end

reg [3:0] rid_reg;
reg rlast_reg;
always @(posedge clk) begin
    if(reset || rresp_next_state == READ_RESP_INIT) 
        rid_reg <= 4'b0;
    else if(rvalid) 
        rid_reg <= rid;
end
always @(posedge clk) begin
    if(reset || rresp_next_state == READ_RESP_INIT) 
        rlast_reg <= 4'b0;
    else if(rvalid) 
        rlast_reg <= rlast;
end

// aw
reg [31:0] awaddr_reg;
reg [2:0]  awsize_reg;
reg        awvalid_reg;
assign awid     = 4'b1;
assign awlen    = 8'b0;
assign awburst  = 2'b1;
assign awlock   = 2'b0;
assign awcache  = 4'b0;
assign awprot   = 3'b0;

// w
reg [31:0] wdata_reg;
reg [3:0]  wstrb_reg;
reg        wvalid_reg;
assign wid      = 4'b1;
assign wlast    = 1'b1;


always @(*) begin
    case(aww_cur_state)
        WRITE_INIT: begin
          //  if(data_sram_en && data_sram_wr && ~ws_reflush_reg) 
          if(data_sram_en && data_sram_wr ) 
                aww_next_state = WRITE_START;
            else 
                aww_next_state = aww_cur_state;
        end

        WRITE_START: begin
            if(wvalid & wready)
                aww_next_state = WRITE_END;
            else
                aww_next_state = aww_cur_state;
        end

        WRITE_END: begin
            aww_next_state = WRITE_INIT;   
        end
        
        default:
            aww_next_state = WRITE_INIT;
    endcase
end

always @(posedge clk) begin
    if(reset) begin
        awaddr_reg <= 32'b0;
        awsize_reg <= 3'b0;
        awvalid_reg <= 1'b0;
        wdata_reg <= 32'b0;
        wstrb_reg <= 4'b0;
        wvalid_reg <= 1'b0;
    end 
    else if(awready | write_block) begin
        awvalid_reg <= 1'b0;
    end
    else if(wready) begin
        wvalid_reg <= 1'b0;
    end
    else if(aww_cur_state == WRITE_START) begin
        awaddr_reg <= data_sram_addr;
        awsize_reg <= {1'b0, data_sram_size};
        awvalid_reg <= 1'b1;
        wdata_reg <= data_sram_wdata;
        wstrb_reg <= data_sram_wstrb;
        wvalid_reg <= 1'b1;
    end 
    else begin
        awaddr_reg <= 32'b0;
        awsize_reg <= 3'b0;
        wvalid_reg <= 1'b0;
    end
end

reg write_block;
always @(posedge clk) begin
    if(reset) 
        write_block <= 1'b0;
    else if(awvalid && awready)
        write_block <= 1'b1;
    else if(aww_next_state == WRITE_END)
        write_block <= 1'b0;
end

assign awaddr  = awaddr_reg;
assign awsize  = awsize_reg;
assign awvalid = awvalid_reg;

assign wdata  = wdata_reg;
assign wstrb  = wstrb_reg;
assign wvalid = wvalid_reg;

//b
reg bready_reg;

// 写响应状态机
always @(*) begin
    case(wresp_cur_state)
        WRITE_RESP_INIT: begin
            if(wvalid & wready ) 
                wresp_next_state = WRITE_RESP_START;
            else
                wresp_next_state = wresp_cur_state;
        end

        WRITE_RESP_START: begin
            if(bvalid & bready)
                wresp_next_state = WRITE_RESP_END;
            else
                wresp_next_state = wresp_cur_state;
        end

        WRITE_RESP_END: begin
            if(bvalid & bready)
                wresp_next_state = wresp_cur_state;
            else
                wresp_next_state = WRITE_RESP_INIT;
        end

        default:
            wresp_next_state = WRITE_RESP_INIT;
    endcase
end

always @(posedge clk) begin
    if(reset | bvalid) 
        bready_reg <= 1'b0;
    else if(wresp_next_state == WRITE_RESP_START)
        bready_reg <= 1'b1;
    else 
        bready_reg <= 1'b0;
end

assign bready = bready_reg;

// read burst
reg [ 2:0] rd_count;
always @(posedge clk) begin
    if(~resetn)
        rd_count <= 3'b000;
    else if(rresp_cur_state[1] || rresp_cur_state[2])
        rd_count <= 3'b000;
    else if(rresp_cur_state[3] && rready & rvalid)
        rd_count <= rd_count + 3'b001;
end


always @(posedge clk) begin
    if(reset) begin
        r_inst_count <= 1'b0;
    end
    else if(arready & arvalid & ~arid[0]) begin
        r_inst_count <= r_inst_count + 1'b1;
    end
    else if (rvalid & rready & ~rid[0] & (r_inst_count== 1'b1)) begin
        r_inst_count <= r_inst_count - 1'b1;
    end
end

always @(posedge clk) begin
    if(reset) begin
        r_data_count <= 1'b0;
    end
    else if(arready & arvalid & arid[0]) begin
        r_data_count <= r_data_count + 1'b1;
    end
    else if (rvalid & rready & rid[0]) begin
        r_data_count <= r_data_count - 1'b1;
    end
end

reg [31:0] inst_sram_reg;
reg [31:0] data_sram_reg;

always @(posedge clk) begin
    if(reset) 
        inst_sram_reg <= 32'b0;
    else if(rvalid && rready && ~rid[0]) 
        inst_sram_reg <= rdata;
end

always @(posedge clk) begin 
    if(reset) 
        data_sram_reg <= 32'b0;
    else if(rvalid && rready && rid[0]) 
        data_sram_reg <= rdata;
end

// CPU interface
// assign inst_sram_addr_ok = ar_cur_state == READ_REQ_END && ~arid[0];
// assign inst_sram_data_ok = rresp_cur_state == READ_RESP_END && ~rid_reg[0];
assign data_sram_addr_ok = ((ar_cur_state == READ_REQ_END && arid[0]) || (aww_cur_state == WRITE_END));//& ~ws_reflush_reg; 
assign data_sram_data_ok_l = (rresp_cur_state == READ_RESP_END && rid_reg[0]);// & ~ws_reflush_reg; 
assign data_sram_data_ok_s =  (wresp_cur_state == WRITE_RESP_END);//& ~ws_reflush_reg; 
assign icache_rd_rdy    = (ar_cur_state == READ_REQ_END && ~arid[0]);
assign icache_ret_valid = ((|rresp_cur_state[3:2]) && ~rid_reg[0]);
//assign icache_ret_valid = rvalid && ~rid_reg[0];
//assign icache_ret_last  =  ~rid_reg[0] &&rresp_cur_state[3] && (rd_count == arlen);
assign icache_ret_last  =  (~rid_reg[0] && rlast_reg);
assign icache_ret_data  = inst_sram_reg;

//assign inst_sram_rdata = inst_sram_reg;
assign data_sram_rdata = data_sram_reg;


endmodule