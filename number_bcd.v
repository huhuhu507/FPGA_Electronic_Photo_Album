`timescale 1ns/1ps
module number_bcd(input wire clk,rst_n,start,input wire [11:0] value,output reg [15:0] bcd);
 reg [27:0] shift;reg [3:0] count;reg running;reg [27:0] adjusted;
 integer i;
 always @* begin
  adjusted=shift;
  for(i=0;i<4;i=i+1)if(shift[12+i*4 +: 4]>=5)adjusted[12+i*4 +: 4]=shift[12+i*4 +: 4]+4'd3;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin shift<=0;count<=0;running<=0;bcd<=0;end
  else if(start)begin shift<={16'd0,value};count<=0;running<=1;end
  else if(running)begin
   shift<=adjusted<<1;
   if(count==11)begin bcd<=adjusted[26:11];running<=0;end else count<=count+1'b1;
  end
 end
endmodule
