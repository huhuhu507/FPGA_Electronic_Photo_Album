`timescale 1ns/1ps
module tb_spi_speed;
 reg clk=0,rst=0,start=0,miso=1;reg [7:0] tx=0,div=250,reply=0,observed=0;
 wire sclk,mosi,busy,done;wire [7:0] rx;
 integer bits=0,checks=0;time previous_edge=0;
 always #10 clk=~clk;
 spi_byte spi(clk,rst,start,tx,div,sclk,mosi,miso,busy,done,rx);
 always @(posedge sclk)begin
  observed={observed[6:0],mosi};bits=bits+1;
  if(previous_edge!=0&&($time-previous_edge)!=40*div)$fatal(1,"SPI period %0t expected%0d",$time-previous_edge,40*div);
  previous_edge=$time;
 end
 always @(negedge sclk)if(bits<8)miso=reply[7-bits];
 task transfer;input [7:0] divider,send_data,response;begin
  @(negedge clk);div=divider;tx=send_data;reply=response;bits=0;observed=0;previous_edge=0;miso=response[7];start=1;
  @(negedge clk);start=0;wait(done);#1;
  if(bits!=8||rx!==response||observed!==send_data)$fatal(1,"SPI bits%0d rx%h exp%h tx%h",bits,rx,response,observed);
  checks=checks+1;repeat(3)@(negedge clk);
 end endtask
 initial begin
  #43;rst=1;transfer(250,8'hff,8'h01);transfer(2,8'ha5,8'h5a);transfer(2,8'h00,8'hff);transfer(2,8'hc3,8'h69);transfer(1,8'ha5,8'h5a);transfer(1,8'hc3,8'h69);transfer(5,8'h39,8'h81);
  $display("PASS SPI: 100kHz init / 25, 12.5, 5MHz read clocks, MSB first, seven MOSI/MISO vectors");$finish;
 end
 initial begin #1000000;$fatal(1,"SPI timeout");end
endmodule
