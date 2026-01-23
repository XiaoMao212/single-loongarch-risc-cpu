module axi_bridge(
    input          clk    ,
    input          resetn ,

    // AXI Interface
    output [ 3:0] arid   , // master -> slave
    output [31:0] araddr , // master -> slave
    output [ 7:0] arlen  , // master -> slave
    output [ 2:0] arsize , // master -> slave
    output [ 1:0] arburst, // master -> slave
    output [ 1:0] arlock , // master -> slave
    output [ 3:0] arcache, // master -> slave
    output [ 2:0] arprot , // master -> slave
    output        arvalid, // master -> slave
    input         arready, // slave  -> master

    input  [ 3:0] rid    , // slave  -> master
    input  [31:0] rdata  , // slave  -> master
    input  [ 1:0] rresp  , // slave  -> master
    input         rlast  , // slave  -> master
    input         rvalid , // slave  -> master
    output        rready , // master -> slave

    output [ 3:0] awid   , // master -> slave
    output [31:0] awaddr , // master -> slave
    output [ 7:0] awlen  , // master -> slave
    output [ 2:0] awsize , // master -> slave
    output [ 1:0] awburst, // master -> slave
    output [ 1:0] awlock , // master -> slave
    output [ 3:0] awcache, // master -> slave
    output [ 2:0] awprot , // master -> slave
    output        awvalid, // master -> slave
    input         awready, // slave  -> master

    output [ 3:0] wid    , // master -> slave
    output [31:0] wdata  , // master -> slave
    output [ 3:0] wstrb  , // master -> slave
    output        wlast  , // master -> slave
    output        wvalid , // master -> slave
    input         wready , // slave  -> master

    input  [ 3:0] bid    , // slave  -> master
    input  [ 1:0] bresp  , // slave  -> master
    input         bvalid , // slave  -> master
    output        bready , // master -> slave

    // ICache Interface
    input         icache_rd_req    ,
    input  [ 2:0] icache_rd_type   ,
    input  [31:0] icache_rd_addr   ,
    output        icache_rd_rdy    ,
    output        icache_ret_valid ,
    output        icache_ret_last  ,
    output [31:0] icache_ret_data  ,
    
    // DCache Interface
    input         dcache_rd_req    ,
    input  [ 2:0] dcache_rd_type   ,
    input  [31:0] dcache_rd_addr   ,
    output        dcache_rd_rdy    ,
    output        dcache_ret_valid ,
    output        dcache_ret_last  ,
    output [31:0] dcache_ret_data  ,
    
    input         dcache_wr_req    ,
    input  [ 2:0] dcache_wr_type   ,
    input  [31:0] dcache_wr_addr   ,
    input  [ 3:0] dcache_wr_wstrb  ,
    input  [127:0]dcache_wr_data   ,
    output        dcache_wr_rdy    ,
    
    input    [1:0]  data_sram_size   ,
    
    output          data_finish    ,
    output          data_prepared
);

    reg         reset;
    always @(posedge clk) begin
        reset <= ~resetn;
    end

    // 状态机定义 (保持原样)
    parameter READ_REQ_INIT       = 5'b00001; 
    parameter READ_DATA_REQ_START = 5'b00010; // 这里虽然叫 DATA_REQ，但实际上是复用给 DCache 读
    parameter READ_INST_REQ_START = 5'b00100; // ICache 读
    parameter READ_DATA_REQ_CHECK = 5'b01000; // 暂时保留，但 Cache 模式下可能不再需要 Check
    parameter READ_REQ_END        = 5'b10000; 

    parameter READ_RESP_INIT      = 4'b0001; 
    parameter READ_RESP_START     = 4'b0010; 
    parameter READ_RESP_MID       = 4'b0100;
    parameter READ_RESP_END       = 4'b1000; 

    parameter WRITE_INIT          = 3'b001; 
    parameter WRITE_START         = 3'b010; 
    parameter WRITE_END           = 3'b100; 

    parameter WRITE_RESP_INIT     = 3'b001; 
    parameter WRITE_RESP_START    = 3'b010; 
    parameter WRITE_RESP_END      = 3'b100; 

    reg  [ 4:0] ar_cur_state, ar_next_state;
    reg  [ 3:0] rresp_cur_state, rresp_next_state;
    reg  [ 3:0] aww_cur_state, aww_next_state;
    reg  [ 2:0] wresp_cur_state, wresp_next_state;

    // 状态机切换
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

    // ---------------------------------------------------------------
    // AR 通道处理
    // ---------------------------------------------------------------
    reg [ 3:0] arid_reg;
    reg [31:0] araddr_reg;
    reg [ 2:0] arsize_reg;
    reg        arvalid_reg;
    reg [ 7:0] arlen_reg;

    always @(*) begin
        case(ar_cur_state)
            READ_REQ_INIT: begin
                // 优先处理 D-Cache 读
                if(dcache_rd_req && rresp_cur_state == READ_RESP_INIT)
                    ar_next_state = READ_DATA_REQ_START;
                // 然后处理 I-Cache 读
                else if(icache_rd_req && rresp_cur_state == READ_RESP_INIT)
                    ar_next_state = READ_INST_REQ_START;
                else
                    ar_next_state = ar_cur_state;
            end
            
            // 此状态在 Cache 模式下可以跳过，或用于握手等待
            READ_DATA_REQ_CHECK: begin 
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
        else if(arready && arvalid) begin
            arvalid_reg <= 1'b0;
        end
        else if(ar_cur_state == READ_REQ_INIT && ar_next_state == READ_DATA_REQ_START) begin
            arid_reg    <= 4'b1; // D-Cache ID = 1
            araddr_reg  <= dcache_rd_addr;
            arsize_reg  <= 3'b010;
            arvalid_reg <= 1'b1;
            // 4'b100 (BLOCK) 对应 arlen = 3 (4次传输)，否则为 0
            arlen_reg   <= (dcache_rd_type == 3'b100) ? 8'd3 : 8'd0;
        end 
        else if(ar_cur_state == READ_REQ_INIT && ar_next_state == READ_INST_REQ_START) begin
            arid_reg    <= 4'b0; // I-Cache ID = 0
            araddr_reg  <= icache_rd_addr;
            arsize_reg  <= 3'b010;
            arvalid_reg <= 1'b1;
            arlen_reg   <= (icache_rd_type == 3'b100) ? 8'd3 : 8'd0;
        end 
    end

    assign arid    = arid_reg;
    assign araddr  = araddr_reg;
    assign arsize  = arsize_reg;
    assign arvalid = arvalid_reg;
    assign arlen   = arlen_reg;
    assign arburst = 2'b01;
    assign arlock  = 2'b0;
    assign arcache = 4'b0;
    assign arprot  = 3'b0;

    // ---------------------------------------------------------------
    // R 通道处理
    // ---------------------------------------------------------------
    assign rready = rresp_cur_state[1] || rresp_cur_state[2]; // START or MID

    always @(*) begin
        case(rresp_cur_state)
            READ_RESP_INIT: begin
                if(arvalid && arready) // 请求发出去就开始等响应
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
      
            READ_RESP_MID:begin
                if(rvalid && rready && rlast)
                    rresp_next_state = READ_RESP_END;
                else if(rvalid && rready)
                    rresp_next_state = rresp_cur_state; // 继续接收中间数据
                else
                    rresp_next_state = READ_RESP_START; // 这里逻辑有点怪，通常保持 MID 即可，但为了不改你原逻辑...
            end
        
            READ_RESP_END: begin
                rresp_next_state = READ_RESP_INIT;
            end

            default:
                rresp_next_state = READ_RESP_INIT;
        endcase
    end

    // 路由数据到 Cache
    assign icache_ret_valid = rvalid && (rid == 4'd0);
    assign icache_ret_last  = rlast;
    assign icache_ret_data  = rdata;

    assign dcache_ret_valid = rvalid && (rid == 4'd1);
    assign dcache_ret_last  = rlast;
    assign dcache_ret_data  = rdata;

    // 反馈给 Cache 的 Ready 信号
    // 只有在 INIT 状态且真正接受请求时拉高
    assign icache_rd_rdy = (ar_cur_state == READ_REQ_END && arid_reg == 4'd0);
    assign dcache_rd_rdy = (ar_cur_state == READ_REQ_END && arid_reg == 4'd1);


    // ---------------------------------------------------------------
    // AW & W 通道处理 (增加 Burst 写逻辑)
    // ---------------------------------------------------------------
    reg [31:0] awaddr_reg;
    reg [ 2:0] awsize_reg;
    reg        awvalid_reg;
    reg [ 7:0] awlen_reg;
    
    // 写数据 Buffer 和计数器
    reg [127:0] wdata_buffer;
    reg [  1:0] w_count;
    
    reg [31:0] wdata_reg;
    reg [ 3:0] wstrb_reg;
    reg        wvalid_reg;
    reg        wlast_reg;

    always @(*) begin
        case(aww_cur_state)
            WRITE_INIT: begin
                if(dcache_wr_req && wresp_cur_state == WRITE_RESP_INIT) 
                    aww_next_state = WRITE_START;
                else 
                    aww_next_state = aww_cur_state;
            end

            WRITE_START: begin
                // 原逻辑在这里直接跳 WRITE_END，现在需要发完所有 Burst 数据
                if(wvalid & wready & (w_count == awlen_reg[1:0])) // 只有当发完最后一个才结束
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
wire wlast_wire;
// 当计数器达到长度限制，且当前正在握手时，wlast 立即为 1
assign wlast_wire = (w_count == awlen_reg); 
    
 // 输出端口直接连 wire
 assign wlast = wlast_wire & wvalid_reg; // 只有 valid 有效时 last 才有效
    // AW 和 数据锁存逻辑
    always @(posedge clk) begin
        if(reset) begin
            awaddr_reg <= 32'b0;
            awsize_reg <= 3'b0;
            awvalid_reg <= 1'b0;
            awlen_reg   <= 8'b0;
            wstrb_reg   <= 4'h0;
            wdata_buffer <= 128'b0;
            w_count      <= 2'd0;
            wvalid_reg   <= 1'b0;
            wlast_reg    <= 1'b0;
        end 
        else if(awready && awvalid) begin
            awvalid_reg <= 1'b0; // 地址握手完成
        end
        else if(aww_cur_state == WRITE_INIT && aww_next_state == WRITE_START) begin
            // 锁存请求
            awaddr_reg <= dcache_wr_addr;
            awsize_reg  <= {1'b0, data_sram_size};
            awvalid_reg <= 1'b1;
            
            wdata_buffer <= dcache_wr_data;
            w_count      <= 2'd0;
            
            // 判断是否是 Block 写 (3'b100)
            if (dcache_wr_type == 3'b100) begin
                awlen_reg <= 8'd3; // 4 beats
                wstrb_reg <= 4'hf;
            end else begin
                awlen_reg <= 8'd0; // 1 beat
                wstrb_reg <= dcache_wr_wstrb; 
            end
            
            wvalid_reg <= 1'b1;
        end 
        
        // Burst 发送逻辑
        if (aww_cur_state == WRITE_START) begin
            // 生成 wlast
          //  if (w_count == awlen_reg[1:0]) 
           //     wlast_reg <= 1'b1;
           // else 
           //     wlast_reg <= 1'b0;

            // 握手成功，准备下一个数据
            if (wvalid && wready) begin
                if (wlast_wire) begin
                    wvalid_reg <= 1'b0; // 全部发完
                    w_count  <= 1'b0;
                end else begin
                    w_count <= w_count + 1'b1; // 继续发下一个
                end
            end
        end
    end

    // WDATA MUX (根据 w_count 选择 32位数据)
    always @(*) begin
        case(w_count)
            2'd0: wdata_reg = wdata_buffer[31:0];
            2'd1: wdata_reg = wdata_buffer[63:32];
            2'd2: wdata_reg = wdata_buffer[95:64];
            2'd3: wdata_reg = wdata_buffer[127:96];
        endcase
        
        // WSTRB MUX
      //  if (awlen_reg == 8'd3 ) wstrb_reg = 4'hf; // Uncached
      //  else wstrb_reg = dcache_wr_wstrb; // Cached Block Write
    end

    assign awid     = 4'b1;
    assign awaddr   = awaddr_reg;
    assign awsize   = awsize_reg;
    assign awlen    = awlen_reg;
    assign awburst  = 2'b01;
    assign awlock   = 2'b0;
    assign awcache  = 4'b0;
    assign awprot   = 3'b0;
    assign awvalid  = awvalid_reg;

    assign wid      = 4'b1;
    assign wdata    = wdata_reg;
    assign wstrb    = wstrb_reg;
    //assign wlast    = wlast_reg;
    assign wvalid   = wvalid_reg;

    // ---------------------------------------------------------------
    // B 通道处理
    // ---------------------------------------------------------------
    reg bready_reg;
    always @(*) begin
        case(wresp_cur_state)
            WRITE_RESP_INIT: begin
                // W 通道发完最后一个数据后，进入等待 B 响应状态
                if(aww_cur_state == WRITE_END) 
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
                // 等待一个周期，确保 Cache 收到 Ready
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


    assign dcache_wr_rdy = (aww_cur_state == WRITE_END);
    
    
assign data_finish = bready && bvalid ;
assign data_prepared = wvalid & wready;
endmodule