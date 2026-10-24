// Mic level test that separates DC offset from real noise (same pins as go_board.pcf).
//   A slow DC tracker (about 2.5 Hz corner) is subtracted from every sample.
//   Display (two decimal digits) = highest set bit of the loudest |sample - DC| over ~0.25 s  (AC level, 0..23)
//   SW1 toggles the display to the DC offset itself: highest set bit of |DC| (LED4 on while showing DC)
//   LED1 heartbeat, LED2 SD toggling, LED3 AC level >= 4, LED4 showing DC
module mic_test_top #(parameter WIN_LOG2 = 12, parameter DEB = 19'd499999) (
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
    assign o_Audio_Out = 1'b0;
    reg [3:0] por = 0; always @(posedge clk) if (!(&por)) por <= por + 1'b1;
    wire rst_n = &por;
    wire p1; ac_deb #(.LIMIT(DEB)) d1 (.clk(clk), .in(i_Switch_1), .press(p1));
    reg show_dc = 1'b0; always @(posedge clk) if (p1) show_dc <= ~show_dc;

    wire [23:0] sample;  wire valid;
    i2s_rx #(.HALF(12)) rx (.clk(clk), .rst_n(rst_n), .sd(i_Mic_SD), .sck(o_Mic_SCK), .ws(o_Mic_WS),
                            .sample(sample), .sample_valid(valid));

    // DC tracker: acc ~ dc * 2^10
    reg signed [34:0] acc = 0;
    wire signed [34:0] sx  = {{11{sample[23]}}, sample};
    wire signed [34:0] dc  = acc >>> 10;
    wire signed [34:0] ac  = sx - dc;
    reg primed = 1'b0;   // first sample after power-up initialises the tracker, so there is no settling period
    always @(posedge clk) if (valid) begin
        primed <= 1'b1;
        acc <= primed ? (acc + sx - dc) : (sx <<< 10);
    end

    wire [34:0] ac_mag = ac[34] ? ~ac : ac;
    wire [34:0] dc_mag = dc[34] ? ~dc : dc;

    reg [23:0] pk = 0, shown_ac = 0;  reg [23:0] dc_show = 0;
    reg [WIN_LOG2-1:0] n = 0;
    wire [23:0] acm = ac_mag[23:0];
    always @(posedge clk) if (valid) begin
        n <= n + 1'b1;
        if (&n) begin shown_ac <= (acm > pk) ? acm : pk; pk <= 0; dc_show <= dc_mag[23:0]; end
        else if (acm > pk) pk <= acm;
    end

    wire [23:0] disp = show_dc ? dc_show : shown_ac;
    reg [4:0] msb; integer i;
    always @* begin msb = 0; for (i = 0; i < 24; i = i + 1) if (disp[i]) msb = i[4:0]; end

    reg sd_m = 0, sd_s = 0, sd_p = 0, sd_seen = 0, sd_live = 0; reg [20:0] sdw = 0;
    always @(posedge clk) begin
        sd_m <= i_Mic_SD; sd_s <= sd_m; sd_p <= sd_s;
        if (sd_s != sd_p) sd_seen <= 1;
        sdw <= sdw + 1'b1;
        if (&sdw) begin sd_live <= sd_seen; sd_seen <= 0; end
    end
    reg [24:0] hb = 0; always @(posedge clk) hb <= hb + 1'b1;
    assign o_LED_1 = hb[24];
    assign o_LED_2 = sd_live;
    assign o_LED_3 = (shown_ac >= 24'd4);
    assign o_LED_4 = show_dc;

    wire [3:0] tens = (msb >= 5'd20) ? 4'd2 : (msb >= 5'd10) ? 4'd1 : 4'd0;
    wire [3:0] ones = msb - ((tens == 4'd2) ? 5'd20 : (tens == 4'd1) ? 5'd10 : 5'd0);
    wire [6:0] s1, s2;
    ac_seg7 a (.value(tens), .seg(s1));  ac_seg7 b (.value(ones), .seg(s2));
    assign {o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G} = ~s1;
    assign {o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G} = ~s2;
endmodule

module ac_deb #(parameter LIMIT = 19'd499999) (input wire clk, input wire in, output reg press);
    reg s0 = 0, s1 = 0, stable = 0; reg [18:0] cnt = 0;
    always @(posedge clk) begin
        s0 <= in; s1 <= s0; press <= 1'b0;
        if (s1 == stable) cnt <= 0;
        else if (cnt == LIMIT) begin stable <= s1; cnt <= 0; if (s1) press <= 1'b1; end
        else cnt <= cnt + 19'd1;
    end
endmodule
module ac_seg7 (input wire [3:0] value, output reg [6:0] seg);
    always @* case (value)
        4'd0: seg = 7'b1111110; 4'd1: seg = 7'b0110000; 4'd2: seg = 7'b1101101; 4'd3: seg = 7'b1111001;
        4'd4: seg = 7'b0110011; 4'd5: seg = 7'b1011011; 4'd6: seg = 7'b1011111; 4'd7: seg = 7'b1110000;
        4'd8: seg = 7'b1111111; 4'd9: seg = 7'b1111011; default: seg = 7'b0000001;
    endcase
endmodule