`timescale 1ns/1ps
module tb_album_auto;
 reg clk=0,source_clk=0,rst=0,next_key=1,prev_key=1,auto_key=1,scan_done=0,busy=1,motion=1;
 reg [3:0] count=3;reg completion_toggle=0;wire completed;
 always #10 clk=~clk;always #6.7 source_clk=~source_clk;
 wire request,auto_en,bright_mode,dim;wire [2:0] index;wire [9:0] progress;wire [4:0] bright;
 clip_done_sync bridge(clk,rst,completion_toggle,completed);
 album_ui #(.AUTO_CYCLES(80),.DEBOUNCE_CYCLES(3),.HOLD_CYCLES(40)) ui(
  clk,rst,next_key,prev_key,auto_key,scan_done,busy,count,request,index,auto_en,progress,bright,bright_mode,dim,motion,completed);
 integer requests=0,pulses=0,before_count;reg previous_request=0;
 always @(negedge clk)begin
  if(rst&&request)begin
   if(previous_request)$fatal(1,"duplicate load pulse");
   if(busy||index>=count)$fatal(1,"load while busy/out of range");
   requests=requests+1;
  end
  if(rst&&completed)pulses=pulses+1;
  previous_request=request;
 end
 task ticks;input integer n;begin repeat(n)@(posedge clk);#1;end endtask
 task finish_clip;begin @(negedge source_clk);completion_toggle=~completion_toggle;ticks(12);end endtask
 task tap_auto;begin @(negedge clk);auto_key=0;ticks(12);@(negedge clk);auto_key=1;ticks(12);end endtask
 task tap_next;begin @(negedge clk);next_key=0;ticks(12);@(negedge clk);next_key=1;ticks(12);end endtask
 task tap_prev;begin @(negedge clk);prev_key=0;ticks(12);@(negedge clk);prev_key=1;ticks(12);end endtask
 task assert_requests;input integer n;input [2:0] expected_index;begin
  if(requests!=n||index!=expected_index)$fatal(1,"playlist requests=%0d expected%0d index%0d expected%0d",requests,n,index,expected_index);
 end endtask
 initial begin
  #43;rst=1;ticks(5);scan_done=1;busy=0;ticks(1000);
  assert_requests(0,0); // Animation must not end at the still-photo timer.
  finish_clip;assert_requests(1,1);
  busy=1;finish_clip;assert_requests(1,1);busy=0;
  finish_clip;assert_requests(2,2);finish_clip;assert_requests(3,0);
  tap_auto;if(auto_en)$fatal(1,"pause failed");finish_clip;assert_requests(3,0);
  tap_next;assert_requests(4,1);tap_prev;assert_requests(5,0);
  tap_auto;if(!auto_en)$fatal(1,"resume failed");finish_clip;assert_requests(6,1);
  count=1;finish_clip;if(requests!=6)$fatal(1,"single-item clip must keep looping");count=3;
  motion=0;wait(request);ticks(2);busy=1;assert_requests(7,2);ticks(300);assert_requests(7,2);
  motion=1;busy=0;finish_clip;assert_requests(8,0);
  // A long brightness-mode press must not turn auto playback off.
  @(negedge clk);auto_key=0;ticks(55);@(negedge clk);auto_key=1;ticks(12);
  if(!auto_en||!bright_mode)$fatal(1,"long press changed autoplay");
  tap_prev;if(bright!=15)$fatal(1,"brightness control lost");assert_requests(8,0);
  @(negedge clk);auto_key=0;ticks(55);@(negedge clk);auto_key=1;ticks(12);
  if(bright_mode||!auto_en)$fatal(1,"brightness exit failed");
  finish_clip;assert_requests(9,1);
  if(pulses!=9)$fatal(1,"CDC completion pulses %0d expected9",pulses);
  $display("PASS ALBUM AUTO: 9 completion CDC pulses, one-shot animation advance, index wrap, still-photo timer, busy gating, pause/manual controls, singleton loop, brightness long press");$finish;
 end
 initial begin #1000000;$fatal(1,"album auto timeout");end
endmodule
