module cache(
    input        clk        ,
    input        resetn     ,
    // Cache and CPU
    input         valid     , // request is valid
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
    output         rd_req   , // the read request is valid
    output [  2:0] rd_type  , // the read request type(byte halfword word line)
    output [ 31:0] rd_addr  , // the start address of read request
    input          rd_rdy   , // the handshake signal that read request can be received
    input          ret_valid, // the return data is valid
    input          ret_last , // the return data is one read request's last
    input  [ 31:0] ret_data , // read return data
    output         wr_req   , // write request valid
    output [  2:0] wr_type  , // write request type(byte halfword word line)
    output [ 31:0] wr_addr  , // the start address of write request
    output [  3:0] wr_wstrb , // the mask of write byte
    output [127:0] wr_data  , // the write data
    input          wr_rdy     // the handshake signal that write request can be received
);

// CPU to cache request type(op)
parameter READ  = 1'b0;
parameter WRITE = 1'b1;
// cache to sram read type(rd_type)
parameter READ_BYTE     = 3'b000;
parameter READ_HALFWORD = 3'b001;
parameter READ_WORD     = 3'b010;
parameter READ_BLOCK    = 3'b100;
// cache to sram write type(wr_type)
parameter WRITE_BYTE     = 3'b000;
parameter WRITE_HALFWORD = 3'b001;
parameter WRITE_WORD     = 3'b010;
parameter WRITE_BLOCK    = 3'b100;

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
parameter IDLE    = 5'b00001;
parameter LOOKUP  = 5'b00010;
parameter MISS    = 5'b00100;
parameter REPLACE = 5'b01000;
parameter REFILL  = 5'b10000;
reg [4:0] current_state;
reg [4:0] next_state;
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
// tag compare（未考虑 Uncache�?
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
always @(posedge clk)begin
    reset <= ~resetn;
end     

/**
    main FSM
*/
always @(posedge clk)begin
    if(reset)
        current_state <= IDLE;
    else 
        current_state <= next_state;
end
always @(*)begin
    case(current_state)
    IDLE:begin
        if(valid && (~read_write_hazard))
            next_state = LOOKUP;
        else
            next_state = IDLE;
    end
    LOOKUP:begin
        if(~cache_hit)
            next_state = MISS;
        else if((~valid) || read_write_hazard || load_store_hazard)
            next_state = IDLE;
        else
            next_state = LOOKUP;
    end
    
    MISS:begin
        if((wr_rdy == 1) || (~replace_block_dirty))
            next_state = REPLACE;
        else
            next_state = MISS;
    end
    REPLACE:begin
        if(rd_rdy == 1)
            next_state = REFILL;
        else
            next_state = REPLACE;
    end
    REFILL:begin
        if(ret_valid == 1 && ret_last == 1)
            next_state = IDLE;
        else
            next_state = REFILL;
    end
    endcase
end

/**
    write buffer FSM
*/
always @(posedge clk)begin
    if(reset)
        writebuf_cur_state <= WRITEBUF_IDLE;
    else
        writebuf_cur_state <= writebuf_next_state;
end

always @(*) begin
    case(writebuf_cur_state)
    WRITEBUF_IDLE:begin
        if((current_state == LOOKUP) && (reg_op == WRITE) && cache_hit)
            writebuf_next_state = WRITEBUF_WRITE;
        else
            writebuf_next_state = WRITEBUF_IDLE;
    end
    WRITEBUF_WRITE:begin
        if((current_state == LOOKUP) && (reg_op == WRITE) && cache_hit)
            writebuf_next_state = WRITEBUF_WRITE;
        else
            writebuf_next_state = WRITEBUF_IDLE;
    end
    endcase
end

/**
    data path other than Cache table
*/
// request buffer(the information for Tag compare and Miss)
always @(posedge clk)begin
    if(reset)begin
        reg_op     <= 1'b0;
        reg_index  <= 8'b0;
        reg_tag    <= 20'b0;
        reg_offset <= 4'b0;
        reg_wstrb  <= 4'b0;
        reg_wdata  <= 32'b0;
    end
    else if(lookup == 1)begin
        reg_op     <= op;
        reg_index  <= index;
        reg_tag    <= tag;
        reg_offset <= offset;
        reg_wstrb  <= wstrb;
        reg_wdata  <= wdata;
    end
end
// Tag Compare
assign {way0_tag, way0_v} = tagv_w0_rdata;
assign {way1_tag, way1_v} = tagv_w1_rdata;
assign way0_hit  = way0_v && (way0_tag == reg_tag);
assign way1_hit  = way1_v && (way1_tag == reg_tag);
assign cache_hit = way0_hit || way1_hit;
// Data Select
assign way0_data = {data_w0_b3_rdata, data_w0_b2_rdata, data_w0_b1_rdata, data_w0_b0_rdata};
assign way1_data = {data_w1_b3_rdata, data_w1_b2_rdata, data_w1_b1_rdata, data_w1_b0_rdata};
assign way0_load_word = way0_data[reg_offset[3:2]*32 +: 32];
assign way1_load_word = way1_data[reg_offset[3:2]*32 +: 32];
assign load_res = {32{way0_hit}} & way0_load_word |
                  {32{way1_hit}} & way1_load_word |
                  {32{current_state == REFILL}} & ret_data;
// miss buffer(record the replace way and has returned several 32-bit data from the AXI bus)
always @(posedge clk)begin
    if(reset)
        refill_word_counter <= 2'b0;
    else if((current_state == REFILL) && (ret_valid == 1))
        refill_word_counter <= refill_word_counter + 1'b1;
end
assign replace_way  = lfsr[0];
assign replace_data = replace_way ? way1_data : way0_data;
// LSFR
always @(posedge clk)begin
    if(reset)begin
        lfsr <= 3'b111;
    end
    else if(ret_valid == 1 & ret_last == 1)begin
        lfsr <= {lfsr[0], lfsr[2]^lfsr[0], lfsr[1]};
    end
end
// write buffer(start at Hit Write)
always @(posedge clk)begin
    if(reset)begin
        write_way   <= 1'b0;
        write_bank  <= 2'b0;
        write_index <= 8'b0;
        write_strb  <= 4'b0;
        write_data  <= 32'b0;
    end
    else if((current_state == LOOKUP) && (reg_op == WRITE) && cache_hit)begin
        write_way   <= way1_hit;
        write_bank  <= reg_offset[3:2];
        write_index <= reg_index;
        write_strb  <= reg_wstrb;
        write_data  <= reg_wdata;
    end
end

/**
    the state now

    @para lookup_en   对于 ram 片�?�信号的生成，需要防止cache输出产生�? cache_hit 信号影响 ram 片�?�信号的生成
*/
assign lookup    = (current_state == IDLE) && valid && (~read_write_hazard) ||
                   (current_state == LOOKUP) && valid && cache_hit && (~read_write_hazard) && (~load_store_hazard);
assign hitwrite  = (writebuf_cur_state == WRITEBUF_WRITE);
assign replace   = (current_state == MISS) || (current_state == REPLACE);
assign refill    = (current_state == REFILL);
assign lookup_en = (current_state == IDLE) && valid && (~read_write_hazard) ||
                   (current_state == LOOKUP) && valid && (~read_write_hazard) && (~load_store_hazard); 

/**
    the write situation

    @para replace_block_dirty  the replace way is dirty and valid
    @para load_store_hazard    the first situation of Hit Write
    @para read_write_hazard    the second situation of Hit Write
*/
assign replace_block_dirty = (replace_way == 1'b0) && dirty_way0[reg_index] && way0_v 
                          || (replace_way == 1'b1) && dirty_way1[reg_index] && way1_v;
wire load_store_hazard = (current_state == LOOKUP) && (reg_op == WRITE) && valid && (op == READ)         
                      && {tag, index, offset[3:2]} == {reg_tag, reg_index, offset[3:2]}; 
wire read_write_hazard = (writebuf_cur_state == WRITEBUF_WRITE)  
                       && valid && (op == READ) && (offset[3:2] == write_bank);     

/**
    refill data

    @para byte_word     the refill word after wstrb to choose
    @para refill_word   the refill word
*/
assign byte_word = {{reg_wstrb[3]? reg_wdata[31:24] : ret_data[31:24]},
                    {reg_wstrb[2]? reg_wdata[23:16] : ret_data[23:16]},
                    {reg_wstrb[1]? reg_wdata[15: 8] : ret_data[15: 8]},
                    {reg_wstrb[0]? reg_wdata[ 7: 0] : ret_data[ 7: 0]}};
assign refill_word = ((refill_word_counter == reg_offset[3:2]) && (reg_op == WRITE))? byte_word : ret_data;

/**
    the assign of dirty table
    Synchronous Write Asynchronous Read
*/
always @(posedge clk)begin
    if(reset) begin
        dirty_way0 <= 256'b0;
        dirty_way1 <= 256'b0;
    end
    else if(hitwrite) begin
        if(way0_hit)
            dirty_way0[write_index] <= 1'b1;
        else if(way1_hit)
            dirty_way1[write_index] <= 1'b1;
    end
    else if(refill) begin
        if(replace_way == 1'b0)
            dirty_way0[reg_index] <= 1'b0;
        else if(replace_way == 1'b1)
            dirty_way1[reg_index] <= 1'b0;
    end
end

// TAGV_RAM
assign tagv_w0_en = lookup_en || ((replace || refill) && (replace_way == 1'b0));
assign tagv_w1_en = lookup_en || ((replace || refill) && (replace_way == 1'b1));
assign tagv_w0_we = refill && (replace_way == 1'b0) && ret_valid && (refill_word_counter == reg_offset[3:2]);
assign tagv_w1_we = refill && (replace_way == 1'b1) && ret_valid && (refill_word_counter == reg_offset[3:2]);
assign tagv_wdata = {reg_tag, 1'b1}; 
assign tagv_addr  = {8{lookup_en}} & index | {8{replace || refill}} & reg_index;
/**
    DATA_RAM

    the three situation for enable signal need to be 1
    1. lookup and the offset corresponds to bank
    2. hitwrite and the way in write buffer corresponds to bank
    3. replace/refill and the way in miss buffer corresponds to bank

    the two situation for write enable signal need to be 1
    1. hitwrite and the way in write buffer corresponds to bank, in this case the write enable signal comes from write buffer
    2. refill and the way in write buffer corresponds to bank, in this case the write enable signal is 1111(replace all)
*/
assign data_w0_b0_en = lookup_en && (offset[3:2] == 2'b00) || hitwrite && (write_way == 1'b0)||
                       (replace || refill) && (replace_way == 1'b0);
assign data_w0_b1_en = lookup_en && (offset[3:2] == 2'b01) || hitwrite && (write_way == 1'b0)||
                       (replace || refill) && (replace_way == 1'b0);
assign data_w0_b2_en = lookup_en && (offset[3:2] == 2'b10) || hitwrite && (write_way == 1'b0)||
                       (replace || refill) && (replace_way == 1'b0);
assign data_w0_b3_en = lookup_en && (offset[3:2] == 2'b11) || hitwrite && (write_way == 1'b0)||
                       (replace || refill) && (replace_way == 1'b0);
assign data_w1_b0_en = lookup_en && (offset[3:2] == 2'b00) || hitwrite && (write_way == 1'b1)||
                       (replace || refill) && (replace_way == 1'b1);
assign data_w1_b1_en = lookup_en && (offset[3:2] == 2'b01) || hitwrite && (write_way == 1'b1)||
                       (replace || refill) && (replace_way == 1'b1);
assign data_w1_b2_en = lookup_en && (offset[3:2] == 2'b10) || hitwrite && (write_way == 1'b1)||
                       (replace || refill) && (replace_way == 1'b1);
assign data_w1_b3_en = lookup_en && (offset[3:2] == 2'b11) || hitwrite && (write_way == 1'b1)||
                       (replace || refill) && (replace_way == 1'b1);
assign data_w0_b0_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b00)}} & write_strb |
                       {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b00) && ret_valid}};
assign data_w0_b1_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b01)}} & write_strb |
                       {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b01) && ret_valid}};
assign data_w0_b2_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b10)}} & write_strb |
                       {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b10) && ret_valid}};
assign data_w0_b3_we = {4{hitwrite && (write_way == 1'b0) && (write_bank == 2'b11)}} & write_strb |
                       {4{refill && (replace_way == 1'b0) && (refill_word_counter == 2'b11) && ret_valid}};
assign data_w1_b0_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b00)}} & write_strb |
                       {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b00) && ret_valid}};
assign data_w1_b1_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b01)}} & write_strb |
                       {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b01) && ret_valid}};
assign data_w1_b2_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b10)}} & write_strb |
                       {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b10) && ret_valid}};
assign data_w1_b3_we = {4{hitwrite && (write_way == 1'b1) && (write_bank == 2'b11)}} & write_strb |
                       {4{refill && (replace_way == 1'b1) && (refill_word_counter == 2'b11) && ret_valid}};
assign data_wdata    = refill ? refill_word : (hitwrite ? write_data : 32'b0);
assign data_addr     = (replace || refill)? reg_index :
                       (hitwrite ? write_index : (lookup_en ? index : 8'b0));

TAGV_RAM tagv_way0(
    .addra(tagv_addr),
    .clka(clk),
    .dina(tagv_wdata),
    .douta(tagv_w0_rdata),
    .ena(tagv_w0_en),
    .wea(tagv_w0_we)
);
TAGV_RAM tagv_way1(
    .addra(tagv_addr),
    .clka(clk),
    .dina(tagv_wdata),
    .douta(tagv_w1_rdata),
    .ena(tagv_w1_en),
    .wea(tagv_w1_we)
);

DATA_RAM data_way0_bank0(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w0_b0_rdata),
    .ena(data_w0_b0_en),
    .wea(data_w0_b0_we)
);
DATA_RAM data_way0_bank1(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w0_b1_rdata),
    .ena(data_w0_b1_en),
    .wea(data_w0_b1_we)
);
DATA_RAM data_way0_bank2(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w0_b2_rdata),
    .ena(data_w0_b2_en),
    .wea(data_w0_b2_we)
);
DATA_RAM data_way0_bank3(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w0_b3_rdata),
    .ena(data_w0_b3_en),
    .wea(data_w0_b3_we)
);
DATA_RAM data_way1_bank0(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w1_b0_rdata),
    .ena(data_w1_b0_en),
    .wea(data_w1_b0_we)
);
DATA_RAM data_way1_bank1(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w1_b1_rdata),
    .ena(data_w1_b1_en),
    .wea(data_w1_b1_we)
);
DATA_RAM data_way1_bank2(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w1_b2_rdata),
    .ena(data_w1_b2_en),
    .wea(data_w1_b2_we)
);
DATA_RAM data_way1_bank3(
    .addra(data_addr),
    .clka(clk),
    .dina(data_wdata),
    .douta(data_w1_b3_rdata),
    .ena(data_w1_b3_en),
    .wea(data_w1_b3_we)
);

// cache and CPU output signal
assign addr_ok = (current_state == IDLE) || (current_state == LOOKUP) && cache_hit &&
                 valid && (~read_write_hazard) && (~load_store_hazard);
assign data_ok = (current_state == LOOKUP) && (cache_hit || (reg_op == WRITE)) ||
                 (current_state == REFILL) && ret_valid && (refill_word_counter == reg_offset[3:2]) && (reg_op == READ);
assign rdata   = load_res;

// cache and AXI output signal
assign rd_req   = (current_state == REPLACE);
assign rd_type  = READ_BLOCK; //
assign rd_addr  = {reg_tag, reg_index, 4'b0000};
assign wr_req   = (current_state == MISS) && replace_block_dirty;
assign wr_type  = WRITE_BLOCK; //
assign wr_addr  = {32{replace_way == 1'b0}} & {way0_tag, reg_index, 4'b0000} |
                  {32{replace_way == 1'b1}} & {way1_tag, reg_index, 4'b0000};
assign wr_wstrb = 4'b1111; // 
assign wr_data  = {128{replace_way == 1'b0}} & way0_data |
                  {128{replace_way == 1'b1}} & way1_data;

endmodule