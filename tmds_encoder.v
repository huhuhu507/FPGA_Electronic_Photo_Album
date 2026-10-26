`timescale 1ns/1ps
// DVI-compatible TMDS encoder. Running disparity and the symbol are updated
// together, for the SAME input pixel. Disparity is signed and measured in bits.
module tmds_encoder(
 input wire clk,rst_n,input wire [7:0] data,
 input wire de,input wire [1:0] control,
 output reg [9:0] symbol
);
 wire [8:0] q;
 tmds_qm transition_minimize(.vd(data),.qm(q));
 wire [4:0] ones={4'd0,q[0]}+{4'd0,q[1]}+{4'd0,q[2]}+{4'd0,q[3]}+
                   {4'd0,q[4]}+{4'd0,q[5]}+{4'd0,q[6]}+{4'd0,q[7]};
 wire signed [5:0] delta=$signed({1'b0,ones,1'b0})-6'sd8;
 reg signed [5:0] disparity;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin symbol<=10'b1101010100;disparity<=0;end
  else if(!de)begin
   disparity<=0;
   case(control)
    0:symbol<=10'b1101010100;
    1:symbol<=10'b0010101011;
    2:symbol<=10'b0101010100;
    3:symbol<=10'b1010101011;
   endcase
  end else if(disparity==0 || delta==0)begin
   symbol<={~q[8],q[8],q[8]?q[7:0]:~q[7:0]};
   disparity<=disparity+(q[8]?delta:-delta);
  end else if((disparity>0 && delta>0)||(disparity<0 && delta<0))begin
   symbol<={1'b1,q[8],~q[7:0]};
   disparity<=disparity-delta+(q[8]?6'sd2:6'sd0);
  end else begin
   symbol<={1'b0,q[8],q[7:0]};
   disparity<=disparity+delta-(q[8]?6'sd0:6'sd2);
  end
 end
endmodule
