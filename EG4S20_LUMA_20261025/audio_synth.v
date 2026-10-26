`timescale 1ns/1ps
// 48kHz stereo PCM cue, generated entirely in the FPGA. The scope observes
// exactly these samples. A three-note triangle chime accompanies a frame commit.
module audio_synth #(parameter PIXEL_HZ=74250000)(
 input wire clk,rst_n,trigger,input wire [1:0] variation,
 output reg sample_valid,output reg signed [15:0] pcm_l,pcm_r,
 output wire active,output wire buzzer_pwm);
 reg [26:0] rate_acc;
 wire [27:0] rate_sum={1'b0,rate_acc}+28'd48000;
 reg [31:0] phase;reg [13:0] duration;reg [1:0] note;
 reg playing;reg [1:0] theme;
 reg [31:0] increment;
 always @* begin
  case(note)
   0:increment=(theme[0]?32'd52613349:32'd46815122); // 588 / 523 Hz
   1:increment=32'd58966320; // 659 Hz
   2:increment=32'd70151132; // 784 Hz
   default:increment=32'd93630246;
  endcase
 end
 wire signed [16:0] triangle=phase[31]?17'sd32767-$signed({1'b0,phase[30:15]}):$signed({1'b0,phase[30:15]})-17'sd32768;
 wire [7:0] envelope=(duration<128)?duration[7:0]:(duration>13'd4480)?(13'd4608-duration):8'd128;
 wire signed [25:0] shaped=triangle*$signed({1'b0,envelope});
 assign active=playing;
 assign buzzer_pwm=playing && phase[31];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rate_acc<=0;sample_valid<=0;pcm_l<=0;pcm_r<=0;phase<=0;duration<=0;note<=0;playing<=0;theme<=0;end
  else begin
   sample_valid<=0;
   if(trigger)begin playing<=1;duration<=0;note<=0;phase<=0;theme<=variation;end
   if(rate_sum>=PIXEL_HZ)begin
    rate_acc<=rate_sum-PIXEL_HZ;sample_valid<=1;
    if(playing)begin
     phase<=phase+increment;
     pcm_l<=shaped>>>10;pcm_r<=shaped>>>10;
     if(duration==4607)begin duration<=0;phase<=0;if(note==2)playing<=0;else note<=note+1'b1;end
     else duration<=duration+1'b1;
    end else begin pcm_l<=0;pcm_r<=0;end
   end else rate_acc<=rate_sum[26:0];
  end
 end
endmodule
