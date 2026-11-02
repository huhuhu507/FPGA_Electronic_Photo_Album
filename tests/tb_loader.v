`timescale 1ns/1ps
module tb_loader;
 reg clk=0,rst_n=0,sd_ready=0,load_req=0;reg [2:0] load_index=0;
 always #10 clk=~clk;
 wire rd_req;wire[31:0] rd_sector;reg[7:0] rd_data=0;reg rd_valid=0,rd_done=0;
 wire wr_req;wire[20:0] wr_addr;wire[31:0] wr_data;reg wr_ack=0;
 wire scan_done,busy,load_done,topdown,frame_start;wire[11:0] img_h,img_w;wire[3:0] count,error;
 bmp_sdram_loader dut(clk,rst_n,sd_ready,rd_req,rd_sector,rd_data,rd_valid,rd_done,load_req,load_index,wr_req,wr_addr,wr_data,wr_ack,21'd524288,scan_done,busy,load_done,count,topdown,frame_start,img_h,img_w,error,,,,,,,);
 reg[7:0] disk[0:227327];reg[31:0] expected0[0:10239],expected1[0:143];
 integer sending=0,index=0,lba=0,phase=0,wstate=0,delay_count=0,words=0,current=0,requests=0;
 always @(posedge clk)begin
  rd_valid<=0;rd_done<=0;
  if(rd_req)begin if(sending)$fatal(1,"overlapping sector requests");sending<=1;index<=0;lba<=rd_sector;phase<=0;requests<=requests+1;end
  else if(sending)begin
   phase<=phase+1;
   if(phase==1)begin
    phase<=0;
    if(index<512)begin rd_data<=disk[lba*512+index];rd_valid<=1;index<=index+1;end
    else begin rd_done<=1;sending<=0;end
   end
  end
  case(wstate)
   0:if(wr_req)begin wstate<=1;delay_count<=0;end
   1:if(delay_count==((words%7==0)?80:3))begin
     if(wr_addr!==524288+words)$fatal(1,"write address %0d expected %0d",wr_addr,524288+words);
     if(current==0 && wr_data!==expected0[words])$fatal(1,"1280 pixel word %0d got %h expected %h",words,wr_data,expected0[words]);
     if(current==1 && wr_data!==expected1[words])$fatal(1,"18-wide pixel word %0d got %h expected %h",words,wr_data,expected1[words]);
     words<=words+1;wr_ack<=1;wstate<=2;
    end else delay_count<=delay_count+1;
   2:if(!wr_req)begin wr_ack<=0;wstate<=0;end
  endcase
 end
 task request;input[2:0] n;begin @(negedge clk);load_index=n;load_req=1;@(negedge clk);load_req=0;end endtask
 initial begin
  if($test$plusargs("MBR"))$readmemh("tests/disk_mbr.hex",disk);else $readmemh("tests/disk.hex",disk);
  $readmemh("tests/expected0.hex",expected0);$readmemh("tests/expected1.hex",expected1);
  #43;rst_n=1;sd_ready=1;
  wait(load_done);#1;
  if(error!=0 || count!=3 || words!=10240 || img_w!=1280 || img_h!=16 || topdown)$fatal(1,"first load count=%0d words=%0d error=%0d",count,words,error);
  @(negedge clk);current=1;words=0;request(1);wait(load_done);#1;
  if(error!=0 || words!=144 || img_w!=18 || img_h!=16 || !topdown)$fatal(1,"second load words=%0d err=%0d",words,error);
  @(negedge clk);current=2;words=0;request(2);wait(error!=0);wait(!busy);#1;
  if(error!=2 || words!=0)$fatal(1,"invalid BMP handling err=%0d words=%0d",error,words);
  $display("PASS FAT32/BMP: %0d reads, fragmented file/root chains, 1280 width, 18-wide row padding, 54/2048-byte offsets, top-down, backpressure, high frame address, bad BMP",requests);$finish;
 end
 initial begin #50000000;$fatal(1,"loader timeout state %0d error %0d words %0d",dut.state,error,words);end
endmodule
