`timescale 1ns/1ps
module tb_tmds;
 reg clk=0,rst_n=0,de=0;reg [7:0] data=0;reg [1:0] ctrl=0;wire [9:0] symbol;
 always #5 clk=~clk;
 tmds_encoder dut(clk,rst_n,data,de,ctrl,symbol);
 integer rd,i,j,ones,n,diff;reg [8:0] q;reg invert;reg [9:0] expected;
 task check;
  input [7:0] b;input active;input [1:0] c;
  begin
   @(negedge clk);data=b;de=active;ctrl=c;
   if(!active)begin
    rd=0;
    case(c)0:expected=10'b1101010100;1:expected=10'b0010101011;2:expected=10'b0101010100;3:expected=10'b1010101011;endcase
   end else begin
    ones=0;for(j=0;j<8;j=j+1)ones=ones+b[j];
    invert=(ones>4)||(ones==4&&!b[0]);q[0]=b[0];
    for(j=1;j<8;j=j+1)q[j]=invert?~(q[j-1]^b[j]):(q[j-1]^b[j]);q[8]=!invert;
    n=0;for(j=0;j<8;j=j+1)n=n+q[j];diff=2*n-8;
    if(rd==0 || diff==0)expected={~q[8],q[8],q[8]?q[7:0]:~q[7:0]};
    else if((rd>0&&diff>0)||(rd<0&&diff<0))expected={1'b1,q[8],~q[7:0]};
    else expected={1'b0,q[8],q[7:0]};
    n=0;for(j=0;j<10;j=j+1)n=n+expected[j];rd=rd+2*n-10;
   end
   @(posedge clk);#1;
   if(symbol!==expected)$fatal(1,"TMDS mismatch data=%h expected=%b got=%b",b,expected,symbol);
   if(rd>8||rd< -8)$fatal(1,"Disparity out of range %0d",rd);
  end
 endtask
 initial begin rd=0;#23;rst_n=1;
  for(i=0;i<4;i=i+1)check(0,0,i);
  for(i=0;i<65536;i=i+1)check((i*73)^(i>>8),1,0);
  check(0,0,0);$display("PASS TMDS: 65536 symbols, four controls, signed disparity and alternating pixels");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
