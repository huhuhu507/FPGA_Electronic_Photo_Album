`timescale 1ns/1ps
// EM638325: 4 banks x 2048 rows x 256 32-bit columns.
// Logic clock 93.75 MHz, memory clock +90 degrees, CL=3, BL=1.
// Requests use four-phase handshakes; addresses/data are latched on acceptance.
module sdram_ctrl_clean(
 input wire clk, rst_n,
 output wire sd_ras_n,sd_cas_n,sd_we_n,
 output reg [10:0] sd_addr, output reg [1:0] sd_ba,
 inout wire [31:0] dq,
 output reg init_done,
 input wire wr_req, input wire [31:0] wr_data,
 input wire [20:0] wr_addr, input wire wr_reset, output reg wr_ack,
 input wire line_req, input wire [20:0] line_base,
 input wire [9:0] line_words,
 output reg [31:0] line_data, output reg line_we,line_done
);
 localparam INIT=0,PRE=1,WAIT_PRE=2,REF=3,WAIT_REF=4,MODE=5,
 WAIT_MODE=6,IDLE=7,WACT=8,WWAIT=9,WRITE=10,WREC=11,WACK=12,
 RACT=13,RWAIT=14,READ=15,RNEXT=16,RPAGE=17,RDRAIN=18,RDONE=19;
 reg [4:0] state;
 reg [14:0] power_count;
 reg [3:0] delay_count,init_refs;
 reg [9:0] ref_count;
 reg [3:0] ref_debt;
 reg [20:0] address;
 reg [31:0] write_data;
 reg [9:0] issue_count,receive_count,words_latched;
 reg [2:0] read_valid;
 reg [2:0] command;
 wire issue=(state==READ);
 wire ref_tick=init_done && (ref_count==10'd699);
 wire ref_take=(state==REF) && init_done;
 wire last_word=(issue_count+10'd1==words_latched);
 always @* begin
  command=3'b111;sd_addr=11'd0;sd_ba=address[20:19];
  case(state)
   PRE:begin command=3'b010;sd_addr=11'h400;end
   REF:command=3'b001;
   MODE:begin command=3'b000;sd_addr=11'h030;sd_ba=0;end
   WACT,RACT:begin command=3'b011;sd_addr=address[18:8];end
   WRITE:begin command=3'b100;sd_addr={1'b1,2'b00,address[7:0]};end
   READ:begin command=3'b101;sd_addr={(last_word || address[7:0]==8'hff),2'b00,address[7:0]};end
  endcase
 end
 assign {sd_ras_n,sd_cas_n,sd_we_n}=command;
 assign dq=(state==WRITE) ? write_data : 32'bz;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   state<=INIT;power_count<=0;delay_count<=0;init_refs<=0;
   ref_count<=0;ref_debt<=0;address<=0;write_data<=0;
   issue_count<=0;receive_count<=0;words_latched<=0;read_valid<=0;
   init_done<=0;wr_ack<=0;line_data<=0;line_we<=0;line_done<=0;
  end else begin
   line_we<=0;line_done<=0;
   read_valid<={read_valid[1:0],issue};
   if(init_done)begin
    ref_count<=ref_tick ? 10'd0 : ref_count+10'd1;
    case({ref_tick,ref_take})
     2'b10:if(ref_debt!=15)ref_debt<=ref_debt+1'b1;
     2'b01:if(ref_debt!=0)ref_debt<=ref_debt-1'b1;
    endcase
   end
   // READ was sampled by the memory at the preceding +90-degree edge.
   // At CL=3, its data is stable before this third subsequent logic edge.
   if(read_valid[2])begin
    line_data<=dq;line_we<=1;
    receive_count<=receive_count+1'b1;
   end
   case(state)
    INIT:if(power_count==15'd25000)state<=PRE;else power_count<=power_count+1'b1;
    PRE:begin delay_count<=0;state<=WAIT_PRE;end
    WAIT_PRE:if(delay_count==3)state<=REF;else delay_count<=delay_count+1'b1;
    REF:begin delay_count<=0;state<=WAIT_REF;end
    WAIT_REF:if(delay_count==8)begin
      if(init_done)state<=IDLE;
      else if(init_refs==7)state<=MODE;
      else begin init_refs<=init_refs+1'b1;state<=REF;end
     end else delay_count<=delay_count+1'b1;
    MODE:begin delay_count<=0;state<=WAIT_MODE;end
    WAIT_MODE:if(delay_count==3)begin init_done<=1;state<=IDLE;end else delay_count<=delay_count+1'b1;
    IDLE:if(ref_debt!=0)state<=REF;
     else if(line_req && line_words!=0)begin
      address<=line_base;words_latched<=line_words;issue_count<=0;receive_count<=0;state<=RACT;
     end else if(wr_req)begin address<=wr_addr;write_data<=wr_data;state<=WACT;end
    WACT:begin delay_count<=0;state<=WWAIT;end
    WWAIT:if(delay_count==3)state<=WRITE;else delay_count<=delay_count+1'b1;
    WRITE:begin delay_count<=0;state<=WREC;end
    WREC:if(delay_count==6)begin wr_ack<=1;state<=WACK;end else delay_count<=delay_count+1'b1;
    WACK:if(!wr_req)begin wr_ack<=0;state<=IDLE;end
    RACT:begin delay_count<=0;state<=RWAIT;end
    RWAIT:if(delay_count==3)state<=READ;else delay_count<=delay_count+1'b1;
    READ:begin issue_count<=issue_count+1'b1;state<=RNEXT;end
    RNEXT:begin
     address<=address+1'b1;
     if(issue_count==words_latched)begin delay_count<=0;state<=RDRAIN;end
     else if(address[7:0]==8'hff)begin delay_count<=0;state<=RPAGE;end
     else state<=READ;
    end
    RPAGE:if(delay_count==5)state<=RACT;else delay_count<=delay_count+1'b1;
    RDRAIN:if(delay_count==6 && receive_count==words_latched)begin line_done<=1;state<=RDONE;end
     else if(delay_count!=6)delay_count<=delay_count+1'b1;
    RDONE:if(!line_req)state<=IDLE;
    default:state<=INIT;
   endcase
  end
 end
endmodule
