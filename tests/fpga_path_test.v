// Output-path test image for the Go Board (same pins as go_board.pcf).
//   SW1 : source   0 = mic   1 = 1 kHz triangle (+-8192)   2 = DC +8192   3 = DC -8192   (cycles)
//   SW2 : denoiser  off (threshold 0)  <->  on (threshold = 2^(LAMBDA_SEL-1))
//   SW3 / SW4 : digital gain up / down (0..8, default 4, mic mode only)
//   Left 7-seg  : loudest sample INTO the denoiser, bit position 0..F (hex), last ~0.17 s
//   Right 7-seg : loudest sample OUT of the denoiser (what feeds the DAC), same scale
//   LED1 : blinks = DAC self-check OK;  solid on = the 1-bit stream does not match its input
//   LED2, LED3 : source number (LED3 LED2 as binary)      LED4 : denoiser on
// Expected pin voltage (3.3 V rail) with a multimeter on the DAC pin side of R1:
//   source 2 (DC +8192): 3.3*40960/65536 = 2.06 V     source 3 (DC -8192): 3.3*24576/65536 = 1.24 V
module out_test_top #(
    parameter LAMBDA_SEL = 8,            // threshold 128 counts when the denoiser is on
    parameter WIN_LOG2   = 22,           // meter window in clocks (2^22 = 168 ms)
    parameter DEB        = 19'd499999    // 20 ms debounce
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

    // ---------------- buttons ----------------
    wire [3:0] press;
    debounce_press #(.LIMIT(DEB)) d1 (.clk(clk), .in(i_Switch_1), .press(press[0]));
    debounce_press #(.LIMIT(DEB)) d2 (.clk(clk), .in(i_Switch_2), .press(press[1]));
    debounce_press #(.LIMIT(DEB)) d3 (.clk(clk), .in(i_Switch_3), .press(press[2]));
    debounce_press #(.LIMIT(DEB)) d4 (.clk(clk), .in(i_Switch_4), .press(press[3]));

    reg [1:0] src = 2'd0;  reg dn_on = 1'b0;  reg [3:0] gain_sel = 4'd4;
    always @(posedge clk) begin
        if (press[0]) src   <= src + 2'd1;
        if (press[1]) dn_on <= ~dn_on;
        if (press[2] && gain_sel < 4'd8) gain_sel <= gain_sel + 4'd1;
        if (press[3] && gain_sel > 4'd0) gain_sel <= gain_sel - 4'd1;
    end

    // ---------------- sources ----------------
    wire [23:0] mic_sample;  wire mic_valid;
    wire signed [15:0] mic_s;  wire mic_s_valid;
    i2s_rx #(.HALF(12)) rx (.clk(clk), .rst_n(rst_n), .sd(i_Mic_SD), .sck(o_Mic_SCK), .ws(o_Mic_WS),
                                           .sample(mic_sample), .sample_valid(mic_valid));
    input_gain gain (.clk(clk), .rst_n(rst_n), .sample(mic_sample), .sample_valid(mic_valid),
                     .gain_sel(gain_sel), .s_in(mic_s), .s_in_valid(mic_s_valid));

    // test tone: 16-bit phase, 4026/65536 * fs(16276 Hz) = 1.0 kHz triangle; updated with the mic strobe so it
    // lines up with s_in_valid
    reg [15:0] phase = 16'd0;
    reg signed [15:0] tone = 16'sd0;
    wire [14:0] tri_w = phase[15] ? ~phase[14:0] : phase[14:0];              // 0..32767
    wire signed [15:0] trc = $signed({1'b0, tri_w}) - 16'sd16384;          // +-16384
    always @(posedge clk) if (mic_valid) begin
        phase <= phase + 16'd4026;
        tone  <= trc >>> 1;                                               // +-8192
    end

    reg signed [15:0] s_mux;
    always @* case (src)
        2'd0: s_mux = mic_s;
        2'd1: s_mux = tone;
        2'd2: s_mux = 16'sd8192;
        default: s_mux = -16'sd8192;
    endcase

    // ---------------- denoiser + DAC (same blocks as wavelet_denoising_top, but s_out is visible) ----------------
    wire [15:0] lambda = dn_on ? (16'd1 << (LAMBDA_SEL - 1)) : 16'd0;
    wire signed [15:0] approx;  wire signed [16:0] detail, detail_thresh;  wire odd_pending;
    wire signed [15:0] s_out;   wire s_out_valid;
    lifting_haar #(.WIDTH(16)) lwt (.clk(clk), .rst_n(rst_n), .s_in(s_mux), .s_in_valid(mic_s_valid),
        .approx(approx), .detail(detail), .odd_pending(odd_pending));
    threshold #(.WIDTH(16)) thresh (.lambda(lambda), .detail(detail), .detail_thresh(detail_thresh));
    inverse_lwt #(.WIDTH(16)) inv (.clk(clk), .rst_n(rst_n), .approx(approx), .detail(detail_thresh),
        .odd_pending(odd_pending), .s_out(s_out), .s_out_valid(s_out_valid));
    wire [15:0] dac_in = {~s_out[15], s_out[14:0]};
    delta_sigma_dac #(.WIDTH(16)) dac (.clk(clk), .rst_n(rst_n), .dac_in(dac_in), .dac_out(o_Audio_Out));

    // ---------------- level meters (peak magnitude over 2^WIN_LOG2 clocks) ----------------
    reg [WIN_LOG2-1:0] wcnt = 0;
    reg [15:0] pk_in = 0, pk_out = 0, sh_in = 0, sh_out = 0;
    wire [15:0] m_in  = s_mux[15] ? ~s_mux : s_mux;
    wire [15:0] m_out = s_out[15] ? ~s_out : s_out;
    always @(posedge clk) begin
        wcnt <= wcnt + 1'b1;
        if (&wcnt) begin
            sh_in  <= (m_in  > pk_in)  ? m_in  : pk_in;   pk_in  <= 0;
            sh_out <= (m_out > pk_out) ? m_out : pk_out;  pk_out <= 0;
        end else begin
            if (m_in  > pk_in)  pk_in  <= m_in;
            if (m_out > pk_out) pk_out <= m_out;
        end
    end
    reg [3:0] b_in, b_out;  integer i;
    always @* begin
        b_in = 4'd0;  b_out = 4'd0;
        for (i = 0; i < 16; i = i + 1) begin
            if (sh_in[i])  b_in  = i[3:0];
            if (sh_out[i]) b_out = i[3:0];
        end
    end

    // ---------------- DAC self-check: ones density of the 1-bit stream vs. the average of its input ----------------
    // first-order loop => | 2^16*ones - sum(dac_in) | < 2^17 over any window of 2^16 clocks
    reg [15:0] dcnt = 0;  reg [16:0] ones = 0;  reg [31:0] dsum = 0;  reg dac_ok = 1'b1;  reg armed = 1'b0;   // first window straddles reset, so it is ignored
    wire signed [33:0] ddiff = $signed({1'b0, ones, 16'b0}) - $signed({2'b0, dsum});
    always @(posedge clk) begin
        dcnt <= dcnt + 1'b1;
        if (&dcnt) begin
            armed <= 1'b1;
            if (armed) dac_ok <= (ddiff > -34'sd262144) && (ddiff < 34'sd262144);
            ones <= 0;  dsum <= 0;
        end else begin
            ones <= ones + o_Audio_Out;
            dsum <= dsum + dac_in;
        end
    end

    // ---------------- indicators ----------------
    reg [24:0] hb = 0;
    always @(posedge clk) hb <= hb + 1'b1;
    assign o_LED_1 = dac_ok ? hb[24] : 1'b1;
    assign o_LED_2 = src[0];
    assign o_LED_3 = src[1];
    assign o_LED_4 = dn_on;

    wire [6:0] s1, s2;
    hex_to_7seg h1 (.value(b_in),  .seg(s1));
    hex_to_7seg h2 (.value(b_out), .seg(s2));
    assign {o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G} = ~s1;
    assign {o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G} = ~s2;
endmodule