// Filter / amplifier test image: no mic, no denoiser. Pmod pin 8 (FPGA pin 79, o_Audio_Out) carries a
// sigma-delta encoded sine wave so you can check the RC filter, volume pot and TDA2822 on their own.
//   SW1 : frequency   0=100 Hz  1=440 Hz  2=1 kHz  3=2 kHz  4=5 kHz        (left  7-seg)
//   SW2 : amplitude   0=off (mid-scale DC)  1=+-1024  2=+-2048  3=+-4096  4=+-8192 counts of 32768  (right 7-seg)
//   Peak voltage on the pin side of R1 = 3.3 V * amplitude/65536 :  1024 -> 52 mV, 2048 -> 103 mV, 4096 -> 207 mV, 8192 -> 413 mV
//   LED1 heartbeat, LED2 tone running.   Mic pins are held low; i_Mic_SD is unused.
module amp_test_top #(
    parameter INIT_F = 2,                   // starts at 1 kHz
    parameter INIT_A = 2,                   // starts at +-2048 (small, safe for the amp)
    parameter DEB    = 19'd499999
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
    assign o_Mic_SCK = 1'b0;
    assign o_Mic_WS  = 1'b0;

    reg [3:0] por = 4'd0;
    always @(posedge clk) if (!(&por)) por <= por + 4'd1;
    wire rst_n = &por;

    wire p1, p2;
    amp_deb #(.LIMIT(DEB)) d1 (.clk(clk), .in(i_Switch_1), .press(p1));
    amp_deb #(.LIMIT(DEB)) d2 (.clk(clk), .in(i_Switch_2), .press(p2));

    reg [2:0] fsel = INIT_F;
    reg [2:0] asel = INIT_A;
    always @(posedge clk) begin
        if (p1) fsel <= (fsel == 3'd4) ? 3'd0 : fsel + 3'd1;
        if (p2) asel <= (asel == 3'd4) ? 3'd0 : asel + 3'd1;
    end

    // sample tick 25 MHz / 512 = 48.83 kHz; phase step = f * 65536 / 48828
    reg [8:0]  tick  = 9'd0;
    reg [15:0] phase = 16'd0;
    reg signed [15:0] s = 16'sd0;
    reg [15:0] inc;
    always @* case (fsel)
        3'd0: inc = 16'd134;     //  100 Hz
        3'd1: inc = 16'd591;     //  440 Hz
        3'd2: inc = 16'd1342;    // 1000 Hz
        3'd3: inc = 16'd2684;    // 2000 Hz
        default: inc = 16'd6711; // 5000 Hz
    endcase

    reg signed [15:0] sine;
    always @* begin
        case (phase[15:9])
            7'd0: sine = 16'sd0;
            7'd1: sine = 16'sd804;
            7'd2: sine = 16'sd1606;
            7'd3: sine = 16'sd2404;
            7'd4: sine = 16'sd3196;
            7'd5: sine = 16'sd3981;
            7'd6: sine = 16'sd4756;
            7'd7: sine = 16'sd5519;
            7'd8: sine = 16'sd6270;
            7'd9: sine = 16'sd7005;
            7'd10: sine = 16'sd7723;
            7'd11: sine = 16'sd8423;
            7'd12: sine = 16'sd9102;
            7'd13: sine = 16'sd9759;
            7'd14: sine = 16'sd10393;
            7'd15: sine = 16'sd11002;
            7'd16: sine = 16'sd11585;
            7'd17: sine = 16'sd12139;
            7'd18: sine = 16'sd12664;
            7'd19: sine = 16'sd13159;
            7'd20: sine = 16'sd13622;
            7'd21: sine = 16'sd14052;
            7'd22: sine = 16'sd14449;
            7'd23: sine = 16'sd14810;
            7'd24: sine = 16'sd15136;
            7'd25: sine = 16'sd15425;
            7'd26: sine = 16'sd15678;
            7'd27: sine = 16'sd15892;
            7'd28: sine = 16'sd16068;
            7'd29: sine = 16'sd16206;
            7'd30: sine = 16'sd16304;
            7'd31: sine = 16'sd16363;
            7'd32: sine = 16'sd16383;
            7'd33: sine = 16'sd16363;
            7'd34: sine = 16'sd16304;
            7'd35: sine = 16'sd16206;
            7'd36: sine = 16'sd16068;
            7'd37: sine = 16'sd15892;
            7'd38: sine = 16'sd15678;
            7'd39: sine = 16'sd15425;
            7'd40: sine = 16'sd15136;
            7'd41: sine = 16'sd14810;
            7'd42: sine = 16'sd14449;
            7'd43: sine = 16'sd14052;
            7'd44: sine = 16'sd13622;
            7'd45: sine = 16'sd13159;
            7'd46: sine = 16'sd12664;
            7'd47: sine = 16'sd12139;
            7'd48: sine = 16'sd11585;
            7'd49: sine = 16'sd11002;
            7'd50: sine = 16'sd10393;
            7'd51: sine = 16'sd9759;
            7'd52: sine = 16'sd9102;
            7'd53: sine = 16'sd8423;
            7'd54: sine = 16'sd7723;
            7'd55: sine = 16'sd7005;
            7'd56: sine = 16'sd6270;
            7'd57: sine = 16'sd5519;
            7'd58: sine = 16'sd4756;
            7'd59: sine = 16'sd3981;
            7'd60: sine = 16'sd3196;
            7'd61: sine = 16'sd2404;
            7'd62: sine = 16'sd1606;
            7'd63: sine = 16'sd804;
            7'd64: sine = 16'sd0;
            7'd65: sine = -16'sd804;
            7'd66: sine = -16'sd1606;
            7'd67: sine = -16'sd2404;
            7'd68: sine = -16'sd3196;
            7'd69: sine = -16'sd3981;
            7'd70: sine = -16'sd4756;
            7'd71: sine = -16'sd5519;
            7'd72: sine = -16'sd6270;
            7'd73: sine = -16'sd7005;
            7'd74: sine = -16'sd7723;
            7'd75: sine = -16'sd8423;
            7'd76: sine = -16'sd9102;
            7'd77: sine = -16'sd9759;
            7'd78: sine = -16'sd10393;
            7'd79: sine = -16'sd11002;
            7'd80: sine = -16'sd11585;
            7'd81: sine = -16'sd12139;
            7'd82: sine = -16'sd12664;
            7'd83: sine = -16'sd13159;
            7'd84: sine = -16'sd13622;
            7'd85: sine = -16'sd14052;
            7'd86: sine = -16'sd14449;
            7'd87: sine = -16'sd14810;
            7'd88: sine = -16'sd15136;
            7'd89: sine = -16'sd15425;
            7'd90: sine = -16'sd15678;
            7'd91: sine = -16'sd15892;
            7'd92: sine = -16'sd16068;
            7'd93: sine = -16'sd16206;
            7'd94: sine = -16'sd16304;
            7'd95: sine = -16'sd16363;
            7'd96: sine = -16'sd16383;
            7'd97: sine = -16'sd16363;
            7'd98: sine = -16'sd16304;
            7'd99: sine = -16'sd16206;
            7'd100: sine = -16'sd16068;
            7'd101: sine = -16'sd15892;
            7'd102: sine = -16'sd15678;
            7'd103: sine = -16'sd15425;
            7'd104: sine = -16'sd15136;
            7'd105: sine = -16'sd14810;
            7'd106: sine = -16'sd14449;
            7'd107: sine = -16'sd14052;
            7'd108: sine = -16'sd13622;
            7'd109: sine = -16'sd13159;
            7'd110: sine = -16'sd12664;
            7'd111: sine = -16'sd12139;
            7'd112: sine = -16'sd11585;
            7'd113: sine = -16'sd11002;
            7'd114: sine = -16'sd10393;
            7'd115: sine = -16'sd9759;
            7'd116: sine = -16'sd9102;
            7'd117: sine = -16'sd8423;
            7'd118: sine = -16'sd7723;
            7'd119: sine = -16'sd7005;
            7'd120: sine = -16'sd6270;
            7'd121: sine = -16'sd5519;
            7'd122: sine = -16'sd4756;
            7'd123: sine = -16'sd3981;
            7'd124: sine = -16'sd3196;
            7'd125: sine = -16'sd2404;
            7'd126: sine = -16'sd1606;
            7'd127: sine = -16'sd804;
            default: sine = 16'sd0;
        endcase
    end
    // sine peak is 16383; scale by shifting
    reg signed [15:0] scaled;
    always @* case (asel)
        3'd1: scaled = sine >>> 4;     // +-1024
        3'd2: scaled = sine >>> 3;     // +-2048
        3'd3: scaled = sine >>> 2;     // +-4096
        3'd4: scaled = sine >>> 1;     // +-8192
        default: scaled = 16'sd0;
    endcase

    always @(posedge clk) begin
        tick <= tick + 9'd1;
        if (&tick) begin
            phase <= phase + inc;
            s     <= scaled;
        end
    end

    delta_sigma_dac #(.WIDTH(16)) dac (.clk(clk), .rst_n(rst_n),
        .dac_in({~s[15], s[14:0]}), .dac_out(o_Audio_Out));

    reg [24:0] hb = 25'd0;
    always @(posedge clk) hb <= hb + 25'd1;
    assign o_LED_1 = hb[24];
    assign o_LED_2 = (asel != 3'd0);
    assign o_LED_3 = 1'b0;
    assign o_LED_4 = 1'b0;

    wire [6:0] s1, s2;
    amp_hex7 h1 (.value({1'b0, fsel}), .seg(s1));
    amp_hex7 h2 (.value({1'b0, asel}), .seg(s2));
    assign {o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G} = ~s1;
    assign {o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G} = ~s2;
endmodule

module amp_deb #(parameter LIMIT = 19'd499999) (input wire clk, input wire in, output reg press);
    reg s0 = 0, s1 = 0, stable = 0; reg [18:0] cnt = 0;
    always @(posedge clk) begin
        s0 <= in; s1 <= s0; press <= 1'b0;
        if (s1 == stable) cnt <= 0;
        else if (cnt == LIMIT) begin stable <= s1; cnt <= 0; if (s1) press <= 1'b1; end
        else cnt <= cnt + 19'd1;
    end
endmodule

module amp_hex7 (input wire [3:0] value, output reg [6:0] seg);   // {A..G}, active high
    always @* case (value)
        4'd0: seg = 7'b1111110; 4'd1: seg = 7'b0110000; 4'd2: seg = 7'b1101101; 4'd3: seg = 7'b1111001;
        4'd4: seg = 7'b0110011; default: seg = 7'b0000001;
    endcase
endmodule