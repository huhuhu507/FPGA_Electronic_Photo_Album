`timescale 1ns/1ps
module tb_video;
 reg pclk=0,mclk=0,prst=0,mrst=0;always #6.666667 pclk=~pclk;always #5.333333 mclk=~mclk;
 reg[11:0] w=1280,h=720;reg topdown=0,bank=0,cover_mode=0;
 wire[10:0] x;wire[9:0] y;wire[15:0] pixel,underflows;wire commit,req;wire[20:0] base;wire[9:0] words;
 reg[31:0] data=0;reg we=0,done=0;
 video_reader dut(pclk,mclk,prst,mrst,1'b1,bank,w,h,topdown,cover_mode,x,y,pixel,commit,req,base,words,data,we,done,underflows,21'd0,1'b0);
 integer engine=0,counter=0,phase=0,received=0,frame=0,checks=0,i,source_x,source_y,address,expected;
 integer fw,fh,left,top,cw,ch,cx,cy;
 function[15:0] val;input integer a;begin val=(a*13)^(a>>7)^16'ha55a;end endfunction
 always @(posedge mclk)begin
  we<=0;done<=0;
  if(!mrst)begin engine<=0;counter<=0;phase<=0;end
  else case(engine)
   0:if(req)begin engine<=1;counter<=0;phase<=0;end
   1:begin phase<=phase+1;
     if(phase==1)begin phase<=0;we<=1;data<={val((base+counter)*2+1),val((base+counter)*2)};counter<=counter+1;
      if(counter+1==words)engine<=2;
     end
   end
   2:begin done<=1;engine<=3;end
   3:if(!req)engine<=0;
  endcase
 end
 always @(negedge pclk)begin
  if(prst)begin
   if(x==1649 && y==749)frame=frame+1;
   if(frame>=1 && x<1280 && y<720)begin
    if(w*540>=h*960)begin fw=960;fh=h*960/w;end else begin fh=540;fw=w*540/h;end
    cw=w;ch=h;cx=0;cy=0;
    if(cover_mode)begin
     if(w*540>=h*960)begin cw=h*960/540;cx=(w-cw)/2;end
     else begin ch=w*540/960;cy=(h-ch)/2;end
     fw=960;fh=540;
    end
    left=32+(960-fw)/2;top=96+(540-fh)/2;
    if(x<left||x>=left+fw||y<top||y>=top+fh)expected=0;
    else begin
     source_x=cx+(x-left)*cw/fw;
     source_y=topdown ? cy+(y-top)*ch/fh : h-1-cy-(y-top)*ch/fh;
     address=(bank?1048576:0)+source_y*w+source_x;expected=val(address);
    end
    if(pixel!==expected[15:0])$fatal(1,"pixel x%0d y%0d frame%0d w%0d got%h expected%h sx%0d sy%0d",x,y,frame,w,pixel,expected[15:0],source_x,source_y);
    checks=checks+1;
   end
  end
 end
 task mode;input[11:0] nw,nh;input nt,nb;begin
  prst=0;mrst=0;frame=0;w=nw;h=nh;topdown=nt;bank=nb;
  #100;prst=1;mrst=1;
  wait(frame==2);#1;
 end endtask
 initial begin
  mode(1280,720,0,0);mode(640,480,0,1);mode(18,16,1,0);mode(640,720,1,1);mode(1280,16,0,1);
  cover_mode=1;mode(1280,720,0,0);mode(640,480,0,1);mode(18,16,1,0);mode(640,720,1,1);mode(1280,16,0,1);
  // Odd crop origin exercises the high half of the first SDRAM word.
  mode(1280,480,0,1);
  // A real UI mode switch keeps metadata and memory alive; it never resets RTL.
  wait(x==0 && y==724);cover_mode=0;frame=0;
  wait(frame==2);#1;
  $display("PASS VIDEO: %0d pixel comparisons, contain/cover, five aspect ratios, odd crop origin, live mode switch, top-down/bottom-up, both banks, line parity and BRAM latency",checks);$finish;
 end
 initial begin #500000000;$fatal(1,"video timeout");end
endmodule
