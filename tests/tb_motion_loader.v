`timescale 1ns/1ps
module tb_motion_loader;
 reg clk=0,rst_n=0,sd_ready=0,load_req=0;reg [2:0] load_index=0;
 always #10 clk=~clk;
 wire rd_req;wire [31:0] rd_sector;reg [7:0] rd_data=0;reg rd_valid=0,rd_done=0;
 wire wr_req;wire [20:0] wr_addr;wire [31:0] wr_data;reg wr_ack=0;
 wire scan_done,busy,load_done,topdown,frame_start,motion,compressed;wire [11:0] h,w;
 wire [3:0] count,error;wire [15:0] frames,spf;wire [20:0] frame_words,audio_base;wire [31:0] audio_samples;
 bmp_sdram_loader dut(clk,rst_n,sd_ready,rd_req,rd_sector,rd_data,rd_valid,rd_done,
  load_req,load_index,wr_req,wr_addr,wr_data,wr_ack,21'd524288,scan_done,busy,load_done,
  count,topdown,frame_start,h,w,error,motion,frames,spf,frame_words,audio_base,audio_samples,compressed);
 reg [7:0] disk[0:338943];reg [31:0] expected[0:5567];
 integer sending=0,pos=0,lba=0,gap=0,wstate=0,delay_count=0,words=0,current=0,requests=0,loads=0;
 always @(posedge clk)begin
  rd_valid<=0;rd_done<=0;
  if(load_done)loads<=loads+1;
  if(rd_req)begin if(sending)$fatal(1,"overlapping sectors");sending<=1;pos<=0;lba<=rd_sector;gap<=0;requests<=requests+1;end
  else if(sending)begin
   if(gap==2)begin gap<=0;
    if(pos<512)begin rd_data<=disk[lba*512+pos];rd_valid<=1;pos<=pos+1;end
    else begin rd_done<=1;sending<=0;end
   end else gap<=gap+1;
  end
  case(wstate)
   0:if(wr_req)begin wstate<=1;delay_count<=0;end
   1:if(delay_count==((words%13==0)?63:2))begin
    if(wr_addr!==((current==3?524288:0)+words))$fatal(1,"address at %0d got %0d",words,wr_addr);
    if(current==0 && wr_data!==expected[words])$fatal(1,"payload %0d got %h expected %h",words,wr_data,expected[words]);
    if(current==3 && wr_data!==32'hcbca_cbca)$fatal(1,"BMP recovery pixel %h",wr_data);
    wr_ack<=1;words<=words+1;wstate<=2;
   end else delay_count<=delay_count+1;
   2:if(!wr_req)begin wr_ack<=0;wstate<=0;end
  endcase
 end
 task request;input [2:0] index;begin
  @(negedge clk);current=index;words=0;load_index=index;load_req=1;
  @(negedge clk);load_req=0;
 end endtask
 initial begin
  if($test$plusargs("MBR"))$readmemh("tests/motion_disk_mbr.hex",disk);else $readmemh("tests/motion_disk.hex",disk);
  $readmemh("tests/motion_expected.hex",expected);
  #41;rst_n=1;sd_ready=1;
  wait(load_done);#1;
  if(error||count!=4||!motion||w!=32||h!=16||!topdown||frames!=3||spf!=1600||frame_words!=256||audio_base!=768||audio_samples!=4800||words!=5568)
   $fatal(1,"LAV metadata count%0d err%0d words%0d frames%0d fw%0d audio%0d",count,error,words,frames,frame_words,audio_samples);
  request(1);wait(busy);wait(!busy);#1;
  if(error!=9||words!=5568||loads!=1)$fatal(1,"checksum rejection err%0d words%0d loads%0d",error,words,loads);
  request(2);wait(busy);wait(!busy);#1;
  if(error!=8||words!=0||loads!=1)$fatal(1,"invalid header rejection err%0d words%0d",error,words);
  request(3);wait(busy);wait(load_done);#1;
  if(error||motion||words!=128||w!=16||h!=16||!topdown)$fatal(1,"BMP recovery failed %0d %0d",error,words);
  $display("PASS LAV LOADER: exact RGB565+stereo payload, fragmented FAT/root chains, checksum/header rejection, BMP recovery, %0d sector reads",requests);$finish;
 end
 initial begin #30000000;$fatal(1,"LAV timeout state%0d error%0d words%0d",dut.state,error,words);end
endmodule
