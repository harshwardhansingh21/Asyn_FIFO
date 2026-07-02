module cdc_sync #(
    parameter addr_width = 4
)(
    input clk,
    input rst_n,//asyn reset
    input [addr_width:0]data_in,
    output reg [addr_width:0]data_out
);
reg [addr_width:0]data_sync;
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            data_sync<=0;
        end
        else begin
            data_sync<=data_in;
        end
    end
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            data_out<=0;
        end
        else begin
            data_out<=data_sync;
        end
    end
endmodule
