`timescale 1ns/1ps
// FAT32 root-directory BMP reader. Follows FAT chains for fragmented files.
// A complete 512-byte sector is buffered before parsing; SDRAM back-pressure
// can therefore never drop an SPI byte. 24-bit BI_RGB, even width 16..1280,
// height +/-16..720. Packed RGB565 is stored without horizontal resampling.
module bmp_sdram_loader(
 input wire clk,rst_n,sd_ready,
 output reg rd_req,output reg [31:0] rd_sector,
 input wire [7:0] rd_data,input wire rd_valid,rd_done,
 input wire load_req,input wire [2:0] load_index,
 output reg wr_req,output reg [20:0] wr_addr,output reg [31:0] wr_data,
 input wire wr_ack,input wire [20:0] fb_offset,
 output reg scan_done,busy,load_done,
 output reg [3:0] bmp_count,output reg img_topdown,frame_start,
 output reg [11:0] img_h,img_w,output reg [3:0] error,
 output reg motion_mode,output reg [15:0] motion_frames,motion_spf,
 output reg [20:0] motion_frame_words,motion_audio_base,
 output reg [31:0] motion_audio_samples,output reg motion_compressed
);
 localparam BOOT=0,IO_REQ=1,IO_WAIT=2,BOOT_PARSE=3,BOOT_EVAL=4,
 DIR_READ=5,DIR_PARSE=6,DIR_NEXT=7,FAT_READ=8,FAT_PARSE=9,FAT_EVAL=10,
 SCAN_END=11,START_FILE=12,HEADER=13,HEADER_EVAL=14,PIXEL=15,
 WRITE_WAIT=16,WRITE_LOW=17,FILE_NEXT=18,FILE_READ=19,READY=20,FAIL=21;
 localparam MEDIA_EVAL=22,MEDIA_CHECK=23,MEDIA_RAW=24;
 reg [4:0] state,io_return,fat_return;
 reg kind_table[0:7];
 reg [31:0] lav_magic,lav_header,lav_count,lav_spf,lav_audio,lav_video,lav_total,lav_rate,lav_fps,lav_flags,lav_checksum;
 reg [31:0] calc_frame_words,calc_video_words,calc_audio_samples,calc_rate;
 reg [31:0] payload_word,payload_sum;reg [1:0] payload_byte;
 reg [7:0] sector_buf[0:511];
 reg [9:0] pointer,io_count;
 reg [25:0] timeout_count;
 reg [31:0] io_sector,part_base,mbr_start,fat_base,data_base,fat_size,root_cluster;
 reg [15:0] reserved_sectors,bytes_per_sector,signature;
 reg [7:0] sectors_per_cluster,fat_copies,partition_type;
 reg [2:0] cluster_shift;
 reg partition_loaded;
 reg [31:0] dir_cluster,dir_clusters_seen,file_cluster,fat_cluster,fat_value;
 reg [7:0] cluster_sector;
 reg [1:0] fat_byte;
 reg [31:0] file_table[0:7],size_table[0:7];
 reg [31:0] entry_cluster,entry_size;
 reg [7:0] entry_first,entry_attr,ext0,ext1,ext2;
 reg [31:0] dib_size,pixel_offset,width32,height32,compression;
 reg [15:0] bit_depth,planes;
 reg [31:0] file_size,file_position,skip_bytes;
 reg [20:0] frame_base,word_count;
 reg [11:0] px,py;
 reg [1:0] component,padding;
 reg [7:0] blue,green;
 reg [15:0] low_pixel;
 reg half,last_pixel;
 wire [7:0] value=sector_buf[pointer[8:0]];
 wire [31:0] abs_height=height32[31] ? (~height32+32'd1) : height32;
 wire [15:0] rgb565={value[7:3],green[7:2],blue[7:3]};
 wire [31:0] fat_entry_address=(fat_cluster>>7);
 wire [31:0] directory_base=data_base+((dir_cluster-32'd2)<<cluster_shift);
 wire [31:0] current_file_base=data_base+((file_cluster-32'd2)<<cluster_shift);
 wire bmp_extension=(ext0==8'h42||ext0==8'h62)&&(ext1==8'h4d||ext1==8'h6d)&&(ext2==8'h50||ext2==8'h70);
 wire lav_extension=(ext0==8'h4c||ext0==8'h6c)&&(ext1==8'h41||ext1==8'h61)&&(ext2==8'h56||ext2==8'h76);
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=BOOT;io_return<=BOOT_PARSE;fat_return<=DIR_READ;
   rd_req<=0;rd_sector<=0;wr_req<=0;wr_addr<=0;wr_data<=0;
   scan_done<=0;busy<=0;load_done<=0;bmp_count<=0;img_topdown<=0;frame_start<=0;img_w<=0;img_h<=0;error<=0;
   pointer<=0;io_count<=0;timeout_count<=0;io_sector<=0;part_base<=0;mbr_start<=0;
   fat_base<=0;data_base<=0;fat_size<=0;root_cluster<=0;reserved_sectors<=0;
   bytes_per_sector<=0;signature<=0;sectors_per_cluster<=0;fat_copies<=0;partition_type<=0;
   cluster_shift<=0;partition_loaded<=0;dir_cluster<=0;dir_clusters_seen<=0;file_cluster<=0;fat_cluster<=0;fat_value<=0;
   cluster_sector<=0;fat_byte<=0;entry_cluster<=0;entry_size<=0;entry_first<=0;entry_attr<=0;ext0<=0;ext1<=0;ext2<=0;
   dib_size<=0;pixel_offset<=0;width32<=0;height32<=0;compression<=0;bit_depth<=0;planes<=0;
   file_size<=0;file_position<=0;skip_bytes<=0;frame_base<=0;word_count<=0;
   px<=0;py<=0;component<=0;padding<=0;blue<=0;green<=0;low_pixel<=0;half<=0;last_pixel<=0;
   motion_compressed<=0;motion_mode<=0;motion_frames<=0;motion_spf<=0;motion_frame_words<=0;motion_audio_base<=0;motion_audio_samples<=0;
   lav_magic<=0;lav_header<=0;lav_count<=0;lav_spf<=0;lav_audio<=0;lav_video<=0;lav_total<=0;lav_rate<=0;lav_fps<=0;lav_flags<=0;lav_checksum<=0;
   calc_frame_words<=0;calc_video_words<=0;calc_audio_samples<=0;calc_rate<=0;payload_word<=0;payload_byte<=0;payload_sum<=0;
   for(i=0;i<8;i=i+1)begin file_table[i]<=0;size_table[i]<=0;kind_table[i]<=0;end
  end else begin
   rd_req<=0;load_done<=0;frame_start<=0;
   case(state)
    BOOT:if(sd_ready)begin io_sector<=0;io_return<=BOOT_PARSE;state<=IO_REQ;end
    IO_REQ:begin rd_sector<=io_sector;rd_req<=1;io_count<=0;timeout_count<=0;state<=IO_WAIT;end
    IO_WAIT:begin
     timeout_count<=timeout_count+1'b1;
     if(rd_valid && io_count<512)begin sector_buf[io_count[8:0]]<=rd_data;io_count<=io_count+1'b1;end
     if(rd_done)begin
      if(io_count==512 || (io_count==511 && rd_valid))begin pointer<=0;state<=io_return;end
      else begin error<=4'd5;state<=FAIL;end
     end else if(timeout_count==26'd49_999_999)begin error<=4'd6;state<=FAIL;end
    end
    BOOT_PARSE:begin
     case(pointer)
      11:bytes_per_sector[7:0]<=value;12:bytes_per_sector[15:8]<=value;
      13:sectors_per_cluster<=value;
      14:reserved_sectors[7:0]<=value;15:reserved_sectors[15:8]<=value;
      16:fat_copies<=value;
      36:fat_size[7:0]<=value;37:fat_size[15:8]<=value;38:fat_size[23:16]<=value;39:fat_size[31:24]<=value;
      44:root_cluster[7:0]<=value;45:root_cluster[15:8]<=value;46:root_cluster[23:16]<=value;47:root_cluster[31:24]<=value;
      450:partition_type<=value;
      454:mbr_start[7:0]<=value;455:mbr_start[15:8]<=value;456:mbr_start[23:16]<=value;457:mbr_start[31:24]<=value;
      510:signature[7:0]<=value;511:signature[15:8]<=value;
     endcase
     if(pointer==511)state<=BOOT_EVAL;else pointer<=pointer+1'b1;
    end
    BOOT_EVAL:begin
     if(signature!=16'haa55)begin error<=4'd3;state<=FAIL;end
     else if(bytes_per_sector==512 && reserved_sectors!=0 && fat_size!=0 && root_cluster>=2 &&
        (fat_copies==1||fat_copies==2) && sectors_per_cluster!=0 && (sectors_per_cluster&(sectors_per_cluster-1'b1))==0)begin
      fat_base<=part_base+reserved_sectors;
      data_base<=part_base+reserved_sectors+(fat_copies==2 ? fat_size<<1 : fat_size);
      case(sectors_per_cluster)
       1:cluster_shift<=0;2:cluster_shift<=1;4:cluster_shift<=2;8:cluster_shift<=3;
       16:cluster_shift<=4;32:cluster_shift<=5;64:cluster_shift<=6;128:cluster_shift<=7;
      endcase
      dir_cluster<=root_cluster;cluster_sector<=0;dir_clusters_seen<=0;state<=DIR_READ;
     end else if(!partition_loaded && (partition_type==8'h0b||partition_type==8'h0c) && mbr_start!=0)begin
      part_base<=mbr_start;io_sector<=mbr_start;partition_loaded<=1;io_return<=BOOT_PARSE;state<=IO_REQ;
     end else begin error<=4'd3;state<=FAIL;end
    end
    DIR_READ:begin io_sector<=directory_base+cluster_sector;io_return<=DIR_PARSE;state<=IO_REQ;end
    DIR_PARSE:begin
     case(pointer[4:0])
      0:entry_first<=value;8:ext0<=value;9:ext1<=value;10:ext2<=value;11:entry_attr<=value;
      20:entry_cluster[23:16]<=value;21:entry_cluster[31:24]<=value;
      26:entry_cluster[7:0]<=value;27:entry_cluster[15:8]<=value;
      28:entry_size[7:0]<=value;29:entry_size[15:8]<=value;30:entry_size[23:16]<=value;
      31:begin
       if(entry_first==0)state<=SCAN_END;
       else if(entry_first!=8'he5 && (entry_attr&8'h18)==0 && entry_attr!=8'h0f && (bmp_extension||lav_extension) && entry_cluster>=2)begin
        kind_table[bmp_count[2:0]]<=lav_extension;file_table[bmp_count[2:0]]<=entry_cluster;size_table[bmp_count[2:0]]<={value,entry_size[23:0]};bmp_count<=bmp_count+1'b1;
        if(bmp_count==7)state<=SCAN_END;
       end
      end
     endcase
     pointer<=pointer+1'b1;
     // Evaluate end-of-sector on the following cycle to retain the last entry.
     if(pointer==512)state<=DIR_NEXT;
    end
    DIR_NEXT:begin
     if(cluster_sector+1'b1<sectors_per_cluster)begin cluster_sector<=cluster_sector+1'b1;state<=DIR_READ;end
     else begin fat_cluster<=dir_cluster;fat_return<=DIR_READ;state<=FAT_READ;end
    end
    FAT_READ:begin io_sector<=fat_base+fat_entry_address;io_return<=FAT_PARSE;fat_value<=0;fat_byte<=0;state<=IO_REQ;end
    FAT_PARSE:begin
     // First set the pointer, then collect the four little-endian FAT bytes.
     if(pointer==0 && fat_byte==0)begin pointer<={1'b0,fat_cluster[6:0],2'b00};fat_byte<=1;end
     else begin
      case(fat_byte)
       1:fat_value[7:0]<=value;
       2:fat_value[15:8]<=value;
       3:fat_value[23:16]<=value;
       0:begin fat_value[31:24]<=value;state<=FAT_EVAL;end
      endcase
      pointer<=pointer+1'b1;fat_byte<=fat_byte+1'b1;
     end
    end
    FAT_EVAL:begin
     if(fat_value[27:0]>=28'hffffff8)begin
      if(fat_return==DIR_READ)state<=SCAN_END;else begin error<=4'd7;state<=FAIL;end
     end else if(fat_value[27:0]<2 || fat_value[27:0]==28'hffffff7)begin error<=4'd7;state<=FAIL;end
     else begin
      cluster_sector<=0;
      if(fat_return==DIR_READ)begin
       dir_cluster<={4'd0,fat_value[27:0]};dir_clusters_seen<=dir_clusters_seen+1'b1;
       if(dir_clusters_seen==1023)begin error<=4'd7;state<=FAIL;end else state<=DIR_READ;
      end else begin file_cluster<={4'd0,fat_value[27:0]};state<=FILE_READ;end
     end
    end
    SCAN_END:begin
     scan_done<=1;
     if(bmp_count==0)begin error<=4'd1;state<=READY;end
     else begin file_cluster<=file_table[0];file_size<=size_table[0];motion_mode<=kind_table[0];state<=START_FILE;end
    end
    START_FILE:begin
     busy<=1;error<=0;frame_start<=1;motion_compressed<=0;frame_base<=motion_mode?21'd0:fb_offset;word_count<=0;
     payload_word<=0;payload_byte<=0;payload_sum<=0;lav_magic<=0;lav_header<=0;lav_count<=0;lav_spf<=0;
     lav_audio<=0;lav_video<=0;lav_total<=0;lav_rate<=0;lav_fps<=0;lav_flags<=0;lav_checksum<=0;
     cluster_sector<=0;file_position<=0;px<=0;py<=0;component<=0;padding<=0;half<=0;last_pixel<=0;
     dib_size<=0;pixel_offset<=0;width32<=0;height32<=0;compression<=0;bit_depth<=0;planes<=0;signature<=0;
     io_sector<=current_file_base;io_return<=HEADER;state<=IO_REQ;
    end
    HEADER:begin
     if(motion_mode)begin
      case(pointer[8:2])
       0:lav_magic[8*pointer[1:0]+:8]<=value;
       1:lav_header[8*pointer[1:0]+:8]<=value;
       2:width32[8*pointer[1:0]+:8]<=value;
       3:height32[8*pointer[1:0]+:8]<=value;
       4:lav_count[8*pointer[1:0]+:8]<=value;
       5:lav_spf[8*pointer[1:0]+:8]<=value;
       6:lav_audio[8*pointer[1:0]+:8]<=value;
       7:lav_video[8*pointer[1:0]+:8]<=value;
       8:lav_total[8*pointer[1:0]+:8]<=value;
       9:lav_rate[8*pointer[1:0]+:8]<=value;
       10:lav_fps[8*pointer[1:0]+:8]<=value;
       11:lav_flags[8*pointer[1:0]+:8]<=value;
       12:lav_checksum[8*pointer[1:0]+:8]<=value;
      endcase
     end else case(pointer)
      0:signature[7:0]<=value;1:signature[15:8]<=value;
      10:pixel_offset[7:0]<=value;11:pixel_offset[15:8]<=value;12:pixel_offset[23:16]<=value;13:pixel_offset[31:24]<=value;
      14:dib_size[7:0]<=value;15:dib_size[15:8]<=value;16:dib_size[23:16]<=value;17:dib_size[31:24]<=value;
      18:width32[7:0]<=value;19:width32[15:8]<=value;20:width32[23:16]<=value;21:width32[31:24]<=value;
      22:height32[7:0]<=value;23:height32[15:8]<=value;24:height32[23:16]<=value;25:height32[31:24]<=value;
      26:planes[7:0]<=value;27:planes[15:8]<=value;28:bit_depth[7:0]<=value;29:bit_depth[15:8]<=value;
      30:compression[7:0]<=value;31:compression[15:8]<=value;32:compression[23:16]<=value;33:compression[31:24]<=value;
     endcase
     if(pointer==53)state<=motion_mode?MEDIA_EVAL:HEADER_EVAL;else pointer<=pointer+1'b1;
    end
    HEADER_EVAL:begin
     if(signature!=16'h4d42 || dib_size<40 || planes!=1 || bit_depth!=24 || compression!=0 ||
       width32<16 || width32>1280 || width32[0] || abs_height<16 || abs_height>720 || pixel_offset<54 || pixel_offset>=file_size)begin
      error<=4'd2;state<=FAIL;
     end else begin img_w<=width32[11:0];img_h<=abs_height[11:0];img_topdown<=height32[31];
      skip_bytes<=pixel_offset;pointer<=0;state<=PIXEL;end
    end
    MEDIA_EVAL:begin
     calc_frame_words<=(width32[11:0]*height32[11:0]) >> (lav_magic==32'h3256414c ? 3 : 1);
     calc_audio_samples<=lav_count[15:0]*lav_spf[15:0];
     calc_rate<=lav_spf[15:0]*lav_fps[7:0];
     state<=MEDIA_CHECK;
    end
    MEDIA_CHECK:begin
     // Split the video product into another registered stage before validation.
     calc_video_words<=calc_frame_words[17:0]*lav_count[15:0];
     state<=25;
    end
    25:begin
     if((lav_magic!=32'h3156414c && lav_magic!=32'h3256414c)||lav_header!=512||width32<16||height32<16||
        (lav_magic==32'h3156414c && (width32>640||width32[0]||height32>360||lav_flags>1))||
        (lav_magic==32'h3256414c && (width32>1280||height32>720||width32[1:0]!=0||height32[1:0]!=0||lav_flags<2||lav_flags>3))||
        lav_count<1||lav_count>240||lav_spf<1600||lav_spf>4800||lav_rate!=48000||calc_rate!=48000||
        !(lav_fps==10||lav_fps==12||lav_fps==15||lav_fps==20||lav_fps==24||lav_fps==30)||
        lav_audio!=calc_audio_samples||lav_video!=calc_video_words||lav_total!=lav_video+lav_audio||
        lav_total==0||lav_total>2097152||file_size!=(512+(lav_total<<2)))begin
      error<=4'd8;state<=FAIL;
     end else begin
      img_w<=width32[11:0];img_h<=height32[11:0];img_topdown<=1;motion_compressed<=(lav_magic==32'h3256414c);
      motion_frames<=lav_count[15:0];motion_spf<=lav_spf[15:0];motion_frame_words<=calc_frame_words[20:0];
      motion_audio_base<=lav_video[20:0];motion_audio_samples<=lav_audio;
      file_position<=512;pointer<=512;state<=MEDIA_RAW;
     end
    end
    MEDIA_RAW:begin
     if(file_position>=file_size)begin error<=4'd7;state<=FAIL;end
     else if(pointer==512)state<=FILE_NEXT;
     else begin
      pointer<=pointer+1'b1;file_position<=file_position+1'b1;
      if(payload_byte==3)begin
       wr_data<={value,payload_word[23:0]};wr_addr<=word_count;wr_req<=1;
       payload_sum<=payload_sum+{value,payload_word[23:0]};payload_byte<=0;word_count<=word_count+1'b1;
       last_pixel<=({11'd0,word_count}+32'd1==lav_total);state<=WRITE_WAIT;
      end else begin payload_word[8*payload_byte+:8]<=value;payload_byte<=payload_byte+1'b1;end
     end
    end
    PIXEL:begin
     if(file_position>=file_size)begin error<=4'd7;state<=FAIL;end
     else if(pointer==512)state<=FILE_NEXT;
     else begin
      pointer<=pointer+1'b1;file_position<=file_position+1'b1;
      if(skip_bytes!=0)skip_bytes<=skip_bytes-1'b1;
      else if(padding!=0)padding<=padding-1'b1;
      else case(component)
       0:begin blue<=value;component<=1;end
       1:begin green<=value;component<=2;end
       2:begin
        component<=0;
        if(!half)begin low_pixel<=rgb565;half<=1;end
        else begin
         wr_data<={rgb565,low_pixel};wr_addr<=frame_base+word_count;wr_req<=1;
         word_count<=word_count+1'b1;half<=0;state<=WRITE_WAIT;
        end
        if(px+1'b1==img_w)begin
         px<=0;py<=py+1'b1;padding<=width32[1] ? 2'd2 : 2'd0;
         if(py+1'b1==img_h)last_pixel<=1;
        end else px<=px+1'b1;
       end
      endcase
     end
    end
    WRITE_WAIT:if(wr_ack)begin wr_req<=0;state<=WRITE_LOW;end
    WRITE_LOW:if(!wr_ack)begin
     if(last_pixel)begin
      if(motion_mode&&payload_sum!=lav_checksum)begin error<=4'd9;state<=FAIL;end
      else begin busy<=0;load_done<=1;state<=READY;end
     end else state<=motion_mode?MEDIA_RAW:PIXEL;
    end
    FILE_NEXT:begin
     if(cluster_sector+1'b1<sectors_per_cluster)begin cluster_sector<=cluster_sector+1'b1;state<=FILE_READ;end
     else begin fat_cluster<=file_cluster;fat_return<=FILE_READ;state<=FAT_READ;end
    end
    FILE_READ:begin io_sector<=current_file_base+cluster_sector;io_return<=motion_mode?MEDIA_RAW:PIXEL;state<=IO_REQ;end
    READY:if(load_req && bmp_count!=0 && load_index<bmp_count)begin
     file_cluster<=file_table[load_index];file_size<=size_table[load_index];motion_mode<=kind_table[load_index];state<=START_FILE;
    end
    FAIL:begin wr_req<=0;busy<=0;scan_done<=1;state<=READY;end
    default:begin error<=4'd15;state<=FAIL;end
   endcase
  end
 end
endmodule
