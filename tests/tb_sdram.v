`timescale 1ns/1ps
module tb_sdram;
 reg clk=0,memclk=0,rst_n=0,wr_req=0,line_req=0;
 always #5.333333 clk=~clk;
 initial begin #2.666667;forever #5.333333 memclk=~memclk;end
 wire ras,cas,we;wire[10:0] addr;wire[1:0] ba;tri[31:0] dq;
 wire init_done,wr_ack,line_we,line_done;wire[31:0] line_data;
 reg[20:0] wr_addr=0,line_base=0;reg[31:0] wr_data=0;reg[9:0] line_words=640;
 sdram_ctrl_clean dut(clk,rst_n,ras,cas,we,addr,ba,dq,init_done,wr_req,wr_data,wr_addr,1'b0,wr_ack,line_req,line_base,line_words,line_data,line_we,line_done);
 reg[31:0] memory[0:2097151];reg[10:0] rows[0:3];
 reg[2:0] pipe=0;reg[31:0] p0,p1,p2,outdata;reg drive=0;integer refreshes=0,reads=0,writes=0,k,count;
 assign dq=drive ? outdata : 32'bz;
 always @(posedge memclk)begin
  pipe<={pipe[1:0],{ras,cas,we}==3'b101};
  if({ras,cas,we}==3'b011)rows[ba]<=addr;
  if({ras,cas,we}==3'b100)begin memory[{ba,rows[ba],addr[7:0]}]<=dq;writes=writes+1;end
  if({ras,cas,we}==3'b101)begin p0<=memory[{ba,rows[ba],addr[7:0]}];reads=reads+1;end
  p1<=p0;p2<=p1;
  drive<=#5 pipe[2];outdata<=#5 p2;
  if({ras,cas,we}==3'b001)refreshes=refreshes+1;
 end
 task write_word;input[20:0] a;input[31:0] d;begin
  @(negedge clk);wr_addr=a;wr_data=d;wr_req=1;
  wait(wr_ack);repeat(4)@(negedge clk);wr_req=0;wait(!wr_ack);
 end endtask
 task read_line;input[20:0] a;input[9:0] n;begin
  @(negedge clk);line_base=a;line_words=n;line_req=1;count=0;
  while(!line_done)begin @(negedge clk);
   if(line_we)begin
    if(line_data!==memory[a+count])$fatal(1,"Read mismatch word %0d at %0d got %h expected %h",count,a+count,line_data,memory[a+count]);
    count=count+1;
   end
   if(line_done&&count!=n)$fatal(1,"Early line_done %0d/%0d",count,n);
  end
  repeat(5)@(negedge clk);
  if(count!=n)$fatal(1,"word count %0d",count);
  line_req=0;repeat(8)@(negedge clk);
 end endtask
 initial begin
  for(k=0;k<2097152;k=k+1)memory[k]=32'h91230000^k;
  #20;rst_n=1;wait(init_done);
  write_word(21'd600000,32'h76543210);write_word(21'd262145,32'hfedcba98);
  write_word(21'd2000000,32'h1234abcd);write_word(21'd2097151,32'h89abcdef);
  read_line(21'd600000,640);read_line(21'd262000,640);read_line(21'd450,320);
  read_line(21'd2000000,640);read_line(21'd2096896,256);read_line(21'd1048400,640);
  repeat(3000)@(negedge clk);
  if(writes!=4)$fatal(1,"duplicate writes %0d",writes);
  if(reads!=3136)$fatal(1,"duplicate reads %0d",reads);
  if(refreshes<12)$fatal(1,"no periodic refresh %0d",refreshes);
  $display("PASS SDRAM: 3136 words, all four banks, upper 4MiB, final SDRAM address, column/row/bank crossings, handshake, periodic refresh (%0d)",refreshes);$finish;
 end
 initial begin #1000000;$fatal(1,"SDRAM timeout state %0d received %0d",dut.state,dut.receive_count);end
endmodule
