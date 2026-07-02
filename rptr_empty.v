module fifo_rptr #(
    parameter addr_width = 4
)(
    input rd_clk,
    input rd_rst_n,//asyn reset
    input rd_en,
    input [addr_width:0]rq2_wptr,
    output reg empty,
    output wire [addr_width-1:0] raddr,
    output reg [addr_width:0]rptr
);
    reg  [addr_width:0]rbin;
    wire [addr_width:0] rbinnext;
    wire [addr_width:0] rgrynext;

    assign raddr=rbin[addr_width-1:0];
    assign rbinnext=rbin+(rd_en&&~empty);
    assign rgrynext=rbinnext ^ (rbinnext >> 1);

always@(posedge rd_clk or negedge rd_rst_n)begin
    if(!rd_rst_n)begin
        empty<=1'b1;
        rptr<=0;
        rbin<=0;
    end
   else  begin
        rbin<=rbinnext;
        rptr<=rgrynext;
        empty<=(rgrynext==rq2_wptr);
       
    end
    
end

endmodule
