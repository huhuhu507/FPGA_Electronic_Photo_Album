`timescale 1ns/1ps
module tb_hdmi;
 reg clk=0,rst_n=0;always #6.734007 clk=~clk;
 reg [10:0] x=0;reg [9:0] y=0;
 reg[26:0] rate=0;reg pcm_valid=0;reg[15:0] pcm_l=0,pcm_r=16'hffff;integer seq=0;
 wire[27:0] rate_next={1'b0,rate}+48000;
 wire[9:0] r,g,b;wire overflow;
 hdmi_tx dut(clk,rst_n,x,y,24'h3498af,pcm_valid,pcm_l,pcm_r,r,g,b,overflow);
 always @(negedge clk)if(rst_n)begin
  if(x==1649)begin x=0;y=(y==749)?0:y+1;end else x=x+1;
  if(rate_next>=74250000)begin rate=rate_next-74250000;pcm_valid=1;pcm_l=seq;pcm_r=~seq;seq=seq+1;end
  else begin rate=rate_next;pcm_valid=0;end
 end
 function[3:0] decode;
  input[9:0] t;
  begin case(t)
   10'b1010011100:decode=0;10'b1001100011:decode=1;10'b1011100100:decode=2;10'b1011100010:decode=3;
   10'b0101110001:decode=4;10'b0100011110:decode=5;10'b0110001110:decode=6;10'b0100111100:decode=7;
   10'b1011001100:decode=8;10'b0100111001:decode=9;10'b0110011100:decode=10;10'b1011000110:decode=11;
   10'b1010001110:decode=12;10'b1001110001:decode=13;10'b0101100011:decode=14;10'b1011000011:decode=15;
   default:begin decode=0;$fatal(1,"Invalid TERC4 %b",t);end
  endcase end
 endfunction
 function[7:0] reference_crc;
  input[55:0] data;input integer bits;
  reg[7:0] c;integer k;reg bitval;
  begin c=0;for(k=0;k<bits;k=k+1)begin bitval=c[0]^data[k];c=c>>1;if(bitval)c=c^8'h83;end reference_crc=c;end
 endfunction
 reg[31:0] header;reg[63:0] body[0:3];reg[3:0] nr,ng,nb;integer q,k,j,sum,packets=0,samples=0,avi=0,aif=0,acr=0,spd=0,frames=0;
 always @(posedge clk)if(rst_n)begin
  #1;
  if(x>=1294&&x<1422)begin
   q=(x-1294)%32;nr=decode(r);ng=decode(g);nb=decode(b);
   if(q==0)begin header=0;for(k=0;k<4;k=k+1)body[k]=0;end
   header[q]=nb[2];
   for(k=0;k<4;k=k+1)begin body[k][q*2]=ng[k];body[k][q*2+1]=nr[k];end
   if(nb[3]!==1'b1 || nb[0]!== (x>=1390&&x<1430))$fatal(1,"Island control bits");
   if(q==31)begin
    packets=packets+1;
    if(header[31:24]!==reference_crc({32'd0,header[23:0]},24))$fatal(1,"Header BCH failed packet type %h",header[7:0]);
    for(k=0;k<4;k=k+1)if(body[k][63:56]!==reference_crc(body[k][55:0],56))$fatal(1,"Body BCH failed %0d packet%h",k,header[7:0]);
    case(header[7:0])
     8'h82,8'h84,8'h83:begin
      sum=header[7:0]+header[15:8]+header[23:16];
      for(k=0;k<4;k=k+1)for(j=0;j<7;j=j+1)sum=sum+((body[k]>>(j*8))&255);
      if((sum&255)!=0)$fatal(1,"InfoFrame checksum type %h sum%h",header[7:0],sum);
      if(header[7:0]==8'h82)begin avi=avi+1;if(body[0][39:32]!=4||body[0][31:24]!=8'h88)$fatal(1,"AVI VIC / full RGB range");end
      if(header[7:0]==8'h84)aif=aif+1;if(header[7:0]==8'h83)spd=spd+1;
     end
     8'h01:begin
      acr=acr+1;
      if({body[0][19:16],body[0][31:24],body[0][23:16]}===20'hfffff)$fatal(1,"bad ACR");
      if(body[0][55:0]!==56'h0018000a220100)$fatal(1,"ACR N/CTS %h",body[0]);
     end
     8'h02:begin
      if(header[11:8]!=1)$fatal(1,"Audio sample presence");
      if(body[0][23:8]!==samples[15:0] || body[0][47:32]!==~samples[15:0])$fatal(1,"PCM sequence %0d L%h R%h",samples,body[0][23:8],body[0][47:32]);
      if((^{body[0][23:0],body[0][51:48]})!==0 || (^{body[0][47:24],body[0][55:52]})!==0)$fatal(1,"IEC60958 parity");
      if(header[20]!==((samples%192)==0))$fatal(1,"Audio frame start");
      samples=samples+1;
     end
     0:begin end
     default:$fatal(1,"Unknown header %h",header);
    endcase
   end
  end
  if(x==1649&&y==749)begin
   frames=frames+1;
   if(frames==2)begin
    if(overflow||samples<1500||avi!=2||aif!=2||spd!=2||acr<40)$fatal(1,"HDMI coverage frames%0d samples%0d AVI%0d AIF%0d SPD%0d ACR%0d overflow%b",frames,samples,avi,aif,spd,acr,overflow);
    $display("PASS HDMI: %0d decoded packets, %0d sequential stereo PCM samples, BCH, InfoFrame checksums, ACR, channel parity, B markers, FIFO",packets,samples);$finish;
   end
  end
 end
 initial begin #50;rst_n=1;end
 initial begin #40000000;$fatal(1,"HDMI timeout");end
endmodule
