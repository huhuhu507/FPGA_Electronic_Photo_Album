`timescale 1ns/1ps
// Snapshot 176 actual PCM samples at 12kHz into the inactive scope buffer.
// Once complete, freeze it until the next frame boundary: no mid-frame tearing.
module audio_scope(input wire clk,rst_n,frame_tick,pcm_valid,
 input wire signed [15:0] pcm,input wire [7:0] read_x,
 output reg [5:0] sample,previous);
 reg [5:0] wave0[0:175],wave1[0:175];
 reg write_bank,read_bank,ready,have_window;
 reg [7:0] index;reg [1:0] decimate;
 wire signed [8:0] amplitude=$signed(pcm)>>>8;
 wire signed [8:0] clipped=(amplitude>9'sd27)?9'sd27:(amplitude< -9'sd27)?-9'sd27:amplitude;
 wire [5:0] height=9'sd32-clipped;
 reg [7:0] read_index,prior_index;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin read_index<=0;prior_index<=0;sample<=32;previous<=32;end
  else begin
   read_index<=read_x;prior_index<=(read_x==0)?8'd0:read_x-1'b1;
   sample<=(!have_window || read_index>=176)?6'd32:(read_bank?wave1[read_index]:wave0[read_index]);
   previous<=(!have_window || prior_index>=176)?6'd32:(read_bank?wave1[prior_index]:wave0[prior_index]);
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin write_bank<=0;read_bank<=1;ready<=0;have_window<=0;index<=0;decimate<=0;end
  else begin
   if(frame_tick && ready)begin
    read_bank<=write_bank;write_bank<=~write_bank;ready<=0;have_window<=1;index<=0;
   end
   if(pcm_valid && !ready)begin
    decimate<=decimate+1'b1;
    if(decimate==0)begin
     if(write_bank)wave1[index]<=height;else wave0[index]<=height;
     if(index==175)ready<=1;else index<=index+1'b1;
    end
   end
  end
 end
endmodule
