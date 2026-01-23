module dcache(
    input        clk        ,
    input        resetn     ,
    // 新增：Uncached 信号
    input        uncached   , // <--- 新增端口

    // Cache and CPU
    input   wire      valid     , // request is valid
    input         op        , // the request type(write is 1 and read is 0)
    input  [ 7:0] index     , // the index of address
    input  [19:0] tag       , // paddr's tag
    input  [ 3:0] offset    , // the offset of address
    input  [ 3:0] wstrb     , // the write byte enable signal
    input  [31:0] wdata     , // the write data
    output        addr_ok   , // the request's address transport is ok
    output        data_ok   , // the request's data transport is ok
    output [31:0] rdata     , // the result of read cache
    
    // Cache and AXI
    output        rd_req    , // the read request is valid
    output [  2:0] rd_type  , // the read request type
    output [ 31:0] rd_addr  , // the start address of read request
    input         rd_rdy    , // the handshake signal
    input         ret_valid , // the return data is valid
    input         ret_last  , // the return data is one read request's last
    input  [ 31:0] ret_data , // read return data
    output        wr_req    , // write request valid
    output [  2:0] wr_type  , // write request type
    output [ 31:0] wr_addr  , // the start address of write request
    output [  3:0] wr_wstrb , // the mask of write byte
    output [127:0] wr_data  , // the write data
    input         wr_rdy    ,  // the handshake signal    
    input         data_finish,
    input         data_prepared,
    //exp23
    input         cacop_req,      // 请求有效
    input  [ 4:0] cacop_op,       // 操作码
    input  [31:0] cacop_addr,     // 操作地址
    output reg    cacop_complete  // 完成信号
);

// CPU to cache request type(op)
parameter READ  = 1'b0;
parameter WRITE = 1'b1;

// cache to sram read/write type
parameter BYTE      = 3'b000;
parameter HALFWORD  = 3'b001;
parameter WORD      = 3'b010;
parameter BLOCK     = 3'b100; // Cache Line

// the in/output signal of tagv_ram and data_ram
wire [ 7:0] tagv_addr;
wire [20:0] tagv_wdata;
wire [20:0] tagv_w0_rdata, tagv_w1_rdata;
wire        tagv_w0_en, tagv_w1_en;
wire        tagv_w0_we, tagv_w1_we;
wire [ 7:0] data_addr;
wire [31:0] data_wdata;
wire [31:0] data_w0_b0_rdata, data_w0_b1_rdata, data_w0_b2_rdata, data_w0_b3_rdata, data_w1_b0_rdata, data_w1_b1_rdata, data_w1_b2_rdata, data_w1_b3_rdata;
wire        data_w0_b0_en, data_w0_b1_en, data_w0_b2_en, data_w0_b3_en, data_w1_b0_en, data_w1_b1_en, data_w1_b2_en, data_w1_b3_en;
wire [ 3:0] data_w0_b0_we, data_w0_b1_we, data_w0_b2_we, data_w0_b3_we, data_w1_b0_we, data_w1_b1_we, data_w1_b2_we, data_w1_b3_we;
reg [255:0] dirty_way0;
reg [255:0] dirty_way1;

// the state
wire lookup;
wire hitwrite;
wire replace;
wire refill;
// main FSM
// 扩展状态机，增加 UNCACHED 状态
// 修改状态参数
parameter IDLE     = 7'b0000001;
parameter LOOKUP   = 7'b0000010;
parameter MISS     = 7'b0000100;
parameter REPLACE  = 7'b0001000;
parameter REFILL   = 7'b0010000;
parameter UNCACHED = 7'b0100000;
parameter STATE_CACOP = 7'b1000000; // [新增]

reg [6:0] current_state; // [修改位宽]
reg [6:0] next_state;    // [修改位宽]

// write buffer FSM
parameter WRITEBUF_IDLE  = 2'b01;
parameter WRITEBUF_WRITE = 2'b10;
reg [1:0] writebuf_cur_state;
reg [1:0] writebuf_next_state;

// request buffer
reg        reg_op;
reg [ 7:0] reg_index;
reg [19:0] reg_tag;
reg [ 3:0] reg_offset;
reg [ 3:0] reg_wstrb;
reg [31:0] reg_wdata;
reg        reg_uncached; // <--- 新增：锁存 uncached 信号

// tag compare
wire        way0_v, way1_v;
wire [19:0] way0_tag, way1_tag;
wire        way0_hit, way1_hit;
wire        cache_hit;

// data select
wire [127:0] way0_data, way1_data;
wire [ 31:0] way0_load_word, way1_load_word;
wire [ 31:0] load_res;

// miss buffer
reg  [ 1:0]  refill_word_counter; 
wire         replace_way;
wire [127:0] replace_data;

// LFSR 
reg [2:0] lfsr;

// write buffer
reg        write_way;
reg [ 1:0] write_bank;
reg [ 7:0] write_index;
reg [ 3:0] write_strb;
reg [31:0] write_data;

// refill data
wire [31:0] refill_word;
wire [31:0] byte_word;
// other 
wire       replace_block_dirty;
reg         reset;

// 新增：检测 Uncached 写命中情况
// 必须在 LOOKUP 阶段检测，因为 cache_hit 信号在 LOOKUP 阶段有效
wire uncached_hit_invalidate = (current_state == LOOKUP) && (reg_op == WRITE) && reg_uncached && cache_hit;

//exp23
wire [1:0] cacop_func = cacop_op[4:3];
wire op_init    = (cacop_func == 2'd0); // Init (Store Tag)
wire op_idx_inv = (cacop_func == 2'd1); // Index Invalidate
wire op_hit_inv = (cacop_func == 2'd2); // Hit Invalidate
// [修正] Way 选择逻辑 (Index 模式)
// 文档：操作该 Cache 的第 VA[Way-1:0] 路
// 假设 Cache 是 2 路组相联 (Way bits = 1)，则使用 VA 的第 0 位
wire cacop_way0_idx = (cacop_addr[0] == 1'b0);
wire cacop_way1_idx = (cacop_addr[0] == 1'b1);
// 3. 确定是否写 Tag RAM (修改 Valid 位)
// Init/Index 模式: 强制写选中的 Way
// Hit 模式: 只有命中时才写对应的 Way
// 只有当 Writeback 完成 (或不需要 WB) 时，才允许写入 Tag RAM 进行无效化
wire cacop_op_ready = !cacop_need_wb || cacop_wb_done;

wire cacop_w0_en = (current_state == STATE_CACOP) && cacop_op_ready && (
                    (op_init    && cacop_way0_idx) ||
                    (op_idx_inv && cacop_way0_idx) ||
                    (op_hit_inv && way0_hit)          // Hit 模式复用原有的 hit 信号
                     );
wire cacop_w1_en = (current_state == STATE_CACOP) && cacop_op_ready && (
                    (op_init    && cacop_way1_idx) ||
                    (op_idx_inv && cacop_way1_idx) ||
                    (op_hit_inv && way1_hit)
                     );
//  CACOP 写回 (Writeback) 逻辑
// 1. 确定操作的目标路 (Target Way)
// Hit模式：谁命中选谁；Index模式：按地址位选
// 注意：Hit模式下如果没有命中，target_way 无意义，但后续逻辑会用 way_hit 屏蔽，所以没关系
wire cacop_target_way = op_hit_inv ? way1_hit : cacop_addr[0];
// 2. 获取目标行的脏状态 (Dirty Status)
// 必须在 STATE_CACOP 且计数器 >= 1 时(RAM读出后)才有效
wire way0_dirty = dirty_way0[reg_index] && way0_v;
wire way1_dirty = dirty_way1[reg_index] && way1_v;
wire target_dirty = (cacop_target_way == 1'b0) ? way0_dirty : way1_dirty;

// 3. 判断是否需要写回 (Need Writeback)
// 条件：(Index操作 且 目标脏) 或 (Hit操作 且 命中 且 目标脏)
 wire cacop_need_wb = (current_state == STATE_CACOP) && (
                      (op_idx_inv && target_dirty) || 
                      (op_hit_inv && cache_hit && target_dirty)
                       );

                       

always @(posedge clk) begin
    reset <= ~resetn;
end     

/**
    main FSM
*/
always @(posedge clk) begin
    if(reset)
        current_state <= IDLE;
    else 
        current_state <= next_state;
end

always @(*) begin
    case(current_state)
    IDLE: begin
        if (cacop_req) 
            next_state = STATE_CACOP;
        else if(valid && (~read_write_hazard)&& !cacop_req)
            next_state = LOOKUP;
        else
            next_state = IDLE;
    end
    LOOKUP: begin
       
        // 在 LOOKUP 阶段发起请求，握手成功后再跳转
        if (reg_uncached) begin
            if (reg_op == READ && rd_rdy) 
                next_state = UNCACHED;    // 读请求被接受，去等待数据
            else if (reg_op == WRITE && wr_rdy)
                next_state = UNCACHED;    // 写请求被接受，去等待完成(或直接回IDLE)
            else
                next_state = LOOKUP;      // 握手未成功，保持 LOOKUP
        end
        else if(cache_hit && (~valid || read_write_hazard || load_store_hazard && writebuf_cur_state == 2'b1)||op==0 && writebuf_cur_state ==  WRITEBUF_WRITE) begin
            next_state = IDLE;
        end
        else if(cache_hit && valid) begin
            next_state = LOOKUP;
        end
        else begin
            next_state = MISS;
        end
    end
    MISS: begin
        if(wr_rdy || (~replace_block_dirty))
            next_state = REPLACE;
        else
            next_state = MISS;
    end
    REPLACE: begin
        if(rd_rdy)
            next_state = REFILL;
        else
            next_state = REPLACE;
    end
    REFILL: begin
        if(ret_valid && ret_last)
            next_state = IDLE;
        else
            next_state = REFILL;
    end
    // UNCACHED 状态处理
    UNCACHED: begin
        if (reg_op == READ && ret_valid) 
            next_state = IDLE; // 读到数据就结束
        else if (reg_op == WRITE && data_finish) 
            next_state = IDLE; // 写响应完成 
        else 
            next_state = UNCACHED;
    end
    STATE_CACOP: begin
        if (cacop_complete) 
            next_state = IDLE;
         else 
            next_state = STATE_CACOP;
    end
    default:
        next_state = IDLE;
    endcase
end

// [修改] CACOP 计数器与握手控制
    // cacop_cnt: 
    // 0: 刚进入，Tag RAM/Data RAM 读地址准备
    // 1: RAM 数据读出。判断是否 dirty。如果 dirty -> 拉高 wr_req。
    // Wait: 等待 wr_rdy。
    // Done: 写 Tag RAM (清 Valid)。

    reg [1:0] cacop_cnt;
    
    always @(posedge clk) begin
        if (reset) begin
            cacop_complete <= 1'b0;
            cacop_cnt      <= 2'b0;
            cacop_wb_done  <= 1'b0;
        end
        else if (current_state == STATE_CACOP) begin
            cacop_cnt <= cacop_cnt + 1'b1;
            
            // 逻辑分支：
            // 1. 如果需要写回，且还没完成
            if (cacop_need_wb && !cacop_wb_done) begin
                // 冻结计数器，防止在写回完成前置 complete
                cacop_cnt <= 2'd2; // 保持在非0状态
                
                // 等待 AXI 握手 (wr_rdy)
                // 注意：wr_req 拉高后，当 wr_rdy 为高时，表示地址已握手，可以认为写回指令已发出
                if (wr_rdy) begin
                    cacop_wb_done <= 1'b1;
                end
            end
            // 2. 如果不需要写回，或者写回刚完成
            else if (cacop_cnt >= 2'd2) begin 
                // 此时 cacop_op_ready 为真，Tag RAM 正在被写入 0
                cacop_complete <= 1'b1;
            end
        end
        else begin
            cacop_complete <= 1'b0;
            cacop_cnt      <= 2'b0;
            cacop_wb_done  <= 1'b0;
        end
    end

/**
    write buffer FSM (保持不变)
*/
always @(posedge clk) begin
    if(reset)
        writebuf_cur_state <= WRITEBUF_IDLE;
    else
        writebuf_cur_state <= writebuf_next_state;
end

always @(*) begin
    case(writebuf_cur_state)
    WRITEBUF_IDLE: begin
        // 注意：Uncached 模式下不会触发 hitwrite
        if((current_state == LOOKUP) && (op == WRITE) && cache_hit && !reg_uncached)
            writebuf_next_state = WRITEBUF_WRITE;
        else
            writebuf_next_state = WRITEBUF_IDLE;
    end
    WRITEBUF_WRITE: begin
        if((current_state == LOOKUP) && (op == WRITE) && cache_hit && !reg_uncached)
            writebuf_next_state = WRITEBUF_WRITE;
        else
            writebuf_next_state = WRITEBUF_IDLE;
    end
    default:
        writebuf_next_state = WRITEBUF_IDLE;
    endcase
end

/**
    data path other than Cache table
*/
// request buffer
always @(posedge clk) begin
    if(reset) begin
        reg_op     <= 1'b0;
        reg_index  <= 8'b0;
        reg_tag    <= 20'b0;
        reg_offset <= 4'b0;
        reg_wstrb  <= 4'b0;
        reg_wdata  <= 32'b0;
        reg_uncached <= 1'b0; 
    end
    else if( current_state==IDLE && cacop_req) begin
        // Index 来自虚拟地址
        // 假设 index 位域是 [11:4] (256 lines)
        reg_index <= cacop_addr[11:4]; 
        
        // Tag 处理：
        // Hit 模式 (code[4:3]=2): 需要比较物理 Tag，锁存 input tag (此时 MEM 已完成转换)
        // Index 模式: Tag 不重要，置 0 即可
        if (op_hit_inv) begin
            reg_tag <= tag; 
        end else begin
            reg_tag <= 20'b0;
        end
        // 清除 uncached 标志，防止 CACOP 误触发 uncached 逻辑
        reg_uncached <= 1'b0;  
        end
    else if(lookup == 1) begin
        reg_op     <= op;
        reg_index  <= index;
        reg_tag    <= tag;
        reg_offset <= offset;
        reg_wstrb  <= wstrb;
        reg_wdata  <= wdata;
        reg_uncached <= uncached; 
    end
   
end

// Tag Compare
assign {way0_tag, way0_v} = tagv_w0_rdata;
assign {way1_tag, way1_v} = tagv_w1_rdata;
assign way0_hit  = way0_v && (way0_tag == reg_tag);
assign way1_hit  = way1_v && (way1_tag == reg_tag);
assign cache_hit = (way0_hit || way1_hit); // Uncached 时忽略此信号

// Data Select
assign way0_data = {data_w0_b3_rdata, data_w0_b2_rdata, data_w0_b1_rdata, data_w0_b0_rdata};
assign way1_data = {data_w1_b3_rdata, data_w1_b2_rdata, data_w1_b1_rdata, data_w1_b0_rdata};
assign way0_load_word = way0_data[reg_offset[3:2]*32 +: 32];
assign way1_load_word = way1_data[reg_offset[3:2]*32 +: 32];

// <--- 修改：load_res 增加 Uncached 旁路数据选择
assign load_res = {32{current_state == UNCACHED}} & ret_data | 
                  {32{way1_hit}} & way1_load_word |
                  {32{way0_hit}} & way0_load_word |
                  {32{current_state == REFILL}} & ret_data;

// miss buffer
always @(posedge clk) begin
    if(reset)
        refill_word_counter <= 2'b0;
    else if((current_state == REFILL) && (ret_valid == 1))
        refill_word_counter <= refill_word_counter + 1'b1;
end
//assign replace_way  = lfsr[0];
assign replace_way = (current_state == STATE_CACOP) ? cacop_target_way : lfsr[0];
assign replace_data = replace_way ? way1_data : way0_data;

// LSFR
always @(posedge clk) begin
    if(reset) begin
        lfsr <= 3'b111;
    end
    else if(ret_valid == 1 & ret_last == 1) begin
        lfsr <= {lfsr[0], lfsr[2]^lfsr[0], lfsr[1]};
    end
end

// write buffer
always @(posedge clk) begin
    if(reset) begin
       // write_way   <= 1'b0;
        write_bank  <= 2'b0;
        write_index <= 8'b0;
        write_strb  <= 4'b0;
        write_data  <= 32'b0;
    end
    else if((current_state == LOOKUP) && (op == WRITE) && cache_hit && !reg_uncached) begin
       // write_way   <= way1_hit;
        write_bank  <= offset[3:2];
        write_index <= index;
        write_strb  <= wstrb;
        write_data  <= wdata;
    end
end
always @(posedge clk) begin
    if(reset) begin
        write_way   <= 1'b0;
    end
    else if((current_state == LOOKUP) && (reg_op == WRITE) && cache_hit && !reg_uncached) begin
        write_way   <= way1_hit;
    end
end

// State Signals
assign lookup    = (current_state == IDLE) && valid && (~read_write_hazard) ||
                   (current_state == LOOKUP) && valid && cache_hit && (~read_write_hazard) && (~load_store_hazard ||  load_store_hazard && writebuf_cur_state == 2'b10) && (~reg_uncached); // <--- Add !reg_uncached
assign hitwrite  = (writebuf_next_state == WRITEBUF_WRITE ) || (writebuf_cur_state == WRITEBUF_WRITE);
assign replace   = (current_state == MISS) || (current_state == REPLACE);
assign refill    = (current_state == REFILL);

// <--- lookup_en 修改：Uncached 时不需要启用 RAM 片选（省电）
assign lookup_en = (current_state == IDLE) && valid && (~read_write_hazard) ||
                   (current_state == LOOKUP) && valid && (~read_write_hazard) && (~load_store_hazard ||  load_store_hazard && writebuf_cur_state == 2'b10) && (~reg_uncached); 

assign replace_block_dirty = (replace_way == 1'b0) && dirty_way0[reg_index] && way0_v ||
                             (replace_way == 1'b1) && dirty_way1[reg_index] && way1_v;

wire load_store_hazard = (current_state == LOOKUP) && (reg_op == WRITE) && valid && (op == READ)         
                      && {tag, index, offset[3:2]} == {reg_tag, reg_index, offset[3:2]};
wire read_write_hazard = (writebuf_cur_state == WRITEBUF_WRITE)  
                       && valid && (op == READ) && (offset[3:2] == write_bank);

assign byte_word = {{reg_wstrb[3] ? reg_wdata[31:24] : ret_data[31:24]},
                    {reg_wstrb[2] ? reg_wdata[23:16] : ret_data[23:16]},
                    {reg_wstrb[1] ? reg_wdata[15: 8] : ret_data[15: 8]},
                    {reg_wstrb[0] ? reg_wdata[ 7: 0] : ret_data[ 7: 0]}};
assign refill_word = ((refill_word_counter == reg_offset[3:2]) && (reg_op == WRITE))? byte_word : ret_data;

// Dirty Tables
always @(posedge clk) begin
    if(reset) begin
        dirty_way0 <= 256'b0;
    end
    else if(writebuf_cur_state == WRITEBUF_WRITE && way0_hit) begin
        dirty_way0[write_index] <= 1'b1; 
    end
    else if(refill) begin
        if(replace_way == 1'b0 && reg_op == 1'b1)
            dirty_way0[reg_index] <= 1'b1;
        else
            dirty_way0[reg_index] <= 1'b0; // Clean on refill (unless it's a write-miss refill)
    end
    else if (current_state == STATE_CACOP && cacop_op_ready && cacop_w0_en) begin
            dirty_way0[reg_index] <= 1'b0;
    end
end
always @(posedge clk) begin
    if(reset) begin
        dirty_way1 <= 256'b0;
    end
    else if(writebuf_cur_state == WRITEBUF_WRITE && way1_hit) begin
        dirty_way1[write_index] <= 1'b1;
    end
    else if(refill) begin
        if(replace_way == 1'b1 && reg_op == 1'b1)
            dirty_way1[reg_index] <= 1'b1;
        else
            dirty_way1[reg_index] <= 1'b0;
    end
    else if (current_state == STATE_CACOP && cacop_op_ready && cacop_w1_en) begin
            dirty_way1[reg_index] <= 1'b0;
    end
end

// RAM Enables
//assign tagv_w0_en = lookup_en || ((replace || refill) && (replace_way == 1'b0));
//assign tagv_w1_en = lookup_en || ((replace || refill) && (replace_way == 1'b1));
assign tagv_w0_en = lookup_en || ((replace || refill) && (replace_way == 1'b0)) || (uncached_hit_invalidate && way0_hit)|| (current_state == STATE_CACOP);
assign tagv_w1_en = lookup_en || ((replace || refill) && (replace_way == 1'b1)) || (uncached_hit_invalidate && way1_hit)|| (current_state == STATE_CACOP);
//assign tagv_w0_we = refill && (replace_way == 1'b0) && ret_valid && (refill_word_counter == reg_offset[3:2]);
//assign tagv_w1_we = refill && (replace_way == 1'b1) && ret_valid && (refill_word_counter == reg_offset[3:2]);
assign tagv_w0_we = (refill && (replace_way == 1'b0) && ret_valid && (refill_word_counter == reg_offset[3:2])) || (uncached_hit_invalidate && way0_hit) || cacop_w0_en;
assign tagv_w1_we = (refill && (replace_way == 1'b1) && ret_valid && (refill_word_counter == reg_offset[3:2])) || (uncached_hit_invalidate && way1_hit) || cacop_w1_en;
//assign tagv_wdata = {reg_tag, 1'b1};
// 如果是 Uncached 写命中，则写入 Valid=0，否则写入 Valid=1
// tagv_wdata = {reg_tag, ~uncached_hit_invalidate};
assign tagv_wdata = (current_state == STATE_CACOP) ? 21'b0 : {reg_tag, ~uncached_hit_invalidate};
//assign tagv_addr  = {8{lookup_en}} & index | {8{replace || refill}} & reg_index;
assign tagv_addr = (current_state == STATE_CACOP) ? reg_index :
                   ({8{lookup_en}} & index | {8{replace || refill}} & reg_index);
/*
assign data_w0_b0_en = lookup_en && (offset[3:2] == 2'b00) || hitwrite && (write_way == 1'b0) || (replace || refill) && (replace_way == 1'b0);
assign data_w0_b1_en = lookup_en && (offset[3:2] == 2'b01) || hitwrite && (write_way == 1'b0) || (replace || refill) && (replace_way == 1'b0);
assign data_w0_b2_en = lookup_en && (offset[3:2] == 2'b10) || hitwrite && (write_way == 1'b0) || (replace || refill) && (replace_way == 1'b0);
assign data_w0_b3_en = lookup_en && (offset[3:2] == 2'b11) || hitwrite && (write_way == 1'b0) || (replace || refill) && (replace_way == 1'b0);
assign data_w1_b0_en = lookup_en && (offset[3:2] == 2'b00) || hitwrite && (write_way == 1'b1) || (replace || refill) && (replace_way == 1'b1);
assign data_w1_b1_en = lookup_en && (offset[3:2] == 2'b01) || hitwrite && (write_way == 1'b1) || (replace || refill) && (replace_way == 1'b1);
assign data_w1_b2_en = lookup_en && (offset[3:2] == 2'b10) || hitwrite && (write_way == 1'b1) || (replace || refill) && (replace_way == 1'b1);
assign data_w1_b3_en = lookup_en && (offset[3:2] == 2'b11) || hitwrite && (write_way == 1'b1) || (replace || refill) && (replace_way == 1'b1);
*/

assign data_w0_b0_en = lookup_en &&~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE) && (offset[3:2] == 2'b00) || hitwrite && (way0_hit == 1'b1) || (replace || refill) && (replace_way == 1'b0)|| (current_state == STATE_CACOP);
assign data_w0_b1_en = lookup_en &&~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE) && (offset[3:2] == 2'b01) || hitwrite && (way0_hit == 1'b1) || (replace || refill) && (replace_way == 1'b0)|| (current_state == STATE_CACOP);
assign data_w0_b2_en = lookup_en &&~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE)&& (offset[3:2] == 2'b10) || hitwrite && (way0_hit == 1'b1) || (replace || refill) && (replace_way == 1'b0)|| (current_state == STATE_CACOP);
assign data_w0_b3_en = lookup_en &&~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE)&& (offset[3:2] == 2'b11) || hitwrite && (way0_hit == 1'b1) || (replace || refill) && (replace_way == 1'b0)|| (current_state == STATE_CACOP);
assign data_w1_b0_en = lookup_en &&~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE) && (offset[3:2] == 2'b00) || hitwrite && (way1_hit == 1'b1) || (replace || refill) && (replace_way == 1'b1)|| (current_state == STATE_CACOP);
assign data_w1_b1_en = lookup_en &&~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE) && (offset[3:2] == 2'b01) || hitwrite && (way1_hit == 1'b1) || (replace || refill) && (replace_way == 1'b1)|| (current_state == STATE_CACOP);
assign data_w1_b2_en = lookup_en &&~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE) && (offset[3:2] == 2'b10) || hitwrite && (way1_hit == 1'b1) || (replace || refill) && (replace_way == 1'b1)|| (current_state == STATE_CACOP);
assign data_w1_b3_en = lookup_en &&~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE) && (offset[3:2] == 2'b11) || hitwrite && (way1_hit == 1'b1) || (replace || refill) && (replace_way == 1'b1)|| (current_state == STATE_CACOP);

assign data_w0_b0_we = {4{hitwrite && (way0_hit == 1'b1) && (write_bank == 2'b00)}} & write_strb | {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b00) && ret_valid}};
assign data_w0_b1_we = {4{hitwrite && (way0_hit == 1'b1) && (write_bank == 2'b01)}} & write_strb | {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b01) && ret_valid}};
assign data_w0_b2_we = {4{hitwrite && (way0_hit == 1'b1) && (write_bank == 2'b10)}} & write_strb | {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b10) && ret_valid}};
assign data_w0_b3_we = {4{hitwrite && (way0_hit == 1'b1) && (write_bank == 2'b11)}} & write_strb | {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b11) && ret_valid}};
assign data_w1_b0_we = {4{hitwrite && (way1_hit == 1'b1) && (write_bank == 2'b00)}} & write_strb | {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b00) && ret_valid}};
assign data_w1_b1_we = {4{hitwrite && (way1_hit == 1'b1) && (write_bank == 2'b01)}} & write_strb | {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b01) && ret_valid}};
assign data_w1_b2_we = {4{hitwrite && (way1_hit == 1'b1) && (write_bank == 2'b10)}} & write_strb | {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b10) && ret_valid}};
assign data_w1_b3_we = {4{hitwrite && (way1_hit == 1'b1) && (write_bank == 2'b11)}} & write_strb | {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b11) && ret_valid}};
/*

assign data_w0_b0_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b00)}} & write_strb | {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b00) && ret_valid}};
assign data_w0_b1_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b01)}} & write_strb | {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b01) && ret_valid}};
assign data_w0_b2_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b10)}} & write_strb | {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b10) && ret_valid}};
assign data_w0_b3_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b11)}} & write_strb | {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b11) && ret_valid}};
assign data_w1_b0_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b00)}} & write_strb | {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b00) && ret_valid}};
assign data_w1_b1_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b01)}} & write_strb | {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b01) && ret_valid}};
assign data_w1_b2_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b10)}} & write_strb | {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b10) && ret_valid}};
assign data_w1_b3_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b11)}} & write_strb | {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b11) && ret_valid}};
*/
assign data_wdata    = refill ? refill_word : (hitwrite ? write_data : 32'b0);
// [修改] CACOP 状态下也需要使用 reg_index 来寻址 Data RAM
assign data_addr     = (replace || refill || current_state == STATE_CACOP) ? reg_index : 
                       (hitwrite  ? write_index : (lookup_en ? index : 8'b0));

// RAM Instantiations (Keep same as original)
TAGV_RAM tagv_way0(.addra(tagv_addr), .clka(clk), .dina(tagv_wdata), .douta(tagv_w0_rdata), .ena(tagv_w0_en), .wea(tagv_w0_we));
TAGV_RAM tagv_way1(.addra(tagv_addr), .clka(clk), .dina(tagv_wdata), .douta(tagv_w1_rdata), .ena(tagv_w1_en), .wea(tagv_w1_we));
DATA_RAM data_way0_bank0(.addra(data_addr), .clka(clk), .dina(data_wdata), .douta(data_w0_b0_rdata), .ena(data_w0_b0_en), .wea(data_w0_b0_we));
DATA_RAM data_way0_bank1(.addra(data_addr), .clka(clk), .dina(data_wdata), .douta(data_w0_b1_rdata), .ena(data_w0_b1_en), .wea(data_w0_b1_we));
DATA_RAM data_way0_bank2(.addra(data_addr), .clka(clk), .dina(data_wdata), .douta(data_w0_b2_rdata), .ena(data_w0_b2_en), .wea(data_w0_b2_we));
DATA_RAM data_way0_bank3(.addra(data_addr), .clka(clk), .dina(data_wdata), .douta(data_w0_b3_rdata), .ena(data_w0_b3_en), .wea(data_w0_b3_we));
DATA_RAM data_way1_bank0(.addra(data_addr), .clka(clk), .dina(data_wdata), .douta(data_w1_b0_rdata), .ena(data_w1_b0_en), .wea(data_w1_b0_we));
DATA_RAM data_way1_bank1(.addra(data_addr), .clka(clk), .dina(data_wdata), .douta(data_w1_b1_rdata), .ena(data_w1_b1_en), .wea(data_w1_b1_we));
DATA_RAM data_way1_bank2(.addra(data_addr), .clka(clk), .dina(data_wdata), .douta(data_w1_b2_rdata), .ena(data_w1_b2_en), .wea(data_w1_b2_we));
DATA_RAM data_way1_bank3(.addra(data_addr), .clka(clk), .dina(data_wdata), .douta(data_w1_b3_rdata), .ena(data_w1_b3_en), .wea(data_w1_b3_we));

// cache and CPU output signal
// <--- 修改：addr_ok 在 Uncached 且能进 LOOKUP 时也要为高
assign addr_ok = //(current_state == IDLE) ||
                 (current_state == LOOKUP) && cache_hit && ~(op==0 && writebuf_cur_state ==  WRITEBUF_WRITE ) && valid && (~read_write_hazard) && (~load_store_hazard ||  load_store_hazard && writebuf_cur_state == 2'b10) && (~uncached)||
                 (current_state == LOOKUP) && reg_uncached && (reg_op == READ &&rd_rdy || reg_op == WRITE &&wr_rdy); 


// <--- 修改：data_ok 在 UNCACHED 状态完成时也要为高
assign data_ok = (current_state == LOOKUP) && (cache_hit || (reg_op == WRITE)) && !reg_uncached ||
                 (current_state == REFILL) && ret_valid && (refill_word_counter == reg_offset[3:2]) && (reg_op == READ) ||
                 (current_state == UNCACHED) && ((reg_op == READ && ret_valid) || (reg_op == WRITE && data_finish));

assign rdata   = load_res;

// cache and AXI output signal
// <--- 修改：rd_req 在 UNCACHED 读时也要为高
assign rd_req   = (current_state == REPLACE) || (current_state == LOOKUP && reg_uncached && reg_op == READ);

// rd_type, wr_type, addr 选择逻辑修正
assign rd_type  = (current_state == LOOKUP && reg_uncached) ? WORD : BLOCK;

// 地址选择：如果当前正在处理 Uncached (LOOKUP or UNCACHED)，使用 reg_ 寄存器拼接
assign rd_addr  = (current_state == LOOKUP && reg_uncached) ? {reg_tag, reg_index, reg_offset} : {reg_tag, reg_index, 4'b0000};

// 修正：wr_req 只在 LOOKUP 状态且确认是 Uncached 写时拉高
// 或者是写回阶段（MISS状态）
/*
reg    dcache_data_prepared;
always @(posedge clk) begin
    if(reset) begin
        dcache_data_prepared <= 1'b0;
    end else 
    if(data_prepared) begin
         dcache_data_prepared <= 1'b1;
    end else 
    if(data_finish) begin
        dcache_data_prepared <= 1'b0;
    end
end 
*/
// cacop_wb_done 是一个新寄存器，用于标记写回是否已完成
reg cacop_wb_done; 
assign wr_req   = (current_state == MISS) && replace_block_dirty  ||
                  (current_state == LOOKUP && reg_uncached && reg_op == WRITE  )||
                  (current_state == STATE_CACOP && cacop_need_wb && !cacop_wb_done && (cacop_cnt != 2'b00)); // <--- 新增

assign wr_type  = (current_state == LOOKUP && reg_uncached) ? 
                  (reg_wstrb == 4'b1111 ? WORD : 
                   (reg_wstrb == 4'b0011 || reg_wstrb == 4'b1100) ? HALFWORD : BYTE) : BLOCK;

assign wr_addr  = (current_state == LOOKUP && reg_uncached) ? {reg_tag, reg_index, reg_offset} : 
                  ({32{replace_way == 1'b0}} & {way0_tag, reg_index, 4'b0000} |
                   {32{replace_way == 1'b1}} & {way1_tag, reg_index, 4'b0000});

assign wr_wstrb = (current_state == LOOKUP && reg_uncached) ? reg_wstrb : 4'b1111;

assign wr_data  = (current_state == LOOKUP && reg_uncached) ? {96'b0, reg_wdata} : 
                  ({128{replace_way == 1'b0}} & way0_data |
                   {128{replace_way == 1'b1}} & way1_data);
                   

endmodule