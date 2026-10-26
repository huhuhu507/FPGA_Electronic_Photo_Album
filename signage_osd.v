`timescale 1ns/1ps
// LUMA gallery UI. All text uses one shared two-bit-alpha font ROM and one
// pipeline. Coordinates, glyph columns and character cells cannot diverge.
module signage_osd #(parameter PIXEL_HZ=74250000)(
 input wire clk,rst_n,input wire [10:0] x,input wire [9:0] y,
 input wire [15:0] photo,input wire valid,sd_ready,scan_done,busy,auto_en,bright_mode,test_mode,cover_mode,
 input wire [2:0] image_index,input wire [3:0] image_count,error,
 input wire [4:0] brightness,input wire [9:0] progress,
 input wire [11:0] image_width,image_height,
 input wire [5:0] wave_sample,wave_previous,input wire audio_active,
 output wire [7:0] wave_x,
 output reg [15:0] rgb,output reg [10:0] out_x,output reg [9:0] out_y);
 wire frame_tick=(x==0 && y==724);
 reg sd_l,scan_l,busy_l,auto_l,valid_l,bmode_l,test_l,audio_l,cover_l;
 reg [2:0] index_l;reg [3:0] count_l,error_l;reg [4:0] bright_l;reg [9:0] progress_l;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sd_l<=0;scan_l<=0;busy_l<=0;auto_l<=1;valid_l<=0;bmode_l<=0;test_l<=0;audio_l<=0;cover_l<=1;index_l<=0;count_l<=0;error_l<=0;bright_l<=16;progress_l<=0;end
  else if(frame_tick)begin sd_l<=sd_ready;scan_l<=scan_done;busy_l<=busy;auto_l<=auto_en;valid_l<=valid;bmode_l<=bright_mode;test_l<=test_mode;audio_l<=audio_active;cover_l<=cover_mode;index_l<=image_index;count_l<=image_count;error_l<=error;bright_l<=brightness;progress_l<=progress;end
 end
 wire [15:0] width_bcd,height_bcd;
 number_bcd bw(clk,rst_n,frame_tick,image_width,width_bcd);
 number_bcd bh(clk,rst_n,frame_tick,image_height,height_bcd);
 reg [26:0] second_div;reg [7:0] seconds,minutes,hours;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin second_div<=0;seconds<=0;minutes<=0;hours<=0;end
  else if(second_div==PIXEL_HZ-1)begin
   second_div<=0;
   if(seconds==8'h59)begin
    seconds<=0;
    if(minutes==8'h59)begin
     minutes<=0;
     if(hours==8'h99)hours<=0;else if(hours[3:0]==9)hours<=hours+8'd7;else hours<=hours+1'b1;
    end else if(minutes[3:0]==9)minutes<=minutes+8'd7;else minutes<=minutes+1'b1;
   end else if(seconds[3:0]==9)seconds<=seconds+8'd7;else seconds<=seconds+1'b1;
  end else second_div<=second_div+1'b1;
 end
 reg [9:0] scroll;reg alternate;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin scroll<=0;alternate<=0;end
  else if(frame_tick)begin alternate<=~alternate;if(alternate)scroll<=scroll+1'b1;end
 end
 wire [10:0] ticker_position=(x-11'd128)+{1'b0,scroll};
 function [11:0] percent_bcd;
  input [4:0] n;
  begin case(n)
   4:percent_bcd=12'h025;5:percent_bcd=12'h031;6:percent_bcd=12'h038;7:percent_bcd=12'h044;
   8:percent_bcd=12'h050;9:percent_bcd=12'h056;10:percent_bcd=12'h063;11:percent_bcd=12'h069;
   12:percent_bcd=12'h075;13:percent_bcd=12'h081;14:percent_bcd=12'h088;15:percent_bcd=12'h094;
   default:percent_bcd=12'h100;
  endcase end
 endfunction
 wire [11:0] percentage=percent_bcd(bright_l);
 wire [19:0] progress_product=progress_l*10'd302;
 wire [9:0] progress_width=progress_product[19:10];
 wire [8:0] bright_width=bright_l*9'd11;
 // Scope has two registered read stages: prefetch two pixels ahead.
 assign wave_x=(x>=1038 && x<1214)?x-11'd1038:8'd0;
 wire [5:0] wave_line=y[5:0]-6'd56;
 wire [5:0] wave_low=(wave_sample<wave_previous)?wave_sample:wave_previous;
 wire [5:0] wave_high=(wave_sample>wave_previous)?wave_sample:wave_previous;
 wire in_photo=(x>=32&&x<992&&y>=96&&y<636);
 reg [15:0] base_rgb;
 wire [2:0] test_bar;
 assign test_bar[2]=(x>=512);
 assign test_bar[1]=(x>=272&&x<512)||(x>=752);
 assign test_bar[0]=(x>=152&&x<272)||(x>=392&&x<512)||(x>=632&&x<752)||(x>=872);
 always @* begin
  base_rgb=16'h08a3;
  if(y<80)base_rgb=16'h08c4;
  if(y==79)base_rgb=16'h2168;
  if(x>=32&&x<64&&y>=24&&y<56)begin
   base_rgb=16'h56d7;
   if((x>=40&&x<44&&y>=32&&y<48)||(x>=48&&x<56&&y>=44&&y<48))base_rgb=16'h08c4;
  end
  if(x>=31&&x<=992&&y>=95&&y<=636)base_rgb=16'h2168;
  if(in_photo)begin
   base_rgb=photo;
   if(!valid_l)base_rgb=(x[5:0]==0||y[5:0]==0)?16'h10e5:16'h08a3;
   if(test_l)base_rgb=(x[5:0]==0||y[5:0]==0)?16'hffff:{{5{test_bar[2]}},{6{test_bar[1]}},{5{test_bar[0]}}};
  end
  if(x>=1024&&x<1248&&y>=96&&y<636)base_rgb=16'h1105;
  if(x>=1040&&x<1232&&(y==279||y==375))base_rgb=16'h2168;
  if(x>=1040&&x<1216&&y>=352&&y<356)base_rgb=((x-1040)<progress_width)?16'h56d7:16'h2168;
  if(x>=1040&&x<1216&&y>=452&&y<458)base_rgb=((x-1040)<bright_width)?16'h56d7:16'h2168;
  if(bmode_l && x>=1032&&x<1035&&y>=384&&y<462)base_rgb=16'h56d7;
  if(x>=1040&&x<1216&&y>=504&&y<568)begin
   base_rgb=(x[4:0]==16||y[3:0]==8)?16'h1946:16'h08c4;
   if(wave_line>=wave_low && wave_line<=wave_high)base_rgb=audio_l?16'h56d7:16'h428a;
  end
  if(x>=32&&x<1248&&y>=656&&y<688)base_rgb=16'h08c4;
  if(x>=112&&x<114&&y>=664&&y<680)base_rgb=16'h2168;
  if(x>=1216&&x<1224&&y>=36&&y<44)base_rgb=(error_l!=0)?16'hf5cc:(sd_l?16'h56d7:16'h428a);
 end
 reg [9:0] address;reg [3:0] column,font_y;reg [1:0] tone,context;
 reg text_on,override_on;reg [6:0] override_code;reg [7:0] char_index;
 reg [6:0] text_rom[0:1023];
 reg [31:0] font_rom[0:2047];
 initial begin
 `include "text_rom_init.vh"
 `include "font_rom_init.vh"
 end
 always @* begin
  address=0;column=0;font_y=0;tone=0;context=0;text_on=0;override_on=0;override_code=0;char_index=0;
  case(1'b1) // synthesis parallel_case
  (1'b1) && x>=80 && x<144 && y>=24 && y<56:begin
   text_on=1;address=0+((x-11'd80) >> 4);column=(((x-11'd80) >> 1) & 11'd7);font_y=(((y-10'd24) >> 1) & 10'd15);tone=2'd0;context=2'd0;char_index=((x-11'd80) >> 4);
  end
  (1'b1) && x>=168 && x<232 && y>=32 && y<48:begin
   text_on=1;address=4+((x-11'd168) >> 4);column=(((x-11'd168) >> 0) & 11'd15);font_y=(((y-10'd32) >> 0) & 10'd15);tone=2'd1;context=2'd0;char_index=((x-11'd168) >> 4);
  end
  (1'b1) && x>=272 && x<392 && y>=32 && y<48:begin
   text_on=1;address=8+((x-11'd272) >> 3);column=(((x-11'd272) >> 0) & 11'd7);font_y=(((y-10'd32) >> 0) & 10'd15);tone=2'd1;context=2'd0;char_index=((x-11'd272) >> 3);
  end
  (1'b1) && x>=944 && x<992 && y>=32 && y<48:begin
   text_on=1;address=23+((x-11'd944) >> 3);column=(((x-11'd944) >> 0) & 11'd7);font_y=(((y-10'd32) >> 0) & 10'd15);tone=2'd1;context=2'd0;char_index=((x-11'd944) >> 3);
  end
  (1'b1) && x>=1008 && x<1072 && y>=32 && y<48:begin
   text_on=1;address=29+((x-11'd1008) >> 3);column=(((x-11'd1008) >> 0) & 11'd7);font_y=(((y-10'd32) >> 0) & 10'd15);tone=2'd0;context=2'd0;char_index=((x-11'd1008) >> 3);
   override_on=1;
   case(char_index)
    0:override_code=16+hours[7:4];1:override_code=16+hours[3:0];2:override_code=26;
    3:override_code=16+minutes[7:4];4:override_code=16+minutes[3:0];5:override_code=26;
    6:override_code=16+seconds[7:4];7:override_code=16+seconds[3:0];default:override_code=0;endcase
  end
  (1'b1) && x>=1120 && x<1160 && y>=32 && y<48:begin
   text_on=1;address=(sd_l ? 10'd37 : 10'd42)+((x-11'd1120) >> 3);column=(((x-11'd1120) >> 0) & 11'd7);font_y=(((y-10'd32) >> 0) & 10'd15);tone=2'd2;context=2'd0;char_index=((x-11'd1120) >> 3);
  end
  (1'b1) && x>=1040 && x<1128 && y>=112 && y<128:begin
   text_on=1;address=47+((x-11'd1040) >> 3);column=(((x-11'd1040) >> 0) & 11'd7);font_y=(((y-10'd112) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1040) >> 3);
  end
  (1'b1) && x>=1040 && x<1072 && y>=140 && y<172:begin
   text_on=1;address=58+((x-11'd1040) >> 4);column=(((x-11'd1040) >> 1) & 11'd7);font_y=(((y-10'd140) >> 1) & 10'd15);tone=2'd0;context=2'd1;char_index=((x-11'd1040) >> 4);
   override_on=1;
   override_code=(char_index==0)?7'd16:7'd17+index_l;
  end
  (1'b1) && x>=1096 && x<1128 && y>=152 && y<168:begin
   text_on=1;address=60+((x-11'd1096) >> 3);column=(((x-11'd1096) >> 0) & 11'd7);font_y=(((y-10'd152) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1096) >> 3);
   override_on=1;
   case(char_index)0:override_code=15;1:override_code=0;2:override_code=16;3:override_code=16+count_l;default:override_code=0;endcase
  end
  (!busy_l) && x>=1040 && x<1104 && y>=192 && y<208:begin
   text_on=1;address=64+((x-11'd1040) >> 4);column=(((x-11'd1040) >> 0) & 11'd15);font_y=(((y-10'd192) >> 0) & 10'd15);tone=2'd0;context=2'd1;char_index=((x-11'd1040) >> 4);
  end
  (busy_l) && x>=1040 && x<1088 && y>=192 && y<208:begin
   text_on=1;address=68+((x-11'd1040) >> 4);column=(((x-11'd1040) >> 0) & 11'd15);font_y=(((y-10'd192) >> 0) & 10'd15);tone=2'd3;context=2'd1;char_index=((x-11'd1040) >> 4);
  end
  (1'b1) && x>=1040 && x<1128 && y>=224 && y<240:begin
   text_on=1;address=71+((x-11'd1040) >> 3);column=(((x-11'd1040) >> 0) & 11'd7);font_y=(((y-10'd224) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1040) >> 3);
   override_on=1;
   case(char_index)0:override_code=16+width_bcd[15:12];1:override_code=16+width_bcd[11:8];2:override_code=16+width_bcd[7:4];3:override_code=16+width_bcd[3:0];7:override_code=16+height_bcd[15:12];8:override_code=16+height_bcd[11:8];9:override_code=16+height_bcd[7:4];10:override_code=16+height_bcd[3:0];5:override_code=56;default:override_code=0;endcase
  end
  (1'b1) && x>=1040 && x<1200 && y>=248 && y<264:begin
   text_on=1;address=(cover_l ? 10'd402 : 10'd422)+((x-11'd1040) >> 3);column=(((x-11'd1040) >> 0) & 11'd7);font_y=(((y-10'd248) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1040) >> 3);
  end
  (1'b1) && x>=1040 && x<1104 && y>=296 && y<312:begin
   text_on=1;address=101+((x-11'd1040) >> 3);column=(((x-11'd1040) >> 0) & 11'd7);font_y=(((y-10'd296) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1040) >> 3);
  end
  (1'b1) && x>=1040 && x<1104 && y>=320 && y<336:begin
   text_on=1;address=(auto_l ? 10'd109 : 10'd113)+((x-11'd1040) >> 4);column=(((x-11'd1040) >> 0) & 11'd15);font_y=(((y-10'd320) >> 0) & 10'd15);tone=2'd2;context=2'd1;char_index=((x-11'd1040) >> 4);
  end
  (1'b1) && x>=1120 && x<1152 && y>=324 && y<340:begin
   text_on=1;address=(auto_l ? 10'd117 : 10'd121)+((x-11'd1120) >> 3);column=(((x-11'd1120) >> 0) & 11'd7);font_y=(((y-10'd324) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1120) >> 3);
  end
  (1'b1) && x>=1040 && x<1120 && y>=384 && y<400:begin
   text_on=1;address=125+((x-11'd1040) >> 3);column=(((x-11'd1040) >> 0) & 11'd7);font_y=(((y-10'd384) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1040) >> 3);
  end
  (1'b1) && x>=1040 && x<1104 && y>=408 && y<440:begin
   text_on=1;address=135+((x-11'd1040) >> 4);column=(((x-11'd1040) >> 1) & 11'd7);font_y=(((y-10'd408) >> 1) & 10'd15);tone=2'd2;context=2'd1;char_index=((x-11'd1040) >> 4);
   override_on=1;
   case(char_index)0:override_code=(percentage[11:8]==0)?0:16+percentage[11:8];1:override_code=16+percentage[7:4];2:override_code=16+percentage[3:0];3:override_code=5;default:override_code=0;endcase
  end
  (1'b1) && x>=1040 && x<1128 && y>=480 && y<496:begin
   text_on=1;address=139+((x-11'd1040) >> 3);column=(((x-11'd1040) >> 0) & 11'd7);font_y=(((y-10'd480) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1040) >> 3);
  end
  (1'b1) && x>=1040 && x<1160 && y>=576 && y<592:begin
   text_on=1;address=150+((x-11'd1040) >> 3);column=(((x-11'd1040) >> 0) & 11'd7);font_y=(((y-10'd576) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1040) >> 3);
  end
  (1'b1) && x>=1040 && x<1168 && y>=608 && y<624:begin
   text_on=1;address=165+((x-11'd1040) >> 3);column=(((x-11'd1040) >> 0) & 11'd7);font_y=(((y-10'd608) >> 0) & 10'd15);tone=2'd1;context=2'd1;char_index=((x-11'd1040) >> 3);
  end
  (1'b1) && x>=48 && x<80 && y>=664 && y<680:begin
   text_on=1;address=181+((x-11'd48) >> 3);column=(((x-11'd48) >> 0) & 11'd7);font_y=(((y-10'd664) >> 0) & 10'd15);tone=2'd2;context=2'd2;char_index=((x-11'd48) >> 3);
  end
  (!valid_l) && x>=408 && x<616 && y>=304 && y<336:begin
   text_on=1;address=185+((x-11'd408) >> 4);column=(((x-11'd408) >> 1) & 11'd7);font_y=(((y-10'd304) >> 1) & 10'd15);tone=2'd0;context=2'd0;char_index=((x-11'd408) >> 4);
  end
  (!valid_l && !sd_l && error_l==0) && x>=436 && x<588 && y>=352 && y<368:begin
   text_on=1;address=198+((x-11'd436) >> 3);column=(((x-11'd436) >> 0) & 11'd7);font_y=(((y-10'd352) >> 0) & 10'd15);tone=2'd1;context=2'd0;char_index=((x-11'd436) >> 3);
  end
  (!valid_l && sd_l && !scan_l && error_l==0) && x>=456 && x<568 && y>=352 && y<368:begin
   text_on=1;address=218+((x-11'd456) >> 3);column=(((x-11'd456) >> 0) & 11'd7);font_y=(((y-10'd352) >> 0) & 10'd15);tone=2'd1;context=2'd0;char_index=((x-11'd456) >> 3);
  end
  (!valid_l && sd_l && scan_l && busy_l && error_l==0) && x>=460 && x<564 && y>=352 && y<368:begin
   text_on=1;address=232+((x-11'd460) >> 3);column=(((x-11'd460) >> 0) & 11'd7);font_y=(((y-10'd352) >> 0) & 10'd15);tone=2'd1;context=2'd0;char_index=((x-11'd460) >> 3);
  end
  (!valid_l && scan_l && !busy_l && error_l==0) && x>=448 && x<576 && y>=352 && y<368:begin
   text_on=1;address=245+((x-11'd448) >> 3);column=(((x-11'd448) >> 0) & 11'd7);font_y=(((y-10'd352) >> 0) & 10'd15);tone=2'd3;context=2'd0;char_index=((x-11'd448) >> 3);
  end
  (!valid_l && error_l!=0) && x>=460 && x<564 && y>=352 && y<368:begin
   text_on=1;address=261+((x-11'd460) >> 3);column=(((x-11'd460) >> 0) & 11'd7);font_y=(((y-10'd352) >> 0) & 10'd15);tone=2'd3;context=2'd0;char_index=((x-11'd460) >> 3);
   override_on=1;
   override_on=(char_index==12);override_code=(error_l<10)?7'd16+error_l:7'd23+error_l;
  end
  x>=128 && x<1232 && y>=664 && y<680:begin
   text_on=1;address=10'd274+ticker_position[9:3];column={1'b0,ticker_position[2:0]};font_y=y-10'd664;tone=1;context=2;
  end

   default:begin end
  endcase
 end
 reg [9:0] address0;reg [3:0] col0,row0,col1,row1,col2;
 reg on0,on1,on2,over0;reg [6:0] over_code0,code1;
 reg [1:0] tone0,tone1,tone2,context0,context1,context2;
 reg [31:0] font_row2;
 reg [15:0] bg0,bg1,bg2;
 reg [10:0] x0,x1,x2;reg [9:0] y0,y1,y2;
 wire [1:0] alpha=(font_row2 >> {col2,1'b0}) & 2'b11;
 function [15:0] ink;
  input [5:0] key;
  begin case(key)
   6'd1:ink=16'h530d;
   6'd2:ink=16'ha555;
   6'd3:ink=16'hefbe;
   6'd5:ink=16'h322a;
   6'd6:ink=16'h63b0;
   6'd7:ink=16'h8d36;
   6'd9:ink=16'h22ca;
   6'd10:ink=16'h3cf0;
   6'd11:ink=16'h5717;
   6'd13:ink=16'h5a66;
   6'd14:ink=16'ha409;
   6'd15:ink=16'hf5cc;
   6'd17:ink=16'h5b4d;
   6'd18:ink=16'ha576;
   6'd19:ink=16'hefbe;
   6'd21:ink=16'h3a6b;
   6'd22:ink=16'h63d0;
   6'd23:ink=16'h8d36;
   6'd25:ink=16'h230b;
   6'd26:ink=16'h3d11;
   6'd27:ink=16'h5717;
   6'd29:ink=16'h5aa7;
   6'd30:ink=16'hac29;
   6'd31:ink=16'hf5cc;
   6'd33:ink=16'h530d;
   6'd34:ink=16'ha575;
   6'd35:ink=16'hefbe;
   6'd37:ink=16'h324a;
   6'd38:ink=16'h63d0;
   6'd39:ink=16'h8d36;
   6'd41:ink=16'h22ea;
   6'd42:ink=16'h3d11;
   6'd43:ink=16'h5717;
   6'd45:ink=16'h5a87;
   6'd46:ink=16'ha429;
   6'd47:ink=16'hf5cc;
   default:ink=16'hffff;
  endcase end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   address0<=0;col0<=0;row0<=0;col1<=0;row1<=0;col2<=0;on0<=0;on1<=0;on2<=0;over0<=0;over_code0<=0;code1<=0;
   tone0<=0;tone1<=0;tone2<=0;context0<=0;context1<=0;context2<=0;font_row2<=0;
   bg0<=0;bg1<=0;bg2<=0;x0<=0;x1<=0;x2<=0;out_x<=0;y0<=0;y1<=0;y2<=0;out_y<=0;rgb<=0;
  end else begin
   address0<=address;col0<=column;row0<=font_y;on0<=text_on;over0<=override_on;over_code0<=override_code;
   tone0<=tone;context0<=context;bg0<=base_rgb;x0<=x;y0<=y;
   code1<=over0?over_code0:text_rom[address0];col1<=col0;row1<=row0;on1<=on0;tone1<=tone0;context1<=context0;bg1<=bg0;x1<=x0;y1<=y0;
   font_row2<=font_rom[{code1,row1}];col2<=col1;on2<=on1;tone2<=tone1;context2<=context1;bg2<=bg1;x2<=x1;y2<=y1;
   rgb<=(on2 && alpha!=0)?ink({context2,tone2,alpha}):bg2;out_x<=x2;out_y<=y2;
  end
 end
endmodule
