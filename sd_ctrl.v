`timescale 1ns/1ps
// SD card SPI controller: init + single-sector read
// SPI init ~200kHz, data read 12.5MHz
module sd_ctrl(
    input  wire clk,
    input  wire rst_n,
    output wire sd_clk,
    output wire sd_cmd,
    output wire sd_cs_n,
    input  wire sd_dat0,
    output reg  sd_ready,
    input  wire rd_req,
    input  wire [31:0] rd_sector,
    output reg  [7:0]  rd_data,
    output reg         rd_valid,
    output reg         rd_done,
    output reg  [3:0]  error_code
);

    // ---------------- SPI byte engine ----------------
    reg  [7:0] div;
    reg        spi_start;
    reg  [7:0] spi_tx;
    wire       spi_busy, spi_done;
    wire [7:0] spi_rx;
    wire       sclk, mosi;

    spi_byte u_spi(
        .clk(clk), .rst_n(rst_n),
        .start(spi_start), .tx_data(spi_tx), .div(div),
        .sclk(sclk), .mosi(mosi), .miso(sd_dat0),
        .busy(spi_busy), .done(spi_done), .rx_data(spi_rx)
    );

    reg cs_n;
    assign sd_clk  = sclk;
    assign sd_cmd  = mosi;
    assign sd_cs_n = cs_n;

    localparam [4:0]
        S_POWER        = 5'd0,
        S_POWER_WAIT   = 5'd1,
        S_CMD0         = 5'd2,
        S_SEND         = 5'd3,
        S_R1           = 5'd4,
        S_CMD0_CHECK   = 5'd5,
        S_CMD8         = 5'd6,
        S_CMD8_DATA    = 5'd7,
        S_CMD8_CHECK   = 5'd8,
        S_ACMD41_55    = 5'd9,
        S_ACMD41       = 5'd10,
        S_ACMD41_CHECK = 5'd11,
        S_CMD58        = 5'd12,
        S_CMD58_DATA   = 5'd13,
        S_CMD58_CHECK  = 5'd14,
        S_IDLE         = 5'd15,
        S_CMD17        = 5'd16,
        S_TOKEN        = 5'd17,
        S_DATA         = 5'd18,
        S_CRC          = 5'd19,
        S_ERR          = 5'd20;

    reg [4:0] state, next_state;
    reg [47:0] cmd_buf, cmd_sr;
    reg [2:0] byte_idx;
    reg [7:0] r1;
    reg [7:0] retry;
    reg [15:0] acmd_retry, token_retry;
    reg [1:0] read_idx, crc_cnt;
    reg [31:0] data_buf;
    reg [3:0] power_cnt;
    reg [24:0] pwr_delay;
    reg first;
    reg [9:0] data_cnt;
    reg [31:0] sector_lat;
    reg sdhc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_POWER;
            cs_n <= 1'b1;
            div <= 8'd250;
            spi_start <= 1'b0;
            spi_tx <= 8'hFF;
            cmd_buf <= 48'd0;
            cmd_sr <= 48'd0;
            byte_idx <= 3'd0;
            r1 <= 8'hFF;
            retry <= 8'd0;
            acmd_retry <= 16'd0;
            token_retry <= 16'd0;
            read_idx <= 2'd0;
            crc_cnt <= 2'd0;
            data_buf <= 32'd0;
            power_cnt <= 4'd0;
            pwr_delay <= 25'd0;
            first <= 1'b0;
            data_cnt <= 10'd0;
            sector_lat <= 32'd0;
            sdhc <= 1'b1;
            sd_ready <= 1'b0;
            rd_data <= 8'd0;
            rd_valid <= 1'b0;
            rd_done <= 1'b0;
            error_code <= 4'd0;
        end else begin
            spi_start <= 1'b0;
            rd_valid <= 1'b0;
            rd_done <= 1'b0;

            case (state)
            S_POWER: begin
                cs_n <= 1'b1;
                if (pwr_delay != 25'h1FFFFFF) begin
                    pwr_delay <= pwr_delay + 25'd1;
                end else if (!spi_busy) begin
                    if (power_cnt == 4'd10) begin
                        cs_n <= 1'b0;
                        state <= S_CMD0;
                    end else begin
                        spi_start <= 1'b1;
                        spi_tx <= 8'hFF;
                        power_cnt <= power_cnt + 4'd1;
                        state <= S_POWER_WAIT;
                    end
                end
            end

            S_POWER_WAIT: if (spi_done) state <= S_POWER;

            S_CMD0: begin
                cs_n <= 1'b0;
                cmd_buf <= {8'h40, 32'h00000000, 8'h95};
                cmd_sr  <= {32'h00000000, 8'h95, 8'h00};
                spi_tx  <= 8'h40;
                spi_start <= 1'b1;
                byte_idx <= 3'd0;
                next_state <= S_CMD0_CHECK;
                state <= S_SEND;
            end

            S_SEND: begin
                if (spi_done) begin
                    if (byte_idx == 3'd5) begin
                        spi_start <= 1'b1;
                        spi_tx <= 8'hFF;
                        retry <= 8'd0;
                        state <= S_R1;
                    end else begin
                        byte_idx <= byte_idx + 3'd1;
                        spi_tx <= cmd_sr[47:40];
                        cmd_sr <= {cmd_sr[39:0], 8'h00};
                        spi_start <= 1'b1;
                    end
                end
            end

            S_R1: begin
                if (spi_done) begin
                    if (spi_rx != 8'hFF) begin
                        r1 <= spi_rx;
                        state <= next_state;
                    end else if (retry == 8'd63) begin
                        error_code <= 4'd1;
                        state <= S_ERR;
                    end else begin
                        retry <= retry + 8'd1;
                        spi_start <= 1'b1;
                        spi_tx <= 8'hFF;
                    end
                end
            end

            S_CMD0_CHECK: begin
                if (r1 == 8'h01) state <= S_CMD8;
                else begin error_code <= 4'd1; state <= S_ERR; end
            end

            S_CMD8: begin
                cmd_buf <= {8'h48, 32'h000001AA, 8'h87};
                cmd_sr  <= {32'h000001AA, 8'h87, 8'h00};
                spi_tx  <= 8'h48;
                spi_start <= 1'b1;
                byte_idx <= 3'd0;
                read_idx <= 2'd0;
                data_buf <= 32'd0;
                first <= 1'b1;
                next_state <= S_CMD8_DATA;
                state <= S_SEND;
            end

            S_CMD8_DATA: begin
                if (first) begin
                    first <= 1'b0;
                    spi_start <= 1'b1;
                    spi_tx <= 8'hFF;
                end else if (spi_done) begin
                    data_buf <= {data_buf[23:0], spi_rx};
                    if (read_idx == 2'd3) state <= S_CMD8_CHECK;
                    else begin
                        read_idx <= read_idx + 2'd1;
                        spi_start <= 1'b1;
                        spi_tx <= 8'hFF;
                    end
                end
            end

            S_CMD8_CHECK: begin
                if (data_buf[11:0] == 12'h1AA) state <= S_ACMD41_55;
                else begin error_code <= 4'd2; state <= S_ERR; end
            end

            S_ACMD41_55: begin
                cmd_buf <= {8'h77, 32'h00000000, 8'hFF};
                cmd_sr  <= {32'h00000000, 8'hFF, 8'h00};
                spi_tx  <= 8'h77;
                spi_start <= 1'b1;
                byte_idx <= 3'd0;
                first <= 1'b0;
                next_state <= S_ACMD41;
                state <= S_SEND;
            end

            S_ACMD41: begin
                cmd_buf <= {8'h69, 32'h40000000, 8'hFF};
                cmd_sr  <= {32'h40000000, 8'hFF, 8'h00};
                spi_tx  <= 8'h69;
                spi_start <= 1'b1;
                byte_idx <= 3'd0;
                next_state <= S_ACMD41_CHECK;
                state <= S_SEND;
            end

            S_ACMD41_CHECK: begin
                if (r1 == 8'h00) begin
                    state <= S_CMD58;
                end else if (acmd_retry == 16'd2000) begin
                    error_code <= 4'd3;
                    state <= S_ERR;
                end else begin
                    acmd_retry <= acmd_retry + 16'd1;
                    state <= S_ACMD41_55;
                end
            end

            S_CMD58: begin
                cmd_buf <= {8'h7A, 32'h00000000, 8'hFF};
                cmd_sr  <= {32'h00000000, 8'hFF, 8'h00};
                spi_tx  <= 8'h7A;
                spi_start <= 1'b1;
                byte_idx <= 3'd0;
                read_idx <= 2'd0;
                data_buf <= 32'd0;
                first <= 1'b1;
                next_state <= S_CMD58_DATA;
                state <= S_SEND;
            end

            S_CMD58_DATA: begin
                if (first) begin
                    first <= 1'b0;
                    spi_start <= 1'b1;
                    spi_tx <= 8'hFF;
                end else if (spi_done) begin
                    data_buf <= {data_buf[23:0], spi_rx};
                    if (read_idx == 2'd3) state <= S_CMD58_CHECK;
                    else begin
                        read_idx <= read_idx + 2'd1;
                        spi_start <= 1'b1;
                        spi_tx <= 8'hFF;
                    end
                end
            end

            S_CMD58_CHECK: begin
                sdhc <= data_buf[30];
                sd_ready <= 1'b1;
                state <= S_IDLE;
            end

            S_IDLE: begin
                if (rd_req) begin
                    sector_lat <= rd_sector;
                    state <= S_CMD17;
                end
            end

            S_CMD17: begin
                div <= 8'd5;
                cmd_buf <= {8'h51, sector_lat, 8'hFF};
                cmd_sr  <= {sector_lat, 8'hFF, 8'h00};
                spi_tx  <= 8'h51;
                spi_start <= 1'b1;
                byte_idx <= 3'd0;
                token_retry <= 16'd0;
                first <= 1'b1;
                next_state <= S_TOKEN;
                state <= S_SEND;
            end

            S_TOKEN: begin
                if (first) begin
                    first <= 1'b0;
                    spi_start <= 1'b1;
                    spi_tx <= 8'hFF;
                end else if (spi_done) begin
                    if (spi_rx == 8'hFE) begin
                        data_cnt <= 10'd0;
                        first <= 1'b1;
                        state <= S_DATA;
                    end else if (token_retry == 16'hFFFF) begin
                        error_code <= 4'd6;
                        state <= S_ERR;
                    end else begin
                        token_retry <= token_retry + 16'd1;
                        spi_start <= 1'b1;
                        spi_tx <= 8'hFF;
                    end
                end
            end

            S_DATA: begin
                if (first) begin
                    first <= 1'b0;
                    spi_start <= 1'b1;
                    spi_tx <= 8'hFF;
                end else if (spi_done) begin
                    rd_data <= spi_rx;
                    rd_valid <= 1'b1;
                    if (data_cnt == 10'd511) begin
                        crc_cnt <= 2'd0;
                        first <= 1'b1;
                        state <= S_CRC;
                    end else begin
                        data_cnt <= data_cnt + 10'd1;
                        spi_start <= 1'b1;
                        spi_tx <= 8'hFF;
                    end
                end
            end

            S_CRC: begin
                if (first) begin
                    first <= 1'b0;
                    spi_start <= 1'b1;
                    spi_tx <= 8'hFF;
                end else if (spi_done) begin
                    if (crc_cnt == 2'd1) begin
                        rd_done <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        crc_cnt <= crc_cnt + 2'd1;
                        spi_start <= 1'b1;
                        spi_tx <= 8'hFF;
                    end
                end
            end

            S_ERR: begin
                cs_n <= 1'b1;
            end

            default: state <= S_ERR;
            endcase
        end
    end

endmodule


module spi_byte(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [7:0] tx_data,
    input  wire [7:0] div,
    output reg  sclk,
    output reg  mosi,
    input  wire miso,
    output reg  busy,
    output reg  done,
    output reg  [7:0] rx_data
);
    localparam IDLE = 2'd0, ACT = 2'd1, FIN = 2'd2;
    reg [1:0] st;
    reg [7:0] cnt;
    reg [7:0] tx_sr, rx_sr;
    reg [3:0] bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE;
            sclk <= 1'b0;
            mosi <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
            cnt <= 8'd0;
            bit_cnt <= 4'd0;
            tx_sr <= 8'hFF;
            rx_sr <= 8'h00;
            rx_data <= 8'hFF;
        end else begin
            done <= 1'b0;
            case (st)
            IDLE: begin
                sclk <= 1'b0;
                busy <= 1'b0;
                if (start) begin
                    tx_sr <= tx_data;
                    mosi <= tx_data[7];
                    bit_cnt <= 4'd0;
                    cnt <= 8'd0;
                    busy <= 1'b1;
                    st <= ACT;
                end
            end

            ACT: begin
                if (cnt == div - 8'd1) begin
                    cnt <= 8'd0;
                    if (!sclk) begin
                        sclk <= 1'b1;
                        rx_sr <= {rx_sr[6:0], miso};
                        if (bit_cnt == 4'd7) st <= FIN;
                        else bit_cnt <= bit_cnt + 4'd1;
                    end else begin
                        sclk <= 1'b0;
                        tx_sr <= {tx_sr[6:0], 1'b0};
                        mosi <= tx_sr[6];
                    end
                end else begin
                    cnt <= cnt + 8'd1;
                end
            end

            FIN: begin
                if (cnt == div - 8'd1) begin
                    cnt <= 8'd0;
                    sclk <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    rx_data <= rx_sr;
                    st <= IDLE;
                end else begin
                    cnt <= cnt + 8'd1;
                end
            end

            default: st <= IDLE;
            endcase
        end
    end
endmodule

