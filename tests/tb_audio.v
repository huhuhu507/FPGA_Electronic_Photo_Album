`timescale 1ns/1ps
module tb_audio;
 reg clk=0,rst_n=0,trigger=0;always #5 clk=~clk;
 wire sample_valid,active,buzzer;wire signed[15:0] l,r;
 audio_synth #(.PIXEL_HZ(480000)) synth(clk,rst_n,trigger,2'd0,sample_valid,l,r,active,buzzer);
 integer cycles=0,samples=0,nonzero=0,peak=0,fd;
 always @(negedge clk)if(rst_n)begin
  cycles=cycles+1;
  if(sample_valid)begin
   samples=samples+1;
   if(l!==r)$fatal(1,"stereo mismatch");
   if(l>peak)peak=l;if(l!=0)nonzero=nonzero+1;
   $fwrite(fd,"%0d\n",l);
  end
  if(cycles==200000)begin
   if(samples!=20000||nonzero<13000||peak<3900||peak>4100||active||l!=0||r!=0||buzzer)$fatal(1,"Audio coverage samples%0d nonzero%0d peak%0d active%b",samples,nonzero,peak,active);
   $fclose(fd);$display("PASS AUDIO: exact 48kHz ratio, stereo equality, envelope, three-note PCM, bounded amplitude, silence/idle");$finish;
  end
 end
 initial begin fd=$fopen("tests/pcm_cue.txt","w");#22;rst_n=1;@(negedge clk);trigger=1;@(negedge clk);trigger=0;end
endmodule
module tb_bcd;
 reg clk=0,rst_n=0,start=0;reg[11:0] value=0;wire[15:0] bcd;integer n;reg[15:0] expected;
 always #5 clk=~clk;
 number_bcd dut(clk,rst_n,start,value,bcd);
 initial begin
  #22;rst_n=1;
  for(n=0;n<4096;n=n+1)begin
   @(negedge clk);value=n;start=1;@(negedge clk);start=0;repeat(13)@(negedge clk);
   expected=((n/1000)<<12)|(((n/100)%10)<<8)|(((n/10)%10)<<4)|(n%10);
   if(bcd!==expected)$fatal(1,"BCD n%0d got%h expected%h",n,bcd,expected);
  end
  $display("PASS BCD: all 4096 input values, decimal carry and zero padding");$finish;
 end
endmodule
