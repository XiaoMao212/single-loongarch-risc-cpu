`include "mycpu.h"

module if_stage(
    input                          clk            ,
    input                          reset          ,
    // ds allwoin
    input                          ds_allowin     ,
    // brbus(from ds)
    input  [`BR_BUS_WD       -1:0] br_bus         ,
    // to ds
    output                         fs_to_ds_valid ,
    output [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus   ,
    // inst sram interface
    output                         inst_sram_en   ,
    output                         inst_sram_wr   ,
    output [ 3:0]                  inst_sram_we   ,
    output [ 1:0]                  inst_sram_size ,
    output [31:0]                  inst_sram_addr ,
    output [31:0]                  inst_sram_wdata,
    input  [31:0]                  inst_sram_rdata,
    input                          inst_sram_addr_ok,
    input                          inst_sram_data_ok,
    // exception interface
    input                          ws_ex         ,
    input                          ertn_flush    ,
    input  [31:0]                  ex_entry      ,
    input  [31:0]                  era_entry     ,
    input                          fs_reflush   ,
        // mmu
    output [31:0]                  va            ,
    input  [31:0]                  pa            ,
    input  [ 5:0]                  fs_exc_ecode  ,
    input                          dmw_hit       ,
    input  [ 1:0]                  plv           ,
    input  [ 9:0]                  mmu_asid      ,
    // to tlb
    output [19:0]                  s0_va_highbits,
    output [ 9:0]                  s0_asid     ,
    input [2:0] exe_need_mem_forward     
   // input [2:0] exe_need_mem_forward
);

// pipeline control signal
reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;
wire        pre_if_ready_go;
reg         pre_fs_valid;//没用

// branch control signal
wire        br_stall;
wire        br_taken;
wire [31:0] br_target;

// pc and inst signal
wire [31:0] seq_pc;
wire [31:0] nextpc;
reg  [31:0] fs_pc;
wire [31:0] fs_inst;

// exception signal
wire [32:0] fs_adef_data;
wire        fs_adef;
wire [31:0] fs_wrong_addr;

// IF to ID trigger
reg [31: 0] fs_inst_trigger;
reg         fs_inst_valid;
//reg         fs_inst_cancel;

// the trigger for random
reg         fs_ertn_valid;
reg         fs_ex_valid;
reg [31: 0] fs_ertn_entry;
reg [31: 0] fs_ex_entry;
reg         fs_br_taken;
reg [31: 0] fs_br_target;


/**
    from ds, the branch information

    @para br_stall   load-to-branch situation, determine if the transfer calculation is complete(complete is 0)
    @para br_taken   ID-stage is branch inst and satify the jump conditions
    @para br_target  destination address(pc) of the branch
*/
assign {br_stall, br_taken, br_target} = br_bus;

/**
    pre-IF stage

    @para pre_if_ready_go   when the addr_ok and req are all 1, pre-IF will ready go
                            the transfer calculation is not complete, can not pass nextpc to IF-stage
                            this situation will be in req(br_stall is 1 and pre_if_ready_go is 0)
    @para to_fs_valid       if pre-IF stage is ready, then can pass to IF-stage
    @para seq_pc            next address in order(pc + 4)
    @para nextpc            the real address of next inst, include exception jump / branch jump / seq_pc
    @para fs_adef           determine if adef exception has occurred based on nextpc
                            (the address is not four-byte boundary-aligned)
    @para fs_wrong_addr     the adef's wrong address
    @para fs_adef_data      the adef exception data, include the adef signal and wrong address
    @para pre_fs_valid      the pre-IF stage is valid to pass
*/

wire es_need_mem;
wire data_sram_addr;
wire data_en;


assign {es_need_mem, data_sram_addr, data_en} = exe_need_mem_forward;

assign pre_if_ready_go = inst_sram_addr_ok && inst_sram_en;
//assign to_fs_valid     = ~reset & pre_if_ready_go;
assign to_fs_valid     = ~reset & pre_if_ready_go & ~(pre_fs_reflush | fs_reflush)   && (~es_need_mem || es_need_mem && data_sram_addr && data_en);//收到异常信号时不管什么情况都设置to_fs_valid无效，直到这个错误的pc已经在IF阶段接收到data_ok
assign seq_pc          = fs_pc + 3'h4;
assign nextpc       = fs_ex_valid   ? fs_ex_entry:
                      ws_ex         ? ex_entry:
                      fs_ertn_valid ? fs_ertn_entry:
                      ertn_flush    ? era_entry:
                      fs_br_taken   ? fs_br_target:
                      (br_taken & ~br_stall) ? br_target : seq_pc;
//assign fs_adef         = nextpc[0] | nextpc[1];
//assign fs_wrong_addr   = nextpc;
assign fs_adef         = fs_pc[0] | fs_pc[1];
assign fs_wrong_addr   = fs_pc;
assign fs_adef_data    = {fs_adef, fs_wrong_addr};
always @(posedge clk) begin
    if (reset) begin
        pre_fs_valid <= 1'b0;//没用，en直接承担起当前pre_if是否有效
    end
    else if (fs_allowin) begin
        pre_fs_valid <= 1'b1;   
    end
end

/**
    IF stage

    @para fs_ready_go       IF-stage is ready and data is ok or the first inst after the cancel
    @para fs_allowin        IF-stage doesn't have valid data or IF-stage will pass the valid data to ID-stage
    @para fs_to_ds_valid    IF-stage have valid data that has been processed
                            WB-stage doesn't have exception and doesn't need to branch/reflush the pipeline
    @para fs_valid          if IF-stage allow in and pre-IF stage can pass
    @para fs_pc             if pre-IF stage can pass and IF-stage can receive
*/
assign fs_ready_go    = (fs_valid && inst_sram_data_ok) || (fs_inst_valid && ~fs_inst_cancel);//fs获取rdata或者临时存指令的缓存存在有效指令
   
//assign fs_to_ds_valid =  fs_valid && fs_ready_go && (~fs_reflush) && (~fs_inst_cancel) && ~(br_taken & ~br_stall);   
//assign fs_allowin     = !fs_valid  || fs_ready_go &&   ds_allowin; 
//assign fs_allowin     = !fs_valid && !pre_fs_reflush || fs_ready_go &&   ds_allowin;
//assign fs_to_ds_valid =  fs_valid && fs_ready_go && (~fs_inst_cancel);//错误的pc和错误的指令码在下一阶段无效
assign fs_to_ds_valid =  fs_valid && fs_ready_go && (~fs_reflush) && (~fs_inst_cancel) && ~(br_taken & ~br_stall); 
assign fs_allowin     = !fs_valid && !pre_fs_reflush || fs_ready_go &&   ds_allowin || fs_inst_cancel_ds;
always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;   
    end
end
always @(posedge clk) begin
    if (reset) begin
        fs_pc <= 32'h1bfffffc;     //trick: to make nextpc be 0x1c000000 during reset 
    end
    else if (to_fs_valid && fs_allowin) begin
        fs_pc <= nextpc;
    end
end

/**
    the trigger for random latency

    cause sram has the random latency, need to use tirgger to save the branch/exception information
*/
always @(posedge clk) begin
   // if(reset || (pre_if_ready_go && fs_allowin)) begin
   if(reset || (to_fs_valid && fs_allowin)) begin
        fs_ertn_valid <= 1'b0;
        fs_ex_valid   <= 1'b0;
        fs_ertn_entry <= 32'b0;
        fs_ex_entry   <= 32'b0;
    end
    else if(ertn_flush) begin//存在随机延迟，需要暂存例外和跳转对应的地址，否则下个周期，对应的信号会随着WB,ID改变从而找不到了
        fs_ertn_valid <= ertn_flush;
        fs_ertn_entry <= era_entry;
    end
    else if(ws_ex) begin
        fs_ex_valid <= ws_ex;
        fs_ex_entry <= ex_entry;
    end
end
always @(posedge clk) begin
   // if(reset || (pre_if_ready_go && fs_allowin)) begin
   if(reset || (to_fs_valid && fs_allowin)) begin
        fs_br_taken  <= 1'b0;
        fs_br_target <= 32'b0;
    end
    else if(br_taken & ~br_stall) begin
        fs_br_taken  <= br_taken;
        fs_br_target <= br_target;
    end
end

/**
    the trigger between IF stage and ID stage

    @para fs_inst_cancel    the signal in order to reflush the pipeline, cancel will be 1
                            if WB-stage have exception or need to jump, we should to discard the current inst
    @para fs_inst_trigger   the first inst after the exception
                            when the data is ok but ID-stage doesn't allow in and WB-stage doesn't have exception
    @para fs_inst_valid     the trigger's valid or not signal
                            when ID-stage allow in, send data to ID and clear the trigger
*/


always @(posedge clk) begin
    if(reset)begin
        fs_inst_trigger <= 32'b0;
        fs_inst_valid   <= 1'b0;
    end
    //else if(inst_sram_data_ok  & ~ds_allowin & ~fs_inst_cancel)//IF_ready_go=1, ID_allowin=0时保存从IF取回的指令
    else if(inst_sram_data_ok & ~fs_inst_valid & ~ds_allowin & ~fs_inst_cancel)
    begin
        fs_inst_trigger <= inst_sram_rdata;
        fs_inst_valid   <= 1'b1;
    end
    else if(fs_reflush || ds_allowin)//我觉得这个条件应该放在第二个而不是第三个，刷新的优先级比存储指令的优先级大，这样没有出错是因为我们就算存储了指令，fs_reflush也会控制to_ds_valid无效
    begin
      fs_inst_trigger <= 32'b0;
      fs_inst_valid   <= 1'b0;
    end
end

/**
    inst sram interface

    @para inst_sram_en       if pre-IF stage can pass and IF-stage can receive 
                             and doesn't happen write-to-branch, read inst from sram
    @para inst_sram_addr     the inst's address
    @para inst_sram_we       the inst sram's signal of write enable
    @para inst_sram_wdata    the isnt sram's signal of write data
    @para inst_sram_size     the reqest's bytes
*/
//Load-to-Branch的情况，ds_allowin一定为0，但由于存在随机延迟，fs此时可能不存在有效指令，那么此时fs_allowin可能为1，我们需要加上br_stall控制信号，防止用错误的nextPC进行取指
//assign inst_sram_en    = fs_allowin & ~br_stall;
assign inst_sram_we    = 4'h0;
assign inst_sram_addr  = pa;
assign inst_sram_wdata = 32'b0;
assign inst_sram_wr    = 1'b0;
assign inst_sram_size  = 2'b10;

/**
    to ds, the inst and pc information

    @para fs_inst       the inst's code to be executed now
    @para fs_to_ds_bus  the bus between pipeline
*/
assign fs_inst      = fs_inst_valid ? fs_inst_trigger : inst_sram_rdata;


//assign fs_inst      =  inst_sram_rdata;
assign fs_to_ds_bus = {fs_exc_ecode,fs_adef_data, fs_inst, fs_pc};

reg pre_fs_reflush;

always @(posedge clk) begin
    if(reset)
        pre_fs_reflush <= 1'b0;
    else if(inst_sram_en && (fs_reflush))
        pre_fs_reflush <= 1'b1;
    else if(inst_sram_data_ok)//直到错误pc已经接收到data_ok
        pre_fs_reflush <= 1'b0;
end


reg         fs_reflush_reg;
always @(posedge clk) begin
    if(reset || (to_fs_valid && fs_allowin)) begin//直到错误pc已经传递到ID
        fs_reflush_reg <= 1'b0;
    end
    else if(fs_reflush) begin
        fs_reflush_reg <= 1'b1;
    end
end
//wire fs_inst_cancel; 
//assign fs_inst_cancel = fs_reflush | fs_reflush_reg|br_taken & ~br_stall;
//assign fs_inst_cancel = fs_reflush | pre_fs_reflush;
reg fs_inst_cancel; 
reg fs_inst_cancel_ds;
always @(posedge clk) begin
    if(reset)
        fs_inst_cancel <= 1'b0;
    else if((fs_reflush | br_taken & ~br_stall) && ~fs_allowin && ~fs_ready_go )
        fs_inst_cancel <= 1'b1;
    else if(inst_sram_data_ok) 
        fs_inst_cancel <= 1'b0;
end
always @(posedge clk) begin
    if(reset)
        fs_inst_cancel_ds <= 1'b0;
    else if((fs_reflush | br_taken & ~br_stall) && ~fs_allowin &&  fs_ready_go &&  ~ds_allowin)
        fs_inst_cancel_ds <= 1'b1;
    else if(fs_allowin) 
        fs_inst_cancel_ds <= 1'b0;
end

reg inst_sram_req_reg;
reg inst_sram_addr_ok_reg;//没用
always @(posedge clk) begin
    if(reset) begin
        inst_sram_req_reg <= 1'b1;
    end
    else if(inst_sram_req_reg && inst_sram_addr_ok) begin
        inst_sram_req_reg <= 1'b0;//握手成功，撤销请求，防止同一个pc发出多个请求
    end
    else if(fs_allowin & ~br_stall) begin
        inst_sram_req_reg <= 1'b1;//允许发送请求,并且跳转指令顺序上的pc的en无效，因为直到跳转指令进入ID，req在下一个周期才能有效，这时正确的nextpc已经完成更新，所以在IF阶段我们不必担心因为跳转而产生错误的pc流入ID的情况
    end
end

always @(posedge clk) begin
    if(reset) begin
        inst_sram_addr_ok_reg <= 1'b0;
    end

    else if(inst_sram_addr_ok) begin
        inst_sram_addr_ok_reg <= 1'b1;
    end
end

/**
    tlb

    the tlb for inst
*/
assign va             = nextpc;
assign s0_va_highbits = nextpc[31:12];
assign s0_asid        = mmu_asid;
assign inst_sram_en    = inst_sram_req_reg;

endmodule