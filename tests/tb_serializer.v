`timescale 1ns/1fs
module EG_LOGIC_ODDR #(parameter ASYNCRST="DISABLE")(
 output wire q,input wire clk,d0,d1,rst);
 reg high_value,low_value,low_latched;reg delayed_clk;
 always @(posedge clk)begin high_value<=d0;low_latched<=d1;end
 always @(negedge clk)low_value<=low_latched;
 always @(clk)delayed_clk<=#0.1 clk;
 assign q=delayed_clk?high_value:low_value;
endmodule
module tb_serializer;
 reg pclk=0,sclk=0,rst_n=0;real phase=2.6936;
 initial begin if($test$plusargs("PHASE_SHIFT"))phase=0.35; #(phase);pclk=1;forever #6.734 pclk=~pclk;end
 initial begin #1.3468;sclk=1;forever #1.3468 sclk=~sclk;end
 reg [9:0] r=0,g=10'h3ff,b=10'h155;wire qr,qg,qb,qc;
 tmds_serializer dut(pclk,sclk,rst_n,rst_n,r,g,b,qr,qg,qb,qc);
 always @(posedge pclk)if(rst_n)begin r<=r+1'b1;g<=(r+10'd1)^10'h3ff;b<=(r+10'd1)^10'h155;end
 integer n,j;reg[9:0] rr,gg,bb,last_r;
 initial begin
  #51;rst_n=1;repeat(5)@(posedge qc);
  for(n=0;n<20000;n=n+1)begin
   @(posedge qc);#0.2;rr[0]=qr;gg[0]=qg;bb[0]=qb;
   for(j=1;j<10;j=j+1)begin #1.3468;rr[j]=qr;gg[j]=qg;bb[j]=qb;end
   if(gg!==(rr^10'h3ff)||bb!==(rr^10'h155))$fatal(1,"Serializer lane bit mismatch n%0d R%h G%h B%h",n,rr,gg,bb);
   if(n>0 && rr!==(last_r+10'd1))$fatal(1,"Serializer duplicated/dropped symbol n%0d got%h previous%h",n,rr,last_r);
   last_r=rr;
  end
  $display("PASS SERIALIZER: 20000 consecutive 10-bit symbols, all lanes, forwarded clock, phase=%f ns",phase);$finish;
 end
 initial begin #1000000;$fatal(1,"serializer timeout");end
endmodule
