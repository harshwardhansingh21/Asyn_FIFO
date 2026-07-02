module fifo_wptr #(
    parameter addr_width = 4
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [addr_width:0]   wq2_rptr, // Synchronized read pointer input
    output reg                   full,
    output wire [addr_width-1:0] waddr,
    output reg  [addr_width:0]   wptr
);

    reg  [addr_width:0] wbin;
    wire [addr_width:0] wbinnext;
    wire [addr_width:0] wgrynext;
    wire wfull;

    assign waddr = wbin[addr_width-1:0];
    assign wbinnext = wbin + (wr_en && ~full);
    assign wgrynext = wbinnext ^ (wbinnext >> 1);
    assign wfull = (wgrynext=={~wq2_rptr[addr_width:addr_width-1],wq2_rptr[addr_width-2:0]});
always@(posedge wr_clk or negedge wr_rst_n)begin
    if(!wr_rst_n)begin
        full<=0;
        wptr<=0;
        wbin<=0;
    end
   else  begin
        wbin<=wbinnext;
        wptr<=wgrynext;
        full<=wfull;
        
       
    end
    
end


endmodule
