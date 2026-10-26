`timescale 1ns/1ps
// Minimal 720p HDMI transmitter, RGB + stereo 16-bit LPCM/48kHz.
// Packet layout, TERC4 and streaming BCH are adapted from hdl-util/hdmi,
// Sameer Puri, MIT license. See third_party/hdl-util-hdmi/LICENSE-MIT.
// This implementation uses Verilog-2001 and one LPCM sample per packet.
module hdmi_tx #(parameter PIXEL_HZ=74250000,parameter CTS=74250)(
 input wire clk,rst_n,input wire [10:0] x,input wire [9:0] y,
 input wire [23:0] rgb,input wire pcm_valid,input wire [15:0] pcm_l,pcm_r,
 output wire [9:0] code_r,code_g,code_b,output reg audio_overflow);
 wire hsync=(x>=1390 && x<1430);
 wire vsync=(y==724)?(x>=1390):(y==729)?(x<1390):(y>=725&&y<729);
 wire video=(x<1280&&y<720);
 wire next_video=(y<719||y==749);
 wire video_pre=(x>=1640&&x<1648&&next_video);
 wire video_guard=(x>=1648&&next_video);
 wire island_pre=(x>=1284&&x<1292);
 wire island_guard=(x>=1292&&x<1294)||(x>=1422&&x<1424);
 wire island=(x>=1294&&x<1422);
 wire [10:0] packet_position=x-11'd1294;
 wire [4:0] q=packet_position[4:0];
 wire pick=(x==1293||x==1325||x==1357||x==1389);
 wire metadata_avi=(y==0&&x==1293);
 wire metadata_audio=(y==0&&x==1325);
 wire metadata_spd=(y==1&&x==1293);
 wire metadata_acr=(x==1357&&y==0)||(x==1293&&y[4:0]==0&&y!=0);
 reg [31:0] fifo[0:15];reg [3:0] wptr,rptr;reg [4:0] count;
 wire pop=pick&&!metadata_avi&&!metadata_audio&&!metadata_spd&&!metadata_acr&&count!=0;
 wire push=pcm_valid&&(count<16||pop);
 wire [31:0] sample=fifo[rptr];
 reg [7:0] frame_counter;
 localparam [191:0] STATUS_L=192'h0202100004,STATUS_R=192'h0202200004;
 wire csl=STATUS_L[frame_counter],csr=STATUS_R[frame_counter];
 wire parity_l=^{csl,sample[15:0]},parity_r=^{csr,sample[31:16]};
 reg [23:0] header;
 reg [55:0] sub0,sub1,sub2,sub3;
 localparam [19:0] N=20'd6144;
 localparam [19:0] STAMP=CTS;
 wire [55:0] acr_body={N[7:0],N[15:8],{4'd0,N[19:16]},STAMP[7:0],STAMP[15:8],{4'd0,STAMP[19:16]},8'd0};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin wptr<=0;rptr<=0;count<=0;frame_counter<=0;audio_overflow<=0;header<=0;sub0<=0;sub1<=0;sub2<=0;sub3<=0;end
  else begin
   if(push)begin fifo[wptr]<={pcm_r,pcm_l};wptr<=wptr+1'b1;end
   if(pcm_valid&&!push)audio_overflow<=1;
   if(pop)begin rptr<=rptr+1'b1;frame_counter<=(frame_counter==191)?0:frame_counter+1'b1;end
   case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
   if(pick)begin
    header<=0;sub0<=0;sub1<=0;sub2<=0;sub3<=0;
    if(metadata_avi)begin
     // VIC4 720p60, RGB full range, IT content, active format 16:9.
     header<=24'h0d0282;sub0<=56'h000004882810ab;
    end else if(metadata_audio)begin header<=24'h0a0184;sub0<=56'h00000000000170;end
    else if(metadata_spd)begin
     header<=24'h190183;
     sub0<=56'h49474f4c4e41d9;sub1<=56'h20414d554c2043;sub2<=56'h20303253344745;sub3<=56'h00000920202020;
    end else if(metadata_acr)begin header<=24'h000001;sub0<=acr_body;sub1<=acr_body;sub2<=acr_body;sub3<=acr_body;end
    else if(pop)begin
     header<={3'd0,(frame_counter==0),4'd0,8'h01,8'h02};
     sub0<={parity_r,csr,2'b00,parity_l,csl,2'b00,sample[31:16],8'd0,sample[15:0],8'd0};
    end
   end
  end
 end
 function [7:0] ecc;
  input [7:0] crc;input bit_in;
  begin ecc=(crc>>1)^((crc[0]^bit_in)?8'h83:8'h00);end
 endfunction
 reg [7:0] p0,p1,p2,p3,p4;
 wire [5:0] q2={q,1'b0},q2p={q,1'b1};
 wire [63:0] b0={p0,sub0},b1={p1,sub1},b2={p2,sub2},b3={p3,sub3};
 wire [31:0] bh={p4,header};
 wire [3:0] nibble_g={b3[q2],b2[q2],b1[q2],b0[q2]};
 wire [3:0] nibble_r={b3[q2p],b2[q2p],b1[q2p],b0[q2p]};
 wire [3:0] nibble_b={1'b1,bh[q],vsync,hsync};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin p0<=0;p1<=0;p2<=0;p3<=0;p4<=0;end
  else if(!island||q==31)begin p0<=0;p1<=0;p2<=0;p3<=0;p4<=0;end
  else begin
   if(q<28)begin
    p0<=ecc(ecc(p0,sub0[q2]),sub0[q2p]);p1<=ecc(ecc(p1,sub1[q2]),sub1[q2p]);
    p2<=ecc(ecc(p2,sub2[q2]),sub2[q2p]);p3<=ecc(ecc(p3,sub3[q2]),sub3[q2p]);
   end
   if(q<24)p4<=ecc(p4,header[q]);
  end
 end
 function [9:0] terc4;
  input [3:0] n;
  begin case(n)
   0:terc4=10'b1010011100;1:terc4=10'b1001100011;2:terc4=10'b1011100100;3:terc4=10'b1011100010;
   4:terc4=10'b0101110001;5:terc4=10'b0100011110;6:terc4=10'b0110001110;7:terc4=10'b0100111100;
   8:terc4=10'b1011001100;9:terc4=10'b0100111001;10:terc4=10'b0110011100;11:terc4=10'b1011000110;
   12:terc4=10'b1010001110;13:terc4=10'b1001110001;14:terc4=10'b0101100011;15:terc4=10'b1011000011;
  endcase end
 endfunction
 wire [9:0] encoded_r,encoded_g,encoded_b;
 tmds_encoder er(clk,rst_n,rgb[23:16],video,{1'b0,island_pre},encoded_r);
 tmds_encoder eg(clk,rst_n,rgb[15:8],video,{1'b0,(video_pre||island_pre)},encoded_g);
 tmds_encoder eb(clk,rst_n,rgb[7:0],video,{vsync,hsync},encoded_b);
 reg special;reg [9:0] special_r,special_g,special_b;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin special<=0;special_r<=0;special_g<=0;special_b<=0;end
  else begin
   special<=island||island_guard||video_guard;
   if(island_guard)begin special_r<=10'b0100110011;special_g<=10'b0100110011;special_b<=terc4({2'b11,vsync,hsync});end
   else if(island)begin special_r<=terc4(nibble_r);special_g<=terc4(nibble_g);special_b<=terc4(nibble_b);end
   else begin special_r<=10'b1011001100;special_g<=10'b0100110011;special_b<=10'b1011001100;end
  end
 end
 assign code_r=special?special_r:encoded_r;assign code_g=special?special_g:encoded_g;assign code_b=special?special_b:encoded_b;
endmodule
