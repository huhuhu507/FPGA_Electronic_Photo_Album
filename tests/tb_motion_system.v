`timescale 1ns/1ps
// Real production video/audio clocks, actual read arbiter and SDRAM controller.
// No ideal line-reader shortcut: SDRAM CL=3 data is modeled at the pin interface.
module tb_motion_system;
 reg pc=0,mc=0,memclk=0,rst=0,en=0,play=1;
 always #6.734007 pc=~pc;
 always #5.387205 mc=~mc;
 initial begin #2.693603;forever #5.387205 memclk=~memclk;end
 wire [10:0] x;wire [9:0] y;wire [15:0] pixel,video_under;
 wire commit,vreq,vwe,vdone,areq,awe,adone,mreq,mwe,mdone;
 wire [20:0] vbase,abase,mbase,fb;wire [9:0] vwords,awords,mwords,progress;
 wire [31:0] vdata,adata,mdata;wire epoch,pvalid,playing,clip_toggle;
 wire signed [15:0] left,right;wire [15:0] frame_index,audio_under;
 video_reader #(.EXPLICIT_BASE(1)) reader(pc,mc,rst,rst,en,epoch,12'd320,12'd180,1'b1,1'b1,x,y,pixel,commit,vreq,vbase,vwords,vdata,vwe,vdone,video_under,fb,1'b0);
 motion_player player(pc,mc,rst,rst,en,play,commit,16'd2,16'd1600,21'd28800,21'd57600,32'd3200,
  fb,epoch,frame_index,progress,pvalid,left,right,playing,audio_under,areq,abase,awords,adata,awe,adone,clip_toggle);
 sdram_read_arbiter arb(mc,rst,vreq,vbase,vwords,vdata,vwe,vdone,areq,abase,awords,adata,awe,adone,mreq,mbase,mwords,mdata,mwe,mdone);
 wire ras,cas,wen,init_done,wr_ack;wire [10:0] addr;wire [1:0] ba;tri [31:0] dq;
 sdram_ctrl_clean mem(mc,rst,ras,cas,wen,addr,ba,dq,init_done,1'b0,32'd0,21'd0,1'b0,wr_ack,mreq,mbase,mwords,mdata,mwe,mdone);
 reg [31:0] memory[0:2097151];reg [10:0] rows[0:3];
 reg [2:0] pipe=0;reg [31:0] p0,p1,p2,outdata;reg drive=0;
 assign dq=drive?outdata:32'bz;
 integer k,frames=0,checks=0,samples=0,refreshes=0,loops=0,pauses=0,expected,source_x,source_y,debug_reads=0;
 function automatic [15:0] pix;input integer n;begin pix=(n*13)^(n>>7)^16'ha55a;end endfunction
 function automatic [31:0] pcm;input integer n;reg [15:0] l,r;begin l=n*23+1000;r=~(n*43+2000);pcm={r,l};end endfunction
 always @(posedge memclk)begin
  pipe<={pipe[1:0],{ras,cas,wen}==3'b101};
  if({ras,cas,wen}==3'b011)rows[ba]<=addr;
  if({ras,cas,wen}==3'b101)begin
   p0<=memory[{ba,rows[ba],addr[7:0]}];
   if($test$plusargs("DEBUG")&&debug_reads<8)begin $display("READ a=%0d v=%h t=%t",{ba,rows[ba],addr[7:0]},memory[{ba,rows[ba],addr[7:0]}],$time);debug_reads=debug_reads+1;end
  end
  p1<=p0;p2<=p1;drive<=#5 pipe[2];outdata<=#5 p2;
  if({ras,cas,wen}==3'b001)refreshes=refreshes+1;
 end
 always @(negedge pc)begin
  if(rst)begin
   if(x==1649&&y==749)frames=frames+1;
   if(en&&x>=32&&x<992&&y>=96&&y<636)begin
    source_x=(x-32)/3;source_y=(y-96)/3;expected=pix(fb*2+source_y*320+source_x);
    if(pixel!==expected[15:0])$fatal(1,"integration pixel frame%0d fi%0d x%0d y%0d got%h expected%h under%0d lb0=%h q0=%h fb=%h",frames,frame_index,x,y,pixel,expected[15:0],video_under,reader.lb0[0],reader.q0,fb);
    checks=checks+1;
   end
   if(en&&pvalid&&playing)begin
    if({right,left}!==pcm(samples%3200))$fatal(1,"integration PCM sample%0d got%h expected%h",samples,{right,left},pcm(samples%3200));
    samples=samples+1;if(samples%3200==0)loops=loops+1;
   end
  end
 end
 integer paused_at;
 initial begin
  for(k=0;k<57600;k=k+1)begin memory[k][15:0]=pix(k*2);memory[k][31:16]=pix(k*2+1);end
  for(k=0;k<3200;k=k+1)memory[57600+k]=pcm(k);
  if($test$plusargs("DEBUG"))$display("INIT mem0=%h mem1=%h",memory[0],memory[1]);
  #42;rst=1;wait(init_done);@(posedge pc);#1;en=1;
  wait(frames==8);@(posedge pc);#1;play=0;paused_at=samples;
  wait(frames==11);
  if(samples!=paused_at)$fatal(1,"integration pause advanced audio");
  @(posedge pc);#1;play=1;
  wait(frames==17);#1;
  if(video_under||audio_under||loops<2)$fatal(1,"integration underflows v%0d a%0d loops%0d",video_under,audio_under,loops);
  $display("PASS MOTION SYSTEM: %0d exact pixels + %0d stereo samples, real SDRAM CL3/refresh/arbitration, loops=%0d, pause/resume, zero underflows",checks,samples,loops);$finish;
 end
 initial begin #400000000;$fatal(1,"system timeout frames%0d samples%0d",frames,samples);end
endmodule
