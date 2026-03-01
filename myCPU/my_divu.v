module my_divu (
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
    assign s_axis_divisor_tready  = 1'b1;
    assign s_axis_dividend_tready = 1'b1;
    assign m_axis_dout_tvalid     = s_axis_divisor_tvalid & s_axis_dividend_tvalid;

    wire [31:0] dividend = s_axis_dividend_tdata;
    wire [31:0] divisor  = s_axis_divisor_tdata;
    wire [63:0] res;

    assign res[63:32] = (divisor == 0) ? 0 : (dividend % divisor);
    assign res[31:0]  = (divisor == 0) ? 0 : (dividend / divisor);

    assign m_axis_dout_tdata = {res[31:0], res[63:32]};
endmodule