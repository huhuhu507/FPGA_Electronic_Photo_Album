`timescale 1ns/1ps
// Whole transactions are serialized. Video lines have priority over audio refill.
module sdram_read_arbiter(
 input wire clk,rst_n,
 input wire video_req,input wire [20:0] video_base,input wire [9:0] video_words,
 output wire [31:0] video_data,output wire video_we,video_done,
 input wire audio_req,input wire [20:0] audio_base,input wire [9:0] audio_words,
 output wire [31:0] audio_data,output wire audio_we,audio_done,
 output reg mem_req,output reg [20:0] mem_base,output reg [9:0] mem_words,
 input wire [31:0] mem_data,input wire mem_we,mem_done
);
 reg [1:0] state;reg owner_audio;
 assign video_data=mem_data;assign audio_data=mem_data;
 assign video_we=state==1&&!owner_audio&&mem_we;
 assign video_done=state==1&&!owner_audio&&mem_done;
 assign audio_we=state==1&&owner_audio&&mem_we;
 assign audio_done=state==1&&owner_audio&&mem_done;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;owner_audio<=0;mem_req<=0;mem_base<=0;mem_words<=0;end
  else case(state)
   0:if(video_req)begin mem_base<=video_base;mem_words<=video_words;owner_audio<=0;mem_req<=1;state<=1;end
     else if(audio_req)begin mem_base<=audio_base;mem_words<=audio_words;owner_audio<=1;mem_req<=1;state<=1;end
   1:if(mem_done)begin mem_req<=0;state<=2;end
   2:if(!mem_done&&!(owner_audio?audio_req:video_req))state<=3;
   3:state<=0;
  endcase
 end
endmodule
