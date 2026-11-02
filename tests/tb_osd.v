`timescale 1ns/1ps
module tb_osd;
 reg clk=0,rst_n=0;always #6.734007 clk=~clk;
 reg [10:0] x=0;reg [9:0] y=0;wire [10:0] ox;wire [9:0] oy;wire [15:0] rgb;wire [7:0] wx;
 wire[15:0] photo={x[4:0],y[5:0],(x[4:0]^y[4:0])};
 signage_osd dut(.clk(clk),.rst_n(rst_n),.x(x),.y(y),.photo(photo),.valid(1'b1),.sd_ready(1'b1),.scan_done(1'b1),.busy(1'b0),.auto_en(1'b1),.bright_mode(1'b0),.test_mode(1'b0),.cover_mode(1'b1),.image_index(3'd1),.image_count(4'd4),.error(4'd0),.brightness(5'd16),.progress(10'd300),.image_width(12'd1280),.image_height(12'd720),.wave_sample(6'd32),.wave_previous(6'd32),.audio_active(1'b0),.wave_x(wx),.rgb(rgb),.out_x(ox),.out_y(oy),.motion_mode(1'b0),.read_divider(8'd1),.load_deciseconds(12'd12));
 `include "tests/osd_golden_count.vh"
 reg[39:0] golden[0:GOLDEN_COUNT-1];
 integer frame=0,n=0,address,fd,pixels=0;
 always @(posedge clk)if(rst_n)begin if(x==1649)begin x<=0;y<=(y==749)?0:y+1'b1;end else x<=x+1'b1;end
 always @(negedge clk)if(rst_n)begin
  if(ox==1649&&oy==749)frame=frame+1;
  if(frame==1&&ox<1280&&oy<720)begin
   address=oy*1280+ox;
   if(n<GOLDEN_COUNT && address==golden[n][39:16])begin
    if(rgb!==golden[n][15:0])$fatal(1,"UI pixel mismatch x%0d y%0d got%h expected%h",ox,oy,rgb,golden[n][15:0]);
    n=n+1;
   end
   $fwrite(fd,"%04x\n",rgb);pixels=pixels+1;
  end
  if(frame==2)begin
   if(n!=GOLDEN_COUNT||pixels!=921600)$fatal(1,"UI missing pixels %0d samples %0d/%0d",pixels,n,GOLDEN_COUNT);
   $fclose(fd);$display("PASS OSD: %0d independent golden text pixels, full frame alignment, ASCII/CJK cells and gaps",n);$finish;
  end
 end
 initial begin $readmemh("tests/osd_golden.hex",golden);fd=$fopen("tests/osd_frame.hex","w");#50;rst_n=1;end
 initial begin #40000000;$fatal(1,"OSD timeout");end
endmodule
