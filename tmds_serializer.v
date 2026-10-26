`timescale 1ns/1ps
// A pixel event, rather than a free-running phase counter, aligns each 10-bit
// symbol with the forwarded clock. The bundled payload is sampled only after
// its toggle has crossed three serializer registers (5:1 clock relationship).
module tmds_serializer(
 input wire pclk,sclk,prst_n,srst_n,input wire [9:0] r,g,b,
 output wire out_r,out_g,out_b,out_clk);
 reg pixel_toggle;reg [2:0] sync;reg load_event;
 reg [9:0] sh_r,sh_g,sh_b,sh_clk;
 wire event_pixel=sync[2]^sync[1];
 always @(posedge pclk or negedge prst_n)begin if(!prst_n)pixel_toggle<=0;else pixel_toggle<=~pixel_toggle;end
 always @(posedge sclk or negedge srst_n)begin
  if(!srst_n)begin load_event<=0;sync<=0;sh_r<=0;sh_g<=0;sh_b<=0;sh_clk<=10'b0000011111;end
  else begin
   sync<={sync[1:0],pixel_toggle};load_event<=event_pixel;
   if(load_event)begin sh_r<=r;sh_g<=g;sh_b<=b;sh_clk<=10'b0000011111;end
   else begin sh_r<={2'b0,sh_r[9:2]};sh_g<={2'b0,sh_g[9:2]};sh_b<={2'b0,sh_b[9:2]};sh_clk<={2'b0,sh_clk[9:2]};end
  end
 end
 EG_LOGIC_ODDR #(.ASYNCRST("DISABLE")) dr(.q(out_r),.clk(sclk),.d0(sh_r[0]),.d1(sh_r[1]),.rst(1'b0));
 EG_LOGIC_ODDR #(.ASYNCRST("DISABLE")) dg(.q(out_g),.clk(sclk),.d0(sh_g[0]),.d1(sh_g[1]),.rst(1'b0));
 EG_LOGIC_ODDR #(.ASYNCRST("DISABLE")) db(.q(out_b),.clk(sclk),.d0(sh_b[0]),.d1(sh_b[1]),.rst(1'b0));
 EG_LOGIC_ODDR #(.ASYNCRST("DISABLE")) dc(.q(out_clk),.clk(sclk),.d0(sh_clk[0]),.d1(sh_clk[1]),.rst(1'b0));
endmodule
