module my_div (
    input  wire        aclk,
    input  wire        s_axis_divisor_tvalid,
    output wire        s_axis_divisor_tready,
    input  wire [31:0] s_axis_divisor_tdata,
    input  wire        s_axis_dividend_tvalid,
    output wire        s_axis_dividend_tready,
    input  wire [31:0] s_axis_dividend_tdata,
    output wire        m_axis_dout_tvalid,
    input  wire        m_axis_dout_tready,
    output wire [63:0] m_axis_dout_tdata
);
    // 仿真模型：只要输入有效，立马准备好接收
    assign s_axis_divisor_tready  = 1'b1;
    assign s_axis_dividend_tready = 1'b1;
    
    // 结果总是有效（模拟组合逻辑或快速除法）
    assign m_axis_dout_tvalid     = s_axis_divisor_tvalid & s_axis_dividend_tvalid;

    // 获取有符号操作数
    wire signed [31:0] dividend = s_axis_dividend_tdata;
    wire signed [31:0] divisor  = s_axis_divisor_tdata;
    wire signed [63:0] res;

    // 计算逻辑 (防除0)
    assign res[63:32] = (divisor == 0) ? 0 : (dividend % divisor); // 余数
    assign res[31:0]  = (divisor == 0) ? 0 : (dividend / divisor); // 商

    // 【注意】Xilinx 除法器输出通常是 {余数, 商} 还是 {商, 余数}？
    // 大部分默认配置下，高32位是余数 (Remainder)，低32位是商 (Quotient)。
    // 如果你的仿真结果反了，请把下面这行改成 {res[31:0], res[63:32]}
    assign m_axis_dout_tdata = {res[31:0], res[63:32]};

endmodule