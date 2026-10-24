// Pass-through test: mic -> I2S receiver -> digital gain -> sigma-delta DAC pin. No wavelet, no threshold.
//   SW1 / SW2 : gain up / down (0..8, default 2 = x4)         -> left  7-seg
//   Right 7-seg : loudest sample after gain, bit position 0..F (hex), last ~0.17 s
//   LED1 heartbeat, LED2 = signal is clipping (hit +-full scale), LED3 = mic samples are not all zero, LED4 off
// Works with either version of i2s_rx.v (reads the left slot: tie the mic's L/R pin to GND).
module passthru_top #(
    parameter INIT_GAIN = 2,
    parameter WIN_LOG2  = 22,
    parameter DEB       = 19'd499999
) (
    input  wire i_Clk,
    input  wire i_Switch_1, i_Switch_2, i_Switch_3, i_Switch_4,
    input  wire i_Mic_SD,
    output wire o_Mic_SCK,
    output wire o_Mic_WS,
    output wire o_Audio_Out,
    output wire o_LED_1, o_LED_2, o_LED_3, o_LED_4,
    output wire o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G,
    output wire o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G
);
    wire clk = i_Clk;
    reg [3:0] por = 4'd0;
    always @(posedge clk) if (!(&por)) por <= por + 4'd1;
    wire rst_n = &por;

    wire p1, p2;
    pt_deb #(.LIMIT(DEB)) d1 (.clk(clk), .in(i_Switch_1), .press(p1));
    pt_deb #(.LIMIT(DEB)) d2 (.clk(clk), .in(i_Switch_2), .press(p2));
    reg [3:0] gain_sel = INIT_GAIN;
    always @(posedge clk) begin
        if (p1 && gain_sel < 4'd8) gain_sel <= gain_sel + 4'd1;
        if (p2 && gain_sel > 4'd0) gain_sel <= gain_sel - 4'd1;
    end

    wire [23:0] mic_sample;  wire mic_valid;
    wire signed [15:0] s_in; wire s_in_valid;
    i2s_rx #(.HALF(12)) rx (.clk(clk), .rst_n(rst_n), .sd(i_Mic_SD), .sck(o_Mic_SCK), .ws(o_Mic_WS),
                            .sample(mic_sample), .sample_valid(mic_valid));
    input_gain gain (.clk(clk), .rst_n(rst_n), .sample(mic_sample), .sample_valid(mic_valid),
                     .gain_sel(gain_sel), .s_in(s_in), .s_in_valid(s_in_valid));

    // s_in holds its value between samples -> straight into the DAC (two's complement -> offset binary)
    delta_sigma_dac #(.WIDTH(16)) dac (.clk(clk), .rst_n(rst_n),
        .dac_in({~s_in[15], s_in[14:0]}), .dac_out(o_Audio_Out));

    // ---- meter ----
    reg [WIN_LOG2-1:0] wcnt = 0;
    reg [15:0] pk = 0, shown = 0;
    reg clip_seen = 0, clip_led = 0, nz_seen = 0, nz_led = 0;
    wire [15:0] mag = s_in[15] ? ~s_in : s_in;
    always @(posedge clk) begin
        wcnt <= wcnt + 1'b1;
        if (s_in == 16'sh7FFF || s_in == 16'sh8000) clip_seen <= 1'b1;
        if (mic_sample != 24'd0) nz_seen <= 1'b1;
        if (&wcnt) begin
            shown <= (mag > pk) ? mag : pk;  pk <= 0;
            clip_led <= clip_seen;  clip_seen <= 0;
            nz_led <= nz_seen;      nz_seen <= 0;
        end else if (mag > pk) pk <= mag;
    end
    reg [3:0] bpos;  integer i;
    always @* begin bpos = 4'd0; for (i = 0; i < 16; i = i + 1) if (shown[i]) bpos = i[3:0]; end

    reg [24:0] hb = 0;
    always @(posedge clk) hb <= hb + 1'b1;
    assign o_LED_1 = hb[24];
    assign o_LED_2 = clip_led;
    assign o_LED_3 = nz_led;
    assign o_LED_4 = 1'b0;

    wire [6:0] s1, s2;
    pt_hex7 h1 (.value(gain_sel), .seg(s1));
    pt_hex7 h2 (.value(bpos),     .seg(s2));
    assign {o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G} = ~s1;
    assign {o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G} = ~s2;
endmodule

module pt_deb #(parameter LIMIT = 19'd499999) (input wire clk, input wire in, output reg press);
    reg s0 = 0, s1 = 0, stable = 0; reg [18:0] cnt = 0;
    always @(posedge clk) begin
        s0 <= in; s1 <= s0; press <= 1'b0;
        if (s1 == stable) cnt <= 0;
        else if (cnt == LIMIT) begin stable <= s1; cnt <= 0; if (s1) press <= 1'b1; end
        else cnt <= cnt + 19'd1;
    end
endmodule

module pt_hex7 (input wire [3:0] value, output reg [6:0] seg);   // {A..G}, active high
    always @* case (value)
        4'h0: seg = 7'b1111110;  4'h1: seg = 7'b0110000;  4'h2: seg = 7'b1101101;  4'h3: seg = 7'b1111001;
        4'h4: seg = 7'b0110011;  4'h5: seg = 7'b1011011;  4'h6: seg = 7'b1011111;  4'h7: seg = 7'b1110000;
        4'h8: seg = 7'b1111111;  4'h9: seg = 7'b1111011;  4'hA: seg = 7'b1110111;  4'hB: seg = 7'b0011111;
        4'hC: seg = 7'b1001110;  4'hD: seg = 7'b0111101;  4'hE: seg = 7'b1001111;  4'hF: seg = 7'b1000111;
    endcase
endmodule