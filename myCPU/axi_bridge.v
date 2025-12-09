//将cpu的类SRAM接口转换成AXI接口
module axi_bridge(
    input          clk    ,
    input          resetn ,
 
    // ar 读请求
    output [ 3:0] arid   , // master -> slave  读ID，取指为0，取数为1，由转接桥仲裁是取指还是取数，外部只认ID
    //之前实验是有指令RAM和数据RAM两个IP，现在只有一个IP，二合一了吗？
    output [31:0] araddr , // master -> slave
    output [ 7:0] arlen  , // master -> slave, 8'b0
    //读请求长度，目前设置为0拍，表示一次只取一个地址的数值，设置cache的时候可以改变len
    output [ 2:0] arsize , // master -> slave
    //每拍传递的数据的字节数，读请求应该固定为四个字节
    output [ 1:0] arburst, // master -> slave, 2'b1
    //设置为地址递增的方式，当设置一拍的时候，不仅要取读请求地址的数据，还要取读地址下一个地址的数据
    //当前是0拍，所以没啥用
    //当我们设置了cache的时候，会根据需要改变len和burst，一个请求读取多个数值
    output [ 1:0] arlock , // master -> slave, 2'b0
    output [ 3:0] arcache, // master -> slave, 4'b0
    output [ 2:0] arprot , // master -> slave, 3'b0
    //以上三个分别为原子锁，cache属性，保护属性，先不考虑，全部置0
    output        arvalid, // master -> slave
    input         arready, // slave  -> master

    // r 读相应
    input  [ 3:0] rid   , // slave  -> master
    input  [31:0] rdata , // slave  -> master
    //本次读请求是否成功完成，目前是都会成功，为什么设置了两个字节
    input  [ 1:0] rresp , // slave  -> master, ignore
    //有效时表示是最后一个传输给cpu的数据，但我们每次只取一个数据
    input         rlast , // slave  -> master, ignore
    //valid相当于_to__valid，ready相当于_ _allowin，valid一定不能依赖于ready
    input         rvalid, // slave  -> master
    output        rready, // master -> slave

    // aw 写请求
    //写请求ID恒为1
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

    // w 写数据
    output [ 3:0] wid   , // master -> slave, 4'b1
    output [31:0] wdata , // master -> slave
    output [ 3:0] wstrb , // master -> slave
    output        wlast , // master -> slave, 1'b1
    output        wvalid, // master -> slave
    input         wready, // slave  -> master

    // b 写相应
    input  [ 3:0] bid   , // slave  -> master, ignore
    //写请求是否成功完成
    input  [ 1:0] bresp , // slave  -> master, ignore
    input         bvalid, // slave  -> master
    output        bready, // master -> slave

    // inst sram interface    
    input         inst_sram_en    ,
    input         inst_sram_wr     ,
    input  [ 1:0] inst_sram_size   ,
    input  [ 3:0] inst_sram_wstrb  ,
    input  [31:0] inst_sram_addr   ,
    input  [31:0] inst_sram_wdata  ,
    output [31:0] inst_sram_rdata  ,
    output        inst_sram_addr_ok,
    output        inst_sram_data_ok,
    
    // data sram interface
    input            data_sram_en    ,
    input            data_sram_wr     ,
    input  [ 3:0] data_sram_wstrb  ,
    input  [ 1:0] data_sram_size   , 
    input  [31:0] data_sram_addr   ,
    input  [31:0] data_sram_wdata  ,
    output [31:0] data_sram_rdata  ,
    output        data_sram_addr_ok,
    output        data_sram_data_ok
);

reg         reset;
always @(posedge clk) begin
    reset <= ~resetn;
end

// read_req，读请求，五个状态，初始化状态，读数据检查状态（检查是否有写内存的动作，有就不发送读请求，但我感觉可以发啊，ID都是1，是同一个事务会按照顺序执行）
//有读数据请求且写数据动作执行完毕或者没有写数据请求的状态，读指令请求状态（inst_sram_en=1），读指令请求能够成功发送的状态（valid=1&ready=1）
parameter READ_REQ_INIT         = 5'b00001; 
parameter READ_DATA_REQ_START   = 5'b00010; 
parameter READ_INST_REQ_START   = 5'b00100; 
parameter READ_DATA_REQ_CHECK   = 5'b01000; 
parameter READ_REQ_END          = 5'b10000; 
//读响应通道
//状态机，没有读请求的时候是INIT，发出读请求时START，接收读响应的时候是END
//req只管发送成功前的状态
//resp只管发送成功后的状态
parameter READ_RESP_INIT        = 3'b001; 
parameter READ_RESP_START       = 3'b010; 
parameter READ_RESP_END         = 3'b100; 

//没有写请求的时候是INIT，有写请求时START，写数据请求能够成功发送的时候是END（req）（写请求一定在写数据之前发送吗）
//只管发送成功前的状态
parameter WRITE_INIT            = 3'b001; 
parameter WRITE_START           = 3'b010; 
parameter WRITE_END             = 3'b100; 

//只管发送成功后的状态
parameter WRITE_RESP_INIT       = 3'b001; 
parameter WRITE_RESP_START      = 3'b010; 
parameter WRITE_RESP_END        = 3'b100; 

//当前写请求的状态
reg  [ 4:0] ar_cur_state;
reg  [ 4:0] ar_next_state;
//当前写响应的状态
reg  [ 2:0] rresp_cur_state;
reg  [ 2:0] rresp_next_state;
reg  [ 3:0] aww_cur_state;
reg  [ 3:0] aww_next_state;
reg  [ 2:0] wresp_cur_state;
reg  [ 2:0] wresp_next_state;
///当前读指令请求的个数
///当前读数据请求的个数
reg r_inst_count;
reg r_data_count;


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

// ar 读请求发出信号的存储
reg [ 3:0] arid_reg;
reg [31:0] araddr_reg;
reg [ 2:0] arsize_reg;
reg        arvalid_reg;
//固定值不需要存储
assign arlen    = 8'b0;
assign arburst  = 2'b1;
assign arlock   = 2'b0;
assign arcache  = 4'b0;
assign arprot   = 3'b0;

//写地址
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
//读请求地址和写请求地址一致，则阻塞读请求
assign block = (data_sram_addr == awaddr_block) && araddr != 32'b0;

// 组合逻辑
//读请求通道
// read_req，读请求，五个状态，初始化状态，读数据检查状态（检查是否有写内存的动作，有就不发送读请求，但我感觉可以发啊，ID都是1，是同一个事务会按照顺序执行）
//有读数据请求且写数据动作执行完毕或者没有写数据请求的状态，读指令请求状态（inst_sram_en=1），读指令请求能够成功发送的状态（valid=1&ready=1）
always @(*) begin
    case(ar_cur_state)
        READ_REQ_INIT: begin
            if(data_sram_en & ~data_sram_wr)
                ar_next_state = READ_DATA_REQ_CHECK;
            else if(inst_sram_en)
                ar_next_state = READ_INST_REQ_START;
            else
                ar_next_state = ar_cur_state;
        end
        
        READ_DATA_REQ_CHECK: begin
          //  if(block)//若读地址和写地址一致且写地址不是0，则读请求一直处于check状态
          //      ar_next_state = ar_cur_state;
          //  else
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
        arsize_reg  <= 3'b0;
        arvalid_reg <= 1'b0;
    end 
    else if(arready) begin//已经握手完毕，下一个周期valid=0
        arvalid_reg <= 1'b0;
    end
    else if(ar_cur_state == READ_DATA_REQ_START) begin
        arid_reg    <= 4'b1;                 //读数据ID是1
        araddr_reg  <= data_sram_addr;
        arsize_reg  <= {1'b0, data_sram_size};//都读四个字节
        arvalid_reg <= 1'b1;
    end 
    else if(ar_cur_state == READ_INST_REQ_START) begin
        arid_reg    <= 4'b0;                //读指令ID是0
        araddr_reg  <= inst_sram_addr;
        arsize_reg  <= {1'b0, inst_sram_size};
        arvalid_reg <= 1'b1;
    end 
    else begin
        arid_reg   <= 4'b0;
        araddr_reg <= 32'b0;
        arsize_reg <= 3'b0;
    end
end

assign arid    = arid_reg;
assign araddr  = araddr_reg;
assign arsize  = arsize_reg;
assign arvalid = arvalid_reg;


// r  读相应接收，当有读请求且没有读相应的时候，rready=1
assign rready = r_inst_count != 1'b0 || r_data_count != 1'b0;

// 没有读请求的时候是INIT，发出读请求时START，接收读响应的时候是END
//req只管发送成功前的状态
//resp只管发送成功后的状态
always @(*) begin
    case(rresp_cur_state)
        READ_RESP_INIT: begin
            if((arready && arvalid) || r_inst_count != 1'b0 || r_data_count != 1'b0)//此刻有读请求成功发送或者之前有
                rresp_next_state = READ_RESP_START;
            else 
                rresp_next_state = rresp_cur_state;
        end

        READ_RESP_START: begin
            if(rvalid && rready)
                rresp_next_state = READ_RESP_END;
            else 
                rresp_next_state = rresp_cur_state;
        end

        READ_RESP_END: begin
            if(rvalid & rready)
                rresp_next_state = rresp_cur_state;
            else if(r_inst_count != 1'b0 || r_data_count != 1'b0)
                rresp_next_state = READ_RESP_START;
            else
                rresp_next_state = READ_RESP_INIT;
        end

        default:
            rresp_next_state = READ_RESP_INIT;
    endcase
end

reg [3:0] rid_reg;
always @(posedge clk) begin
    if(reset || rresp_next_state == READ_RESP_INIT) 
        rid_reg <= 4'b0;
    else if(rvalid) // rresp_next_state != READ_RESP_INIT说明当前处于成功发送读请求未接收读响应阶段或者成功接收读响应阶段，valid为1，则是成功接收读响应阶段
        rid_reg <= rid;
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

//没有写请求的时候是INIT，有写请求时START，写数据响应能够成功发送的时候是END（req），写请求一定在写数据前发送吗
//只管发送成功前的状态
always @(*) begin
    case(aww_cur_state)
        WRITE_INIT: begin
            if(data_sram_en && data_sram_wr) 
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
    else if(awready | write_block) begin//正好成功发送写请求或者已经成功发送写请求且没有发送写数据
        awvalid_reg <= 1'b0;
    end
    else if(wready) begin//正好成功发送写数据，避免valid连续多个周期为1，多次发送同一条写请求
        wvalid_reg <= 1'b0;
    end
    else if(aww_cur_state == WRITE_START) begin//有写请求，把写请求和写数据打入触发器，先不管ready是否有效
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

//成功发送写请求，没有成功发送写数据请求block置为1
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

// 只管发送成功后的状态
always @(*) begin
    case(wresp_cur_state)
        WRITE_RESP_INIT: begin
            if(wvalid & wready) 
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


always @(posedge clk) begin
    if(reset) begin
        r_inst_count <= 1'b0;
    end
    else if(arready & arvalid & ~arid[0]) begin
        r_inst_count <= r_inst_count + 1'b1;
    end
    else if (rvalid & rready & ~rid[0]) begin
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
assign inst_sram_addr_ok = ar_cur_state == READ_REQ_END && ~arid[0];
assign inst_sram_data_ok = rresp_cur_state == READ_RESP_END && ~rid_reg[0];
assign data_sram_addr_ok = (ar_cur_state == READ_REQ_END && arid[0]) || (aww_cur_state == WRITE_END); 
assign data_sram_data_ok = (rresp_cur_state == READ_RESP_END && rid_reg[0]) || (wresp_cur_state == WRITE_RESP_END); 

assign inst_sram_rdata = inst_sram_reg;
assign data_sram_rdata = data_sram_reg;


endmodule