`timescale 1ns/1ps
// SPI pin-level SDHC model: real commands, tokens, payload and CRC16.
module tb_sd_crc #(parameter READ_SPEED=1);
 reg clk=0,rst=0,req=0;reg [31:0] sector=32'h12345678;
 always #10 clk=~clk;
 wire sclk,mosi,cs,ready,valid,done;wire [7:0] data;wire [3:0] error;
 reg miso=1;
 sd_ctrl #(.READ_DIV(READ_SPEED),.POWER_DELAY(10),.INIT_DIV(2)) dut(clk,rst,sclk,mosi,cs,miso,ready,req,sector,data,valid,done,error,);
 reg [7:0] queue[0:1023];integer head=0,tail=0,bitn=0,cmdn=0,reads=0;
 reg [7:0] rx=0,tx=8'hff,command;reg [31:0] argument=0;
 integer j;reg [15:0] checksum;reg [7:0] byte_value;
 integer delivered=0,completed=0,corrupt_reads=2,phase=0;
 time begin_time;
 function [7:0] pattern;input integer n;begin pattern=(n*37+(n>>3)+8'h78)&255;end endfunction
 function [15:0] crc;input [15:0] c0;input [7:0] b;
  reg [15:0] c;integer k;begin
   c=c0;for(k=7;k>=0;k=k-1)begin
    if(c[15]^b[k])c=(c<<1)^16'h1021;else c=c<<1;
   end crc=c;
  end
 endfunction
 task push;input [7:0] b;begin queue[tail]=b;tail=tail+1;end endtask
 always @(posedge cs)begin head=0;tail=0;bitn=0;cmdn=0;tx=8'hff;miso=1;end
 always @(posedge sclk)if(!cs)begin
  rx={rx[6:0],mosi};bitn=bitn+1;
  if(bitn==8)begin
   bitn=0;
   if(cmdn==0)begin
    if(rx[7:6]==2'b01)begin command=rx;cmdn=1;argument=0;end
   end else if(cmdn<5)begin argument={argument[23:0],rx};cmdn=cmdn+1;end
   else begin
    cmdn=0;head=0;tail=0;
    case(command)
     8'h40:push(1);
     8'h48:begin push(1);push(0);push(0);push(1);push(8'haa);end
     8'h77:push(1);
     8'h69:push(0);
     8'h7a:begin push(0);push(8'hc0);push(0);push(0);push(0);end
     8'h51:begin
      if(argument!==32'h12345678)$fatal(1,"wrong LBA %h",argument);
      reads=reads+1;checksum=0;push(0);push(8'hff);push(8'hfe);
      for(j=0;j<512;j=j+1)begin
       byte_value=pattern(j);checksum=crc(checksum,byte_value);
       push((reads<=corrupt_reads && j==257)?byte_value^8'h04:byte_value);
      end
      push(checksum[15:8]);push(checksum[7:0]);
     end
     default:$fatal(1,"unexpected command %h",command);
    endcase
   end
   if(head<tail)begin tx=queue[head];head=head+1;end else tx=8'hff;
  end
 end
 always @(negedge sclk)begin if(cs)miso=1;else miso<=#24 tx[7-bitn];end
 always @(negedge clk)if(rst)begin
  if(valid)begin
   if(phase==0 && reads!=3 && !$test$plusargs("CLEAN"))$fatal(1,"corrupt sector leaked before successful retry");
   if(phase==2)$fatal(1,"corrupt final sector leaked");
   if(data!==pattern(delivered%512))$fatal(1,"sector data %0d %h",delivered,data);
   delivered=delivered+1;
  end
  if(done)completed=completed+1;
 end
 task read_sector;begin
  @(negedge clk);req=1;@(negedge clk);req=0;
 end endtask
 initial begin
  if(crc(16'hffff,8'hff)===16'hxxxx)$fatal;
  checksum=0;for(j=0;j<512;j=j+1)checksum=crc(checksum,8'hff);
  if(checksum!=16'h7fa1)$fatal(1,"reference CRC check vector");
  if($test$plusargs("CLEAN"))corrupt_reads=0;
  #43;rst=1;wait(ready);begin_time=$time;read_sector();wait(done);#40;
  if($test$plusargs("CLEAN"))begin
   if(error||delivered!=512||reads!=1||dut.data_div!=READ_SPEED)$fatal(1,"clean read retried; late sampling failed");
   $display("PASS SD CLEAN: divider=%0d, 24ns pin delay, 512 exact bytes, CRC valid, no retry, sector time %0d ns",READ_SPEED,$time-begin_time);$finish;
  end
  if(error||delivered!=512||reads!=3||dut.data_div!=5||completed!=1)$fatal(1,"fallback result error%0d n%0d reads%0d div%0d",error,delivered,reads,dut.data_div);
  phase=1;read_sector();wait(done);#40;
  if(error||delivered!=1024||reads!=4||completed!=2)$fatal(1,"second sector/fallback retention");
  phase=2;corrupt_reads=100;read_sector();wait(error);#100;
  if(error!=10||delivered!=1024||completed!=2||reads!=7)$fatal(1,"fatal CRC gating");
  $display("PASS SD CRC: pin-level SDHC init/CMD17, 24ns MISO delay, CRC16 known vector, corrupt-sector withholding, 25->12.5->5MHz retries, retained fallback, 3-attempt error, 1024 exact bytes");$finish;
 end
 initial begin #20000000;$fatal(1,"SD timeout state%0d cmd%0d read%0d n%0d crc%h",dut.state,command,reads,delivered,dut.crc16);end
endmodule

module tb_sd_crc_slow;tb_sd_crc #(.READ_SPEED(2)) bench();endmodule
