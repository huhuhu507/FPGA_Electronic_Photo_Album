`timescale 1ns/1ps
// 1024 stereo samples; independent clocks, Gray-coded pointer crossings.
// The read port is synchronous: rd_valid follows an accepted rd_en by one edge.
module async_audio_fifo(
 input wire wclk,wrst_n,wr_en,input wire [31:0] wr_data,
 output wire full,output wire [10:0] wr_level,
 input wire rclk,rrst_n,rd_en,output reg [31:0] rd_data,
 output reg rd_valid,output wire empty
);
 reg [31:0] storage[0:1023];
 reg [10:0] wb,rb,wg,rg;
 (* ASYNC_REG="TRUE" *) reg [10:0] rg1,rg2,wg1,wg2;
 function [10:0] gray_binary;
  input [10:0] g;integer k;begin
   gray_binary[10]=g[10];
   for(k=9;k>=0;k=k-1)gray_binary[k]=gray_binary[k+1]^g[k];
  end
 endfunction
 assign full=(wg=={~rg2[10:9],rg2[8:0]});
 assign empty=(rg==wg2);
 assign wr_level=wb-gray_binary(rg2);
 always @(posedge wclk or negedge wrst_n)begin
  if(!wrst_n)begin wb<=0;wg<=0;rg1<=0;rg2<=0;end
  else begin
   rg1<=rg;rg2<=rg1;
   if(wr_en&&!full)begin wb<=wb+1'b1;wg<=((wb+1'b1)>>1)^(wb+1'b1);end
  end
 end
 always @(posedge wclk)if(wr_en&&!full)storage[wb[9:0]]<=wr_data;
 always @(posedge rclk or negedge rrst_n)begin
  if(!rrst_n)begin rb<=0;rg<=0;wg1<=0;wg2<=0;rd_valid<=0;end
  else begin
   wg1<=wg;wg2<=wg1;rd_valid<=0;
   if(rd_en&&!empty)begin rb<=rb+1'b1;rg<=((rb+1'b1)>>1)^(rb+1'b1);rd_valid<=1;end
  end
 end
 always @(posedge rclk)if(rd_en&&!empty)rd_data<=storage[rb[9:0]];
endmodule
