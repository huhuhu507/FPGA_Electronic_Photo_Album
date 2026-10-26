`timescale 1ns/1ps
// Button debounce + auto slideshow controller for the BMP album
module album_ui(
    input  wire clk,
    input  wire rst_n,
    input  wire key_next,   // active low
    input  wire key_prev,   // active low
    input  wire key_auto,   // active low
    input  wire scan_done,
    input  wire busy,
    input  wire [3:0] bmp_count,
    output reg  load_req,
    output reg  [2:0] load_index,
    output reg  auto_en,
    output wire [9:0] progress,     // 0..610 slideshow progress
    output reg  [4:0] bright,       // 4..20 display brightness
    output reg        bright_mode,  // 1 while adjusting
    output reg        dim           // 1 while fading out before a load
);
    reg [25:0] dim_cnt;
    reg a_hold_done;

    // ---------------- synchronizers + debounce ----------------
    reg [1:0] sync_n, sync_p, sync_a;
    reg stable_n, stable_p, stable_a;
    reg stable_n_d, stable_p_d, stable_a_d;
    reg [19:0] cnt_n, cnt_p, cnt_a;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_n <= 2'b11; sync_p <= 2'b11; sync_a <= 2'b11;
            stable_n <= 1'b1; stable_p <= 1'b1; stable_a <= 1'b1;
            stable_n_d <= 1'b1; stable_p_d <= 1'b1; stable_a_d <= 1'b1;
            cnt_n <= 20'd0; cnt_p <= 20'd0; cnt_a <= 20'd0;
        end else begin
            sync_n <= {sync_n[0], key_next};
            sync_p <= {sync_p[0], key_prev};
            sync_a <= {sync_a[0], key_auto};

            if (sync_n[1] != stable_n) begin
                if (cnt_n == 20'd999_999) stable_n <= sync_n[1];
                else cnt_n <= cnt_n + 20'd1;
            end else begin
                cnt_n <= 20'd0;
            end

            if (sync_p[1] != stable_p) begin
                if (cnt_p == 20'd999_999) stable_p <= sync_p[1];
                else cnt_p <= cnt_p + 20'd1;
            end else begin
                cnt_p <= 20'd0;
            end

            if (sync_a[1] != stable_a) begin
                if (cnt_a == 20'd999_999) stable_a <= sync_a[1];
                else cnt_a <= cnt_a + 20'd1;
            end else begin
                cnt_a <= 20'd0;
            end

            stable_n_d <= stable_n;
            stable_p_d <= stable_p;
            stable_a_d <= stable_a;
        end
    end

    wire press_next = stable_n_d && !stable_n;
    wire press_prev = stable_p_d && !stable_p;
    wire press_auto = stable_a_d && !stable_a;

    // ---------------- auto slideshow timer ----------------
    reg [29:0] auto_cnt;
    reg scan_done_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) scan_done_d <= 1'b0;
        else scan_done_d <= scan_done;
    end
    wire scan_start = scan_done && !scan_done_d;

    wire [3:0] idx4 = {1'b0, load_index};
    wire [3:0] next4 = (idx4 + 4'd1 >= bmp_count) ? 4'd0 : (idx4 + 4'd1);
    wire [3:0] prev4 = (idx4 == 4'd0) ? (bmp_count - 4'd1) : (idx4 - 4'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_req <= 1'b0;
            load_index <= 3'd0;
            auto_en <= 1'b1;
            auto_cnt <= 30'd0;
            dim <= 1'b0; dim_cnt <= 26'd0;
        end else begin
            load_req <= 1'b0;

            dim<=1'b0;
            if (!stable_a_d && stable_a && !a_hold_done)
                auto_en <= ~auto_en;

            if (scan_start) begin
                load_index <= 3'd0;
                auto_cnt <= 30'd0;
            end else if (press_next && stable_p && !bright_mode && scan_done && !busy && bmp_count > 4'd1 && !dim) begin
                load_index <= next4[2:0];
                load_req   <= 1'b1;
                dim_cnt    <= 26'd0;
                auto_cnt   <= 30'd0;
            end else if (press_prev && stable_n && !bright_mode && scan_done && !busy && bmp_count > 4'd1 && !dim) begin
                load_index <= prev4[2:0];
                load_req   <= 1'b1;
                dim_cnt    <= 26'd0;
                auto_cnt   <= 30'd0;
            end else if (auto_en && scan_done && !busy && bmp_count > 4'd1 && !dim) begin
                if (auto_cnt == 30'd624_999_999) begin
                    load_index <= next4[2:0];
                    load_req   <= 1'b1;
                    dim_cnt    <= 26'd0;
                    auto_cnt   <= 30'd0;
                end else begin
                    auto_cnt <= auto_cnt + 30'd1;
                end
            end else begin
                auto_cnt <= 30'd0;
            end
        end
    end
    // ---------------- brightness mode: long press KEY4 toggles, then
    // KEY2/KEY3 adjust the brightness (with auto repeat) ----------------
    reg [26:0] hold_a;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hold_a      <= 27'd0;
            a_hold_done <= 1'b0;
            bright_mode <= 1'b0;
            bright      <= 5'd16;
        end else begin
            if (!stable_a) begin
                if (!a_hold_done) begin
                    if (hold_a == 27'd40_000_000) begin   // 0.8 s
                        a_hold_done <= 1'b1;
                        bright_mode <= ~bright_mode;
                    end else begin
                        hold_a <= hold_a + 27'd1;
                    end
                end
            end else begin
                hold_a      <= 27'd0;
                a_hold_done <= 1'b0;
            end

            if (bright_mode) begin
                if (press_next && stable_p) begin
                    if (bright < 5'd16) bright <= bright + 5'd1;
                end else if (press_prev && stable_n) begin
                    if (bright > 5'd4) bright <= bright - 5'd1;
                end
            end
        end
    end

    // slideshow progress 0..610 (auto_cnt / 2^20)
    assign progress = auto_cnt[29:20];
endmodule



