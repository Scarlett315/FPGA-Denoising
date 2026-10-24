// I2S alignment check for the INMP441 on the Go Board (same pins as go_board.pcf).
// Captures the full 32-bit slot and looks at the 8 padding bits that should always be 0.
//   SW1 : capture start offset 0..3 (default 1 = standard I2S: MSB one SCK after the WS edge)
//   Left 7-seg  : start offset in use
//   Right 7-seg : 0  = padding bits all zero (aligned)
//                 1..8 = highest padding bit that was ever 1 in the last ~0.17 s, plus one (misaligned or noisy line)
//   LED1 heartbeat, LED2 = padding all zero, LED3 = data bits above the padding are not all zero (mic alive), LED4 off
// Offset 1 and 2 both show 0 for a correct mic (offset 2 just doubles the level); offset 0 should show non-zero.
module mic_align_top #(parameter WIN_LOG2 = 22, parameter DEB = 19'd499999) (
    input  wire i_Clk,
    input  wire i_Switch_1, i_Switch_2, i_Switch_3, i_Switch_4,
    input  wire i_Mic_SD,
    output reg  o_Mic_SCK,
    output wire o_Mic_WS,
    output wire o_Audio_Out,
    output wire o_LED_1, o_LED_2, o_LED_3, o_LED_4,
    output wire o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G,
    output wire o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G
);
    wire clk = i_Clk;
    assign o_Audio_Out = 1'b0;
    reg [3:0] por = 0; always @(posedge clk) if (!(&por)) por <= por + 1'b1;
    wire rst_n = &por;

    wire p1; al_deb #(.LIMIT(DEB)) d1 (.clk(clk), .in(i_Switch_1), .press(p1));
    reg [1:0] start = 2'd1;
    always @(posedge clk) if (p1) start <= start + 2'd1;

    // clock / frame generation identical to i2s_rx (HALF = 12)
    reg [7:0] div = 0;  reg [5:0] fc = 6'd63;  reg sd_m = 0, sd_s = 0;
    reg [31:0] sh = 0;  reg [31:0] word = 0;  reg word_v = 0;
    assign o_Mic_WS = fc[5];
    wire tick = (div == 8'd11);
    wire [5:0] first = {4'd0, start};
    wire [5:0] last  = first + 6'd31;
    always @(posedge clk) begin
        sd_m <= i_Mic_SD; sd_s <= sd_m; word_v <= 1'b0;
        if (!rst_n) begin div <= 0; o_Mic_SCK <= 0; fc <= 6'd63; end
        else begin
            div <= tick ? 8'd0 : div + 8'd1;
            if (tick) begin
                o_Mic_SCK <= ~o_Mic_SCK;
                if (o_Mic_SCK) fc <= fc + 6'd1;
                else if (fc >= first && fc <= last) begin
                    sh <= {sh[30:0], sd_s};
                    if (fc == last) begin word <= {sh[30:0], sd_s}; word_v <= 1'b1; end
                end
            end
        end
    end

    // window statistics: OR of padding bits, OR of sign-corrected data bits
    reg [WIN_LOG2-1:0] wc = 0;
    reg [7:0] pad_or = 0, pad_show = 0;  reg [23:0] dat_or = 0, dat_show = 0;
    wire [23:0] mag = word[31:8] ^ {24{word[31]}};
    always @(posedge clk) begin
        wc <= wc + 1'b1;
        if (&wc) begin pad_show <= pad_or | (word_v ? word[7:0] : 8'd0); dat_show <= dat_or; pad_or <= 0; dat_or <= 0; end
        else if (word_v) begin pad_or <= pad_or | word[7:0]; dat_or <= dat_or | mag; end
    end
    reg [3:0] padpos;  integer i;
    always @* begin padpos = 0; for (i = 0; i < 8; i = i + 1) if (pad_show[i]) padpos = i[3:0] + 4'd1; end

    reg [24:0] hb = 0; always @(posedge clk) hb <= hb + 1'b1;
    assign o_LED_1 = hb[24];
    assign o_LED_2 = (pad_show == 8'd0);
    assign o_LED_3 = (dat_show[23:2] != 0);
    assign o_LED_4 = 1'b0;

    wire [6:0] s1, s2;
    al_hex7 h1 (.value({2'b0, start}), .seg(s1));
    al_hex7 h2 (.value(padpos), .seg(s2));
    assign {o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G} = ~s1;
    assign {o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G} = ~s2;
endmodule

module al_deb #(parameter LIMIT = 19'd499999) (input wire clk, input wire in, output reg press);
    reg s0 = 0, s1 = 0, stable = 0; reg [18:0] cnt = 0;
    always @(posedge clk) begin
        s0 <= in; s1 <= s0; press <= 1'b0;
        if (s1 == stable) cnt <= 0;
        else if (cnt == LIMIT) begin stable <= s1; cnt <= 0; if (s1) press <= 1'b1; end
        else cnt <= cnt + 19'd1;
    end
endmodule
module al_hex7 (input wire [3:0] value, output reg [6:0] seg);
    always @* case (value)
        4'h0: seg = 7'b1111110;  4'h1: seg = 7'b0110000;  4'h2: seg = 7'b1101101;  4'h3: seg = 7'b1111001;
        4'h4: seg = 7'b0110011;  4'h5: seg = 7'b1011011;  4'h6: seg = 7'b1011111;  4'h7: seg = 7'b1110000;
        4'h8: seg = 7'b1111111;  default: seg = 7'b0000001;
    endcase
endmodule