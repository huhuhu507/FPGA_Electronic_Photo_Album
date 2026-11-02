`timescale 1ns/1ps
// A complete LAV1 clip is loaded to SDRAM before enabling this player.
// RGB565 frames precede 48 kHz signed 16-bit stereo PCM, one sample/32-bit word.
// Audio consumption is the timeline. Display changes only at vertical blanking.
module motion_player #(parameter PIXEL_HZ=74250000)(
 input wire pclk,mclk,prst_n,mrst_n,enable,play,vblank,
 input wire [15:0] frame_count,samples_per_frame,
 input wire [20:0] frame_words,audio_base,
 input wire [31:0] audio_samples,
 output reg [20:0] frame_base,output reg frame_epoch,
 output reg [15:0] frame_index,output reg [9:0] progress,
 output reg pcm_valid,output reg signed [15:0] pcm_l,pcm_r,
 output wire playing,output reg [15:0] underflows,
 output reg audio_req,output reg [20:0] audio_read_base,
 output reg [9:0] audio_read_words,
 input wire [31:0] audio_data,input wire audio_we,audio_done,
 output reg clip_done_toggle
);
 (* ASYNC_REG="TRUE" *) reg [1:0] active_m;
 always @(posedge mclk or negedge mrst_n)begin
  if(!mrst_n)active_m<=0;else active_m<={active_m[0],enable};
 end
 wire fifo_wr_rst=mrst_n&&active_m[1];
 wire fifo_rd_rst=prst_n&&enable;
 wire fifo_full,fifo_empty,fifo_valid;wire [10:0] fifo_level;
 wire [31:0] fifo_data;
 reg have_sample,read_pending;reg [31:0] sample_hold;
 wire fifo_pop=enable&&!have_sample&&!read_pending&&!fifo_empty;
 wire fifo_push=active_m[1]&&audio_we;
 async_audio_fifo fifo(mclk,fifo_wr_rst,fifo_push,audio_data,fifo_full,fifo_level,
                       pclk,fifo_rd_rst,fifo_pop,fifo_data,fifo_valid,fifo_empty);
 reg [1:0] read_state;reg [31:0] read_position;
 wire [31:0] remaining=audio_samples-read_position;
 always @(posedge mclk or negedge mrst_n)begin
  if(!mrst_n)begin audio_req<=0;audio_read_base<=0;audio_read_words<=0;read_state<=0;read_position<=0;end
  else if(!active_m[1])begin audio_req<=0;read_state<=0;read_position<=0;end
  else case(read_state)
   0:if(fifo_level<=11'd512&&audio_samples!=0)begin
    audio_read_base<=audio_base+read_position[20:0];
    audio_read_words<=(remaining>=256)?10'd256:remaining[9:0];
    audio_req<=1;read_state<=1;
   end
   1:if(audio_done)begin audio_req<=0;read_state<=2;end
   2:begin
    if(read_position+audio_read_words>=audio_samples)read_position<=0;
    else read_position<=read_position+audio_read_words;
    read_state<=0;
   end
  endcase
 end
 reg [26:0] rate_acc;
 wire [27:0] rate_sum={1'b0,rate_acc}+28'd48000;
 wire sample_tick=rate_sum>=PIXEL_HZ;
 reg started;
 reg [15:0] desired_index,sample_in_frame;
 reg [20:0] desired_base;
 reg [31:0] sample_position,progress_acc;
 wire [32:0] next_progress={1'b0,progress_acc}+33'd610;
 assign playing=enable&&play&&started;
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin
   frame_base<=0;frame_epoch<=0;frame_index<=0;progress<=0;clip_done_toggle<=0;
   pcm_valid<=0;pcm_l<=0;pcm_r<=0;rate_acc<=0;have_sample<=0;read_pending<=0;sample_hold<=0;
   started<=0;desired_index<=0;desired_base<=0;sample_in_frame<=0;sample_position<=0;progress_acc<=0;underflows<=0;
  end else begin
   pcm_valid<=0;
   if(sample_tick)begin rate_acc<=rate_sum-PIXEL_HZ;pcm_valid<=1;pcm_l<=0;pcm_r<=0;end
   else rate_acc<=rate_sum[26:0];
   if(!enable)begin
    frame_base<=0;frame_epoch<=0;frame_index<=0;progress<=0;have_sample<=0;read_pending<=0;
    started<=0;desired_index<=0;desired_base<=0;sample_in_frame<=0;sample_position<=0;progress_acc<=0;
   end else begin
    if(fifo_pop)read_pending<=1;
    if(fifo_valid)begin sample_hold<=fifo_data;have_sample<=1;read_pending<=0;end
    if(vblank)begin
     if(!started&&have_sample)started<=1;
     if(started&&desired_index!=frame_index)begin
      frame_base<=desired_base;frame_index<=desired_index;frame_epoch<=~frame_epoch;
     end
    end
    if(sample_tick&&play&&started)begin
     if(have_sample)begin
      pcm_l<=sample_hold[15:0];pcm_r<=sample_hold[31:16];have_sample<=0;
      if(sample_in_frame+1'b1==samples_per_frame)begin
       sample_in_frame<=0;
       if(desired_index+1'b1==frame_count)begin desired_index<=0;desired_base<=0;end
       else begin desired_index<=desired_index+1'b1;desired_base<=desired_base+frame_words;end
      end else sample_in_frame<=sample_in_frame+1'b1;
      if(sample_position+1'b1==audio_samples)begin
       sample_position<=0;progress_acc<=0;progress<=0;clip_done_toggle<=~clip_done_toggle;
      end
      else begin
       sample_position<=sample_position+1'b1;
       if(next_progress>=audio_samples)begin progress_acc<=next_progress-audio_samples;progress<=progress+1'b1;end
       else progress_acc<=next_progress[31:0];
      end
     end else if(underflows!=16'hffff)underflows<=underflows+1'b1;
    end
   end
  end
 end
endmodule
