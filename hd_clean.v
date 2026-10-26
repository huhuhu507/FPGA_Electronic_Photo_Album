`timescale 1ns/1ps
module hd_clean(
    input  wire clk50,
    input  wire rst_n,
    output wire HDMI_CLK_P,
    output wire HDMI_D0_P,
    output wire HDMI_D1_P,
    output wire HDMI_D2_P,
    output wire led1,
    output wire led2,
    output wire led3,
    output wire led4,
    output wire sd_clk,
    output wire sd_cmd,
    output wire sd_cs_n,
    input  wire sd_dat0,
    input  wire key_next,
    input  wire key_prev,
    input  wire key_auto,
    output wire buzzer
);
    // ---------------- clocks ----------------
    // 50MHz -> 49.5MHz reference PLL -> 742.5MHz video VCO
    //   clk375 : TMDS bit clock          (742.5/2)
    //   clk_mem : SDRAM controller        (742.5/8)
    //   clk75  : pixel clock             (742.5/10)
    wire [4:0] clkc;
    wire clk375_raw = clkc[0];
    wire clk_mem_raw = clkc[1];
    wire clk75_raw  = clkc[2];
    wire clk_mem;
    wire clk375;
    wire clk75;
    wire locked;

    wire [4:0] ref_clocks;wire ref_locked,ref49;
    EG_PHY_PLL #(
        .DYNCFG("DISABLE"),
        .REFCLK_SEL("INTERNAL"),
        .FIN("50.0000"),
        .REFCLK_DIV(5),
        .FBCLK_DIV(99),
        .CLKC0_DIV(20),
        .CLKC1_DIV(8),
        .CLKC3_DIV(8),
        .CLKC1_CPHASE(0),
        .CLKC3_CPHASE(2),
        .CLKC2_DIV(10),
        .CLKC0_CPHASE(0),
        .CLKC0_ENABLE("ENABLE"),
        .CLKC1_ENABLE("DISABLE"),
        .CLKC2_ENABLE("DISABLE"),
        .CLKC3_ENABLE("DISABLE"),
        .CLKC4_ENABLE("DISABLE"),
        .FEEDBK_MODE("NORMAL"),
        .FEEDBK_PATH("VCO_PHASE_0"),
        .STDBY_ENABLE("DISABLE"),
        .PLLRST_ENA("ENABLE")
    ) u_refpll (
        .refclk(clk50),
        .reset(~rst_n),
        .stdby(1'b0),
        .extlock(ref_locked),
        .clkc(ref_clocks),
        .fbclk(1'b0),
        .load_reg(1'b0),
        .psdone(),
        .psclk(1'b0),
        .psdown(1'b0),
        .psstep(1'b0),
        .psclksel(3'b000),
        .do(),
        .dclk(1'b0),
        .dcs(1'b0),
        .dwe(1'b0),
        .di(8'b0),
        .daddr(6'b0)
    );
    EG_PHY_GCLK u_ref_gclk(.clki(ref_clocks[0]),.clko(ref49));
    EG_PHY_PLL #(
        .DYNCFG("DISABLE"),
        .REFCLK_SEL("INTERNAL"),
        .FIN("49.5000"),
        .REFCLK_DIV(1),
        .FBCLK_DIV(15),
        .CLKC0_DIV(2),
        .CLKC1_DIV(8),
        .CLKC3_DIV(8),
        .CLKC1_CPHASE(0),
        .CLKC3_CPHASE(2),
        .CLKC2_DIV(10),
        .CLKC0_CPHASE(0),
        .CLKC0_ENABLE("ENABLE"),
        .CLKC1_ENABLE("ENABLE"),
        .CLKC2_ENABLE("ENABLE"),
        .CLKC3_ENABLE("ENABLE"),
        .CLKC4_ENABLE("DISABLE"),
        .FEEDBK_MODE("NORMAL"),
        .FEEDBK_PATH("VCO_PHASE_0"),
        .STDBY_ENABLE("DISABLE"),
        .PLLRST_ENA("ENABLE")
    ) u_pll (
        .refclk(ref49),
        .reset(~rst_n || !ref_locked),
        .stdby(1'b0),
        .extlock(locked),
        .clkc(clkc),
        .fbclk(1'b0),
        .load_reg(1'b0),
        .psdone(),
        .psclk(1'b0),
        .psdown(1'b0),
        .psstep(1'b0),
        .psclksel(3'b000),
        .do(),
        .dclk(1'b0),
        .dcs(1'b0),
        .dwe(1'b0),
        .di(8'b0),
        .daddr(6'b0)
    );
    EG_PHY_GCLK u_gclk0(.clki(clk375_raw), .clko(clk375));
    EG_PHY_GCLK u_gclk1(.clki(clk_mem_raw), .clko(clk_mem));
    EG_PHY_GCLK u_gclk2(.clki(clk75_raw),  .clko(clk75));

    wire clk_sdram;
    EG_PHY_GCLK u_gclk3(.clki(clkc[3]),.clko(clk_sdram));

    wire rst50_n,rst75_n,rstm_n,rstser_n;
    wire clock_good=rst_n && ref_locked && locked;
    reg [2:0] reset50,reset75,resetmem,resetser;
    always @(posedge clk50 or negedge clock_good)begin if(!clock_good)reset50<=0;else reset50<={reset50[1:0],1'b1};end
    always @(posedge clk75 or negedge clock_good)begin if(!clock_good)reset75<=0;else reset75<={reset75[1:0],1'b1};end
    always @(posedge clk_mem or negedge clock_good)begin if(!clock_good)resetmem<=0;else resetmem<={resetmem[1:0],1'b1};end
    always @(posedge clk375 or negedge clock_good)begin if(!clock_good)resetser<=0;else resetser<={resetser[1:0],1'b1};end
    assign rst50_n=reset50[2];assign rst75_n=reset75[2];assign rstm_n=resetmem[2];assign rstser_n=resetser[2];
    wire sd_ready,rd_req,rd_valid,rd_done;
    wire [31:0] rd_sector;wire [7:0] rd_data;wire [3:0] sd_error;
    sd_ctrl u_sd(.clk(clk50),.rst_n(rst50_n),.sd_clk(sd_clk),.sd_cmd(sd_cmd),.sd_cs_n(sd_cs_n),.sd_dat0(sd_dat0),
      .sd_ready(sd_ready),.rd_req(rd_req),.rd_sector(rd_sector),.rd_data(rd_data),.rd_valid(rd_valid),.rd_done(rd_done),.error_code(sd_error));
    wire scan_done,busy,load_done,ld_frame_start,img_topdown;
    wire [3:0] bmp_count,load_error;wire [11:0] ld_img_w,ld_img_h;
    wire ld_wr_req,ld_wr_ack;wire [20:0] ld_wr_addr;wire [31:0] ld_wr_data;
    wire ui_load_req,auto_en,ui_bmode,ui_dim;
    wire [2:0] load_index;wire [9:0] ui_progress;wire [4:0] ui_bright;
    reg disp_bank,display_en,pending;
    reg [11:0] disp_w,disp_h;reg disp_topdown;
    reg [2:0] display_index;
    reg [1:0] cover_sync;reg display_cover;wire combo_suppress;
    reg [1:0] bank_sync;
    always @(posedge clk50 or negedge rst50_n)begin
      if(!rst50_n)bank_sync<=0;else bank_sync<={bank_sync[0],disp_bank};
    end
    wire [20:0] ld_fb_offset=bank_sync[1] ? 21'd0 : 21'd524288;
    bmp_sdram_loader u_loader(.clk(clk50),.rst_n(rst50_n),.sd_ready(sd_ready),.rd_req(rd_req),.rd_sector(rd_sector),
      .rd_data(rd_data),.rd_valid(rd_valid),.rd_done(rd_done),.load_req(ui_load_req),.load_index(load_index),
      .wr_req(ld_wr_req),.wr_addr(ld_wr_addr),.wr_data(ld_wr_data),.wr_ack(ld_wr_ack),.fb_offset(ld_fb_offset),
      .scan_done(scan_done),.busy(busy),.load_done(load_done),.img_topdown(img_topdown),.frame_start(ld_frame_start),
      .img_h(ld_img_h),.img_w(ld_img_w),.bmp_count(bmp_count),.error(load_error));
    reg done_toggle;
    always @(posedge clk50 or negedge rst50_n)begin
      if(!rst50_n)done_toggle<=0;else if(load_done)done_toggle<=~done_toggle;
    end
    reg [2:0] done_sync;wire commit;reg [4:0] fade_level;reg frame_swapped;
    // Keep the old image visible during SD loading. Only after a complete
    // new frame arrives, fade down, commit at vblank, then fade up.
    always @(posedge clk75 or negedge rst75_n)begin
      if(!rst75_n)begin done_sync<=0;pending<=0;disp_bank<=0;display_en<=0;disp_w<=1280;disp_h<=720;disp_topdown<=0;display_index<=0;fade_level<=0;frame_swapped<=0;end
      else begin
        done_sync<={done_sync[1:0],done_toggle};frame_swapped<=0;
        if(done_sync[2]^done_sync[1])pending<=1;
        if(commit)begin
          if(pending)begin
            if(display_en && fade_level!=0)fade_level<=fade_level-5'd2;
            else begin
              disp_bank<=~disp_bank;display_en<=1;pending<=0;frame_swapped<=1;
              disp_w<=ld_img_w;disp_h<=ld_img_h;disp_topdown<=img_topdown;display_index<=load_index;
            end
          end else if(display_en && fade_level<16)fade_level<=fade_level+5'd2;
        end
      end
    end
    reg [1:0] pending_sync;
    reg commit_pending;
    reg [2:0] bank_event;
    always @(posedge clk50 or negedge rst50_n)begin
      if(!rst50_n)begin pending_sync<=0;commit_pending<=0;bank_event<=0;end
      else begin
        pending_sync<={pending_sync[0],pending};bank_event<={bank_event[1:0],disp_bank};
        if(load_done)commit_pending<=1;
        if(bank_event[2]^bank_event[1])commit_pending<=0;
      end
    end
    album_ui u_ui(.clk(clk50),.rst_n(rst50_n),.key_next(key_next||combo_suppress),.key_prev(key_prev||combo_suppress),.key_auto(key_auto),
      .scan_done(scan_done),.busy(busy||commit_pending),.bmp_count(bmp_count),.load_req(ui_load_req),.load_index(load_index),
      .auto_en(auto_en),.progress(ui_progress),.bright(ui_bright),.bright_mode(ui_bmode),.dim(ui_dim));
    // Stable bundled write payload, synchronized request/acknowledge only.
    reg [1:0] req_sync,ack_sync;wire mem_wr_ack;
    always @(posedge clk_mem or negedge rstm_n)begin
      if(!rstm_n)req_sync<=0;else req_sync<={req_sync[0],ld_wr_req};
    end
    always @(posedge clk50 or negedge rst50_n)begin
      if(!rst50_n)ack_sync<=0;else ack_sync<={ack_sync[0],mem_wr_ack};
    end
    assign ld_wr_ack=ack_sync[1];
    wire [10:0] sd_addr;wire [1:0] sd_ba;wire sd_ras_n,sd_cas_n,sd_we_n;
    wire [31:0] dq,line_data;wire init_done,line_req,line_we,line_done;
    wire [20:0] line_base;wire [9:0] line_words;
    sdram_ctrl_clean u_sdram_ctrl(.clk(clk_mem),.rst_n(rstm_n),.sd_ras_n(sd_ras_n),.sd_cas_n(sd_cas_n),.sd_we_n(sd_we_n),
      .sd_addr(sd_addr),.sd_ba(sd_ba),.dq(dq),.init_done(init_done),.wr_req(req_sync[1]),.wr_data(ld_wr_data),.wr_addr(ld_wr_addr),
      .wr_reset(1'b0),.wr_ack(mem_wr_ack),.line_req(line_req),.line_base(line_base),.line_words(line_words),
      .line_data(line_data),.line_we(line_we),.line_done(line_done));
    EG_PHY_SDRAM_2M_32 u_sdram(.clk(clk_sdram),.ras_n(sd_ras_n),.cas_n(sd_cas_n),.we_n(sd_we_n),
      .addr(sd_addr),.ba(sd_ba),.dq(dq),.cs_n(1'b0),.dm0(1'b0),.dm1(1'b0),.dm2(1'b0),.dm3(1'b0),.cke(1'b1));
    wire [10:0] hcnt;wire [9:0] vcnt;wire [15:0] photo_pixel,underflows;
    video_reader u_video(.pclk(clk75),.mclk(clk_mem),.prst_n(rst75_n),.mrst_n(rstm_n),
      .valid(display_en),.frame_bank(disp_bank),.img_w(disp_w),.img_h(disp_h),.topdown(disp_topdown),.cover_mode(display_cover),
      .x(hcnt),.y(vcnt),.pixel(photo_pixel),.vblank_commit(commit),.line_req(line_req),.line_base(line_base),.line_words(line_words),
      .line_data(line_data),.line_we(line_we),.line_done(line_done),.underflows(underflows));

    reg [4:0] bright_s1,bright_s2;reg [3:0] state_s1,state_s2;reg [1:0] bmode_sync;
    reg [9:0] prog_s1,prog_s2;
    always @(posedge clk75 or negedge rst75_n)begin
      if(!rst75_n)begin bright_s1<=16;bright_s2<=16;state_s1<=0;state_s2<=0;bmode_sync<=0;prog_s1<=0;prog_s2<=0;end
      else begin bright_s1<=ui_bright;bright_s2<=bright_s1;state_s1<={busy,scan_done,sd_ready,auto_en};state_s2<=state_s1;bmode_sync<={bmode_sync[0],ui_bmode};prog_s1<=ui_progress;prog_s2<=prog_s1;end
    end
    reg [8:0] photo_gain;
    always @(posedge clk75 or negedge rst75_n)begin if(!rst75_n)photo_gain<=0;else photo_gain<=fade_level*bright_s2;end
    wire [13:0] r_gain=photo_pixel[15:11]*photo_gain,b_gain=photo_pixel[4:0]*photo_gain;
    wire [14:0] g_gain=photo_pixel[10:5]*photo_gain;
    wire [15:0] photo_faded={r_gain[12:8],g_gain[13:8],b_gain[12:8]};
    // Hold KEY2+KEY3 for 0.8s: a deterministic colour/grid + audio cue test.
    reg [1:0] next_sync,prev_sync;reg [25:0] test_counter;reg test_held,test_mode,cover_mode,combo_latched;
    assign combo_suppress=combo_latched||(!next_sync[1]&&!prev_sync[1]);
    always @(posedge clk50 or negedge rst50_n)begin
      if(!rst50_n)begin next_sync<=3;prev_sync<=3;test_counter<=0;test_held<=0;test_mode<=0;cover_mode<=1;combo_latched<=0;end
      else begin
        next_sync<={next_sync[0],key_next};prev_sync<={prev_sync[0],key_prev};
        if(!next_sync[1]&&!prev_sync[1])combo_latched<=1;
        else if(next_sync[1]&&prev_sync[1])combo_latched<=0;
        if(next_sync[1]||prev_sync[1])begin
          if(!test_held && test_counter>=1_000_000)cover_mode<=~cover_mode;
          test_counter<=0;test_held<=0;
        end
        else if(!test_held)begin
          if(test_counter==39_999_999)begin test_mode<=~test_mode;test_held<=1;end else test_counter<=test_counter+1'b1;
        end
      end
    end
    always @(posedge clk75 or negedge rst75_n)begin
      if(!rst75_n)begin cover_sync<=2'b11;display_cover<=1;end
      else begin cover_sync<={cover_sync[0],cover_mode};if(commit)display_cover<=cover_sync[1];end
    end
    reg [2:0] test_sync;
    always @(posedge clk75 or negedge rst75_n)begin if(!rst75_n)test_sync<=0;else test_sync<={test_sync[1:0],test_mode};end
    wire test_entry=test_sync[1]&&!test_sync[2];
    wire pcm_valid,audio_active,buzzer_pwm;wire signed [15:0] pcm_l,pcm_r;
    audio_synth #(.PIXEL_HZ(74250000)) u_audio(clk75,rst75_n,frame_swapped||test_entry,display_index[1:0],pcm_valid,pcm_l,pcm_r,audio_active,buzzer_pwm);
    assign buzzer=~buzzer_pwm;
    wire [7:0] wave_x;wire [5:0] wave_sample,wave_previous;
    wire frame_tick=(hcnt==0&&vcnt==724);
    audio_scope u_scope(clk75,rst75_n,frame_tick,pcm_valid,pcm_l,wave_x,wave_sample,wave_previous);
    wire [15:0] screen_rgb;wire [10:0] tx_x;wire [9:0] tx_y;
    wire audio_overflow;
    wire [3:0] media_error=(sd_error!=0)?sd_error:load_error;
    signage_osd #(.PIXEL_HZ(74250000)) u_osd(.clk(clk75),.rst_n(rst75_n),.x(hcnt),.y(vcnt),.photo(photo_faded),
      .valid(display_en),.sd_ready(state_s2[1]),.scan_done(state_s2[2]),.busy(state_s2[3]),.auto_en(state_s2[0]),.bright_mode(bmode_sync[1]),.test_mode(test_sync[2]),.cover_mode(display_cover),
      .image_index(display_index),.image_count(bmp_count),.error(media_error),.brightness(bright_s2),.progress(prog_s2),.image_width(disp_w),.image_height(disp_h),
      .wave_sample(wave_sample),.wave_previous(wave_previous),.audio_active(audio_active),.wave_x(wave_x),.rgb(screen_rgb),.out_x(tx_x),.out_y(tx_y));
    wire [23:0] rgb888={screen_rgb[15:11],screen_rgb[15:13],screen_rgb[10:5],screen_rgb[10:9],screen_rgb[4:0],screen_rgb[4:2]};
    wire [9:0] code_r,code_g,code_b;
    hdmi_tx #(.PIXEL_HZ(74250000),.CTS(74250)) u_hdmi(clk75,rst75_n,tx_x,tx_y,rgb888,pcm_valid,pcm_l,pcm_r,code_r,code_g,code_b,audio_overflow);
    tmds_serializer u_serializer(clk75,clk375,rst75_n,rstser_n,code_r,code_g,code_b,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_CLK_P);
    reg [25:0] heartbeat;
    always @(posedge clk50 or negedge rst50_n)begin if(!rst50_n)heartbeat<=0;else heartbeat<=heartbeat+1'b1;end
    assign led1=heartbeat[25];assign led2=sd_ready;assign led3=display_en;
    assign led4=(media_error!=0||audio_overflow||underflows!=0)?heartbeat[23]:busy;
endmodule
