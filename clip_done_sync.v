`timescale 1ns/1ps
// A source toggle records every completed clip; disabling a player must not
// reset that toggle. The destination sees exactly one clk50 pulse per clip.
module clip_done_sync(input wire clk,rst_n,completion_toggle,output wire done);
 (* ASYNC_REG="TRUE" *) reg [2:0] sync;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)sync<=0;else sync<={sync[1:0],completion_toggle};
 end
 assign done=sync[2]^sync[1];
endmodule
