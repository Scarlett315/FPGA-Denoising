// Voice playback through the wavelet denoiser: a 1 s clip stored in the FPGA (ROM) -> volume -> lifting Haar ->
// soft threshold -> inverse lifting -> sigma-delta DAC on Pmod pin 8 (FPGA 79).  No microphone is used.
//   The clip plays for 1.0 s, then 0.5 s of silence, then repeats.
//   SW1 : volume   0 = muted   1 = +-2032   2 = +-4064   3 = +-8128   4 = +-16256 counts of 32768 (default 2)
//   SW2 : denoiser on / off.  Off = threshold 0 (exact pass-through, same one-sample lag), so A/B is fair.
//   SW3 : threshold up   SW4 : threshold down.   threshold = 0 for index 0, else 2^(index-1) counts (16-bit domain)
//   Left 7-seg : threshold index (hex 0..F)   Right 7-seg : volume (0..4)
//   LED1 heartbeat, LED2 clip is playing, LED3 denoiser on, LED4 off.
// Change the clip: edit the $readmemh line (clean / noisy 15, 10, 5 dB files from test_audio/).
// Needs lifting_haar.v, threshold.v, inverse_lwt.v, delta_sigma_dac.v in the project.
module voice_dn_top #(
    parameter INIT_VOL = 2,
    parameter INIT_SEL = 10,                // threshold index at power-up (10 = 512 counts)
    parameter INIT_ON  = 1,
    parameter DIV      = 1536,              // clocks per sample: 25 MHz / 3072 = 8138 Hz
    parameter GAP      = 4096,              // silent samples between repeats (0.5 s)
    parameter DEB      = 19'd499999
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

    // mic pins idle (no dummy clock in this image)
    assign o_Mic_SCK = 1'b0;
    assign o_Mic_WS  = 1'b0;

    // ---- buttons ----
    wire p1, p2, p3, p4;
    vd_deb #(.LIMIT(DEB)) d1 (.clk(clk), .in(i_Switch_1), .press(p1));
    vd_deb #(.LIMIT(DEB)) d2 (.clk(clk), .in(i_Switch_2), .press(p2));
    vd_deb #(.LIMIT(DEB)) d3 (.clk(clk), .in(i_Switch_3), .press(p3));
    vd_deb #(.LIMIT(DEB)) d4 (.clk(clk), .in(i_Switch_4), .press(p4));
    reg [2:0] vol = INIT_VOL;
    reg [3:0] sel = INIT_SEL;
    reg       dn_on = INIT_ON;
    always @(posedge clk) begin
        if (p1) vol <= (vol == 3'd4) ? 3'd0 : vol + 3'd1;
        if (p2) dn_on <= ~dn_on;
        if (p3 && sel != 4'd15) sel <= sel + 4'd1;
        if (p4 && sel != 4'd0)  sel <= sel - 4'd1;
    end
    wire [15:0] lam_val = (sel == 4'd0) ? 16'd0 : (16'd1 << (sel - 4'd1));
    wire [15:0] lambda  = dn_on ? lam_val : 16'd0;

    // ---- sample ROM (16 block RAMs) ----
    reg [7:0] mem [0:8191];
    initial $readmemh("test_audio/voice16_hiss15.hex", mem);
    reg [12:0] addr = 13'd0;
    reg [7:0]  rdata = 8'd0;
    always @(posedge clk) rdata <= mem[addr];

    // ---- playback sequencer: 8192 samples of clip, then GAP samples of silence (both even, so pairs stay aligned) ----
    reg [11:0] dcnt = 12'd0;
    reg [13:0] gcnt = 14'd0;
    reg        in_gap = 1'b0;
    wire       tick = (dcnt == DIV - 1);
    always @(posedge clk) begin
        dcnt <= tick ? 12'd0 : dcnt + 12'd1;
        if (tick) begin
            if (!in_gap) begin
                addr <= addr + 13'd1;
                if (addr == 13'd8191) begin in_gap <= 1'b1; gcnt <= 14'd0; end
            end else begin
                gcnt <= gcnt + 14'd1;
                if (gcnt == GAP - 1) in_gap <= 1'b0;
            end
        end
    end

    wire signed [15:0] raw = {rdata, 8'd0};
    reg  signed [15:0] scaled;
    always @* case (vol)
        3'd1: scaled = raw >>> 4;
        3'd2: scaled = raw >>> 3;
        3'd3: scaled = raw >>> 2;
        3'd4: scaled = raw >>> 1;
        default: scaled = 16'sd0;
    endcase
    reg signed [15:0] s = 16'sd0;
    reg               s_valid = 1'b0;           // one-clock strobe, the cycle after s changes
    always @(posedge clk) begin
        if (tick) s <= in_gap ? 16'sd0 : scaled;
        s_valid <= tick;
    end

    // ---- wavelet denoiser (your modules) ----
    wire signed [15:0] approx, s_out;
    wire signed [16:0] detail, detail_thresh;
    wire odd_pending, s_out_valid;
    lifting_haar #(.WIDTH(16)) lwt (.clk(clk), .rst_n(rst_n), .s_in(s), .s_in_valid(s_valid),
        .approx(approx), .detail(detail), .odd_pending(odd_pending));
    threshold #(.WIDTH(16)) thresh (.lambda(lambda), .detail(detail), .detail_thresh(detail_thresh));
    inverse_lwt #(.WIDTH(16)) inv (.clk(clk), .rst_n(rst_n), .approx(approx), .detail(detail_thresh),
        .odd_pending(odd_pending), .s_out(s_out), .s_out_valid(s_out_valid));

    delta_sigma_dac #(.WIDTH(16)) dac (.clk(clk), .rst_n(rst_n),
        .dac_in({~s_out[15], s_out[14:0]}), .dac_out(o_Audio_Out));

    reg [24:0] hb = 25'd0;
    always @(posedge clk) hb <= hb + 25'd1;
    assign o_LED_1 = hb[24];
    assign o_LED_2 = ~in_gap & (vol != 3'd0);
    assign o_LED_3 = dn_on;
    assign o_LED_4 = 1'b0;

    wire [6:0] s1, s2;
    vd_hex7 h1 (.value(sel), .seg(s1));
    vd_hex7 h2 (.value({1'b0, vol}), .seg(s2));
    assign {o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G} = ~s1;
    assign {o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G} = ~s2;
endmodule

module vd_deb #(parameter LIMIT = 19'd499999) (input wire clk, input wire in, output reg press);
    reg s0 = 0, s1 = 0, stable = 0; reg [18:0] cnt = 0;
    always @(posedge clk) begin
        s0 <= in; s1 <= s0; press <= 1'b0;
        if (s1 == stable) cnt <= 0;
        else if (cnt == LIMIT) begin stable <= s1; cnt <= 0; if (s1) press <= 1'b1; end
        else cnt <= cnt + 19'd1;
    end
endmodule

module vd_hex7 (input wire [3:0] value, output reg [6:0] seg);   // seg = {A,B,C,D,E,F,G}, 1 = lit
    always @* case (value)
        4'h0: seg = 7'b1111110; 4'h1: seg = 7'b0110000; 4'h2: seg = 7'b1101101; 4'h3: seg = 7'b1111001;
        4'h4: seg = 7'b0110011; 4'h5: seg = 7'b1011011; 4'h6: seg = 7'b1011111; 4'h7: seg = 7'b1110000;
        4'h8: seg = 7'b1111111; 4'h9: seg = 7'b1111011; 4'hA: seg = 7'b1110111; 4'hB: seg = 7'b0011111;
        4'hC: seg = 7'b1001110; 4'hD: seg = 7'b0111101; 4'hE: seg = 7'b1001111; 4'hF: seg = 7'b1000111;
    endcase
endmodule