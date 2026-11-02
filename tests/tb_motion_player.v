`timescale 1ns/1ps
module tb_motion_player;
 reg pc=0,mc=0,pr=0,mr=0,en=0,play=1,vblank=0;
 always #10 pc=~pc;always #7 mc=~mc;
 wire [20:0] fb,abase;wire epoch,pcm_valid,playing,req,clip_toggle;wire [15:0] fi,under;wire [9:0] progress,words;
 wire signed [15:0] l,r;reg [31:0] data=0;reg we=0,done=0;
 motion_player #(.PIXEL_HZ(480000)) dut(pc,mc,pr,mr,en,play,vblank,16'd3,16'd1600,21'd256,21'd768,32'd4800,
  fb,epoch,fi,progress,pcm_valid,l,r,playing,under,req,abase,words,data,we,done,clip_toggle);
 integer state=0,index=0,delay=0,transactions=0,samples=0,pauses=0,changes=0,cycles=0,expected_index=0,loops=0;
 reg [20:0] read_base;reg [9:0] read_words;reg [15:0] last_frame=0;reg was_blank=0;
 function [31:0] sample;
  input integer n;reg [15:0] left,right;begin left=n*73+123;right=~(n*97+321);sample={right,left};end
 endfunction
 // Delayed audio reads exercise pointer wraps, partial final bursts and buffering.
 always @(posedge mc)begin
  we<=0;done<=0;
  if(!mr)state<=0;
  else case(state)
   0:if(req)begin read_base<=abase;read_words<=words;index<=0;delay<=0;state<=1;transactions<=transactions+1;end
   1:if(delay==19)begin delay<=0;state<=2;end else delay<=delay+1;
   2:begin data<=sample(read_base-768+index);we<=1;index<=index+1;if(index+1==read_words)state<=3;end
   3:begin done<=1;state<=4;end
   4:if(!req)state<=0;
  endcase
 end
 // This test accelerates the sample clock; commits are deliberately not aligned to samples.
 always @(negedge pc)begin
  cycles=cycles+1;vblank=(cycles%80==0);
  if(en&&pcm_valid)begin
   if(playing)begin
    if({r,l}!==sample(samples%4800))$fatal(1,"PCM sequence at %0d got%h expected%h",samples,{r,l},sample(samples%4800));
    samples=samples+1;if(samples%4800==0)loops=loops+1;
   end else if(l!==0||r!==0)$fatal(1,"pause/inactive PCM is not silent");
  end
  if(pr&&fi!=last_frame)begin
   if(!was_blank)$fatal(1,"frame changed outside vblank");
   if(fb!==fi*256)$fatal(1,"frame base mismatch %0d %0d",fi,fb);
   changes=changes+1;last_frame=fi;
  end
  was_blank=vblank;
 end
 integer before_pause,frame_pause;
 initial begin
  #43;pr=1;mr=1;repeat(10)@(negedge pc);en=1;
  wait(samples>=1777);@(posedge pc);#1;play=0;before_pause=samples;frame_pause=dut.desired_index;
  repeat(1000)@(negedge pc);
  if(samples!=before_pause||dut.desired_index!=frame_pause)$fatal(1,"pause advanced timeline");
  @(posedge pc);#1;play=1;
  wait(samples>=14600);
  if(under||loops<3||changes<8||clip_toggle!=1)$fatal(1,"underflows%0d loops%0d changes%0d",under,loops,changes);
  @(posedge pc);#1;en=0;repeat(500)@(negedge pc);
  samples=0;last_frame=0;@(posedge pc);#1;en=1;
  wait(samples>=2000);
  if(under||clip_toggle!=1)$fatal(1,"restart underflow %0d or spurious completion",under);
  $display("PASS MOTION PLAYER: stereo sample order, 3 loops, vblank-only frames, pause/resume, disable/restart, partial bursts, %0d refills",transactions);$finish;
 end
 initial begin #10000000;$fatal(1,"motion timeout samples%0d fifo%0d state%0d",samples,dut.fifo_level,dut.read_state);end
endmodule
