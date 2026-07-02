module fifo_mem #(
    parameter DATA_WIDTH = 8,   // Size of each data word (default 8 bits)
    parameter ADDR_WIDTH = 4,   // Number of address bits
    parameter FIFO_DEPTH = 16   // Total storage depth (2^ADDR_WIDTH)
)(
    
    input  wire wr_clk,
    input  wire wr_en,    
    input  wire [ADDR_WIDTH-1:0] waddr,    
    input  wire [DATA_WIDTH-1:0] din,      
    
    
    input  wire [ADDR_WIDTH-1:0] raddr,    
    output wire [DATA_WIDTH-1:0] dout      
);

    
    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    always @(posedge wr_clk) begin
        if (wr_en) begin
            mem[waddr] <= din;
        end
    end

    assign dout = mem[raddr];

endmodule
