`timescale 1ns/1ps
// Full-resolution, double-line-buffered picture reader. Pixel/OSD coordinates
// and RGB565 emerge together after two registered cycles; no CAL_X correction.
module video_reader #(
 parameter VIEW_X=32, VIEW_Y=96, VIEW_W=960, VIEW_H=540
)(
 input wire pclk,mclk,prst_n,mrst_n,
 input wire valid,frame_bank, input wire [11:0] img_w,img_h,
 input wire topdown,cover_mode,
 output reg [10:0] x,output reg [9:0] y,
 output reg [15:0] pixel,
 output wire vblank_commit,
 output reg line_req,output reg [20:0] line_base,
 output reg [9:0] line_words,
 input wire [31:0] line_data,input wire line_we,line_done,
 output reg [15:0] underflows
);
 reg [10:0] hx;reg [9:0] vy;
 assign vblank_commit=(hx==0 && vy==724);
 // Geometry is computed only when image metadata changes.  The divide is
 // a 32-step restoring divider, never a variable combinational divider.
 reg [11:0] width_seen,height_seen;
 reg [3:0] fit_state;
 reg fit_ready,fit_by_width,cover_seen;
 reg [11:0] crop_width,crop_height;reg [10:0] crop_left,crop_top;
 reg [31:0] wide_product,tall_product;
 reg [31:0] dividend,divisor,quotient,remainder;
 reg [5:0] divide_count;
 reg [10:0] fit_width,fit_height;
 reg [10:0] content_left,content_top;
 wire [32:0] division_trial={remainder,dividend[31]};
 wire division_take=division_trial>={1'b0,divisor};
 wire [31:0] division_remainder=division_take ? division_trial-{1'b0,divisor} : division_trial[31:0];
 wire [31:0] division_quotient={quotient[30:0],division_take};
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin
   width_seen<=0;height_seen<=0;fit_state<=0;fit_ready<=0;fit_by_width<=0;cover_seen<=0;crop_width<=1;crop_height<=1;crop_left<=0;crop_top<=0;
   wide_product<=0;tall_product<=0;dividend<=0;divisor<=1;quotient<=0;remainder<=0;divide_count<=0;
   fit_width<=1;fit_height<=1;content_left<=VIEW_X;content_top<=VIEW_Y;
  end else if(!valid)begin fit_ready<=0;fit_state<=0;width_seen<=0;height_seen<=0;end
  else if(img_w!=width_seen || img_h!=height_seen || cover_mode!=cover_seen)begin
   width_seen<=img_w;height_seen<=img_h;cover_seen<=cover_mode;fit_state<=1;fit_ready<=0;
  end else case(fit_state)
   1:begin wide_product<=width_seen*VIEW_H;tall_product<=height_seen*VIEW_W;fit_state<=2;end
   2:begin
    quotient<=0;remainder<=0;divide_count<=31;fit_by_width<=wide_product>=tall_product;
    crop_width<=width_seen;crop_height<=height_seen;crop_left<=0;crop_top<=0;
    if(cover_seen)begin
     fit_width<=VIEW_W;fit_height<=VIEW_H;
     if(wide_product>=tall_product)begin dividend<=tall_product;divisor<=VIEW_H;end
     else begin dividend<=wide_product;divisor<=VIEW_W;end
    end else if(wide_product>=tall_product)begin
     fit_width<=VIEW_W;dividend<=tall_product;divisor<={20'd0,width_seen};
    end else begin fit_height<=VIEW_H;dividend<=wide_product;divisor<={20'd0,height_seen};end
    fit_state<=3;
   end
   3:begin
    dividend<={dividend[30:0],1'b0};quotient<=division_quotient;remainder<=division_remainder;
    if(divide_count==0)begin
     if(cover_seen)begin
      if(fit_by_width)crop_width<=(division_quotient==0)?12'd1:division_quotient[11:0];
      else crop_height<=(division_quotient==0)?12'd1:division_quotient[11:0];
     end else if(fit_by_width)fit_height<=(division_quotient==0)?11'd1:division_quotient[10:0];
     else fit_width<=(division_quotient==0)?11'd1:division_quotient[10:0];
     fit_state<=4;
    end else divide_count<=divide_count-1'b1;
   end
   4:begin
    crop_left<=(width_seen-crop_width)/2;crop_top<=(height_seen-crop_height)/2;
    content_left<=VIEW_X+(VIEW_W-fit_width)/2;
    content_top<=VIEW_Y+(VIEW_H-fit_height)/2;
    fit_ready<=1;fit_state<=5;
   end
  endcase
 end
 wire visible=valid && fit_ready && hx>=content_left && hx<content_left+fit_width &&
              vy>=content_top && vy<content_top+fit_height;
 reg [11:0] xacc;reg [10:0] sx;
 wire [12:0] xsum={1'b0,xacc}+{1'b0,crop_width};
 wire [12:0] xden={2'd0,fit_width};
 // With the supported image limits, contain scale-down is at most 4/3.
 // Parallel subtract/select avoids two cascaded DSP multipliers per pixel.
 wire [12:0] xden2={xden[11:0],1'b0};
 wire [1:0] xstep=(xsum>=xden2)?2'd2:(xsum>=xden)?2'd1:2'd0;
 wire [12:0] xresidue=(xsum>=xden2)?(xsum-xden2):(xsum>=xden)?(xsum-xden):xsum;
 reg [11:0] vacc;reg [9:0] source_row;
 wire [12:0] vsum={1'b0,vacc}+{1'b0,crop_height};
 wire [12:0] yden={2'd0,fit_height};
 wire [12:0] yden2={yden[11:0],1'b0};
 wire [1:0] ystep=(vsum>=yden2)?2'd2:(vsum>=yden)?2'd1:2'd0;
 wire [12:0] yresidue=(vsum>=yden2)?(vsum-yden2):(vsum>=yden)?(vsum-yden):vsum;
 wire [9:0] target_y=(vy==749) ? 10'd0 : vy+1'b1;
 wire fetch_line=fit_ready && valid && target_y>=content_top && target_y<content_top+fit_height;
 wire first_source_line=(target_y==content_top);
 wire [9:0] next_row=first_source_line ? 10'd0 : source_row+ystep;
 wire [9:0] stride=img_w[10:1];
 reg [9:0] row_candidate;
 reg [11:0] memory_row_r;
 reg [20:0] row_address;
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin row_candidate<=0;memory_row_r<=0;row_address<=0;end
  else begin
   row_candidate<=next_row+crop_top;
   memory_row_r<=topdown ? {2'd0,row_candidate} : img_h-12'd1-{2'd0,row_candidate};
   row_address<=memory_row_r*stride;
  end
 end

 reg command_toggle;
 reg [20:0] command_base;
 reg [9:0] command_words,command_y;
 reg command_bank,command_epoch;
 reg [2:0] command_sync;
 reg [9:0] write_addr;
 reg write_bank,write_epoch;
 reg [9:0] write_y;
 reg [2:0] engine;
 reg [10:0] received;
 reg [11:0] tag0,tag1;
 reg [11:0] tag0a,tag0b,tag1a,tag1b;
 reg [31:0] lb0[0:639],lb1[0:639];
 reg [31:0] q0,q1;
 reg [10:0] x1;reg [9:0] y1;
 reg half1,bank1,active1;
 wire tag_ok=vy[0] ? (tag1b=={1'b1,frame_bank,vy}) : (tag0b=={1'b1,frame_bank,vy});
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin
   hx<=0;vy<=0;x<=0;y<=0;x1<=0;y1<=0;pixel<=0;
   xacc<=0;sx<=0;vacc<=0;source_row<=0;
   command_toggle<=0;command_base<=0;command_words<=0;command_y<=0;command_bank<=0;command_epoch<=0;
   half1<=0;bank1<=0;active1<=0;
   tag0a<=0;tag0b<=0;tag1a<=0;tag1b<=0;underflows<=0;
  end else begin
   tag0a<=tag0;tag0b<=tag0a;tag1a<=tag1;tag1b<=tag1a;
   if(hx==1649)begin hx<=0;vy<=(vy==749)?0:vy+1'b1;end else hx<=hx+1'b1;
   if(!visible)begin xacc<=0;sx<=crop_left;end
   else begin xacc<=xresidue[11:0];sx<=sx+xstep;end
   x1<=hx;y1<=vy;half1<=sx[0];bank1<=vy[0];active1<=visible&&tag_ok;
   x<=x1;y<=y1;
   pixel<=active1 ? (half1 ? (bank1?q1[31:16]:q0[31:16]) : (bank1?q1[15:0]:q0[15:0])) : 16'h0000;
   if(hx==500)begin
    if(fetch_line)begin
     command_base<=(frame_bank ? 21'd524288 : 21'd0)+row_address;
     command_words<=stride;command_y<=target_y;
     command_bank<=target_y[0];command_epoch<=frame_bank;
     if(valid)command_toggle<=~command_toggle;
     source_row<=next_row;
     vacc<=first_source_line ? 12'd0 : yresidue[11:0];
    end else begin vacc<=0;source_row<=0;end
   end
   if(hx==content_left && vy>=content_top && vy<content_top+fit_height && valid && fit_ready && !tag_ok && underflows!=16'hffff)underflows<=underflows+1'b1;
  end
 end
 // One synchronous BRAM read. Both pixel half and coordinates have the same latency.
 always @(posedge pclk)begin q0<=lb0[sx[10:1]];q1<=lb1[sx[10:1]];end
 always @(posedge mclk)begin
  if(line_we && engine==1 && write_addr<640)begin
   if(write_bank)lb1[write_addr]<=line_data;else lb0[write_addr]<=line_data;
  end
 end
 always @(posedge mclk or negedge mrst_n)begin
  if(!mrst_n)begin
   command_sync<=0;engine<=0;line_req<=0;line_base<=0;line_words<=0;
   write_addr<=0;write_bank<=0;write_y<=0;write_epoch<=0;received<=0;tag0<=0;tag1<=0;
  end else begin
   command_sync<={command_sync[1:0],command_toggle};
   case(engine)
    0:if(command_sync[2]^command_sync[1])begin
     line_base<=command_base;line_words<=command_words;write_bank<=command_bank;
     write_y<=command_y;write_epoch<=command_epoch;write_addr<=0;received<=0;line_req<=1;engine<=1;
    end
    1:begin
     if(line_we)begin write_addr<=write_addr+1'b1;received<=received+1'b1;end
     if(line_done)begin line_req<=0;engine<=2;end
    end
    2:begin
     if(received=={1'b0,line_words})begin
      if(write_bank)tag1<={1'b1,write_epoch,write_y};else tag0<={1'b1,write_epoch,write_y};
     end
     engine<=0;
    end
   endcase
  end
 end
endmodule
