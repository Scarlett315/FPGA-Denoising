// Go Board top level: buttons set gain and threshold, 7-segment displays show them.
//   SW1 / SW2 : gain up / down      (0..8,  default 4)   -> left  7-seg
//   SW3 / SW4 : threshold up / down (0..15, default 0)   -> right 7-seg (lambda = 2^(n-1), 0 = off)
module go_board_top (
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
    // ---------------- debounced buttons ----------------
    wire [3:0] press; 
    debounce_press d1 (.clk(i_Clk), .in(i_Switch_1), .press(press[0]));
    debounce_press d2 (.clk(i_Clk), .in(i_Switch_2), .press(press[1]));
    debounce_press d3 (.clk(i_Clk), .in(i_Switch_3), .press(press[2]));
    debounce_press d4 (.clk(i_Clk), .in(i_Switch_4), .press(press[3]));

    reg [3:0] gain_sel   = 4'd4;
    reg [3:0] lambda_sel = 4'd0;
    always @(posedge i_Clk) begin
        if (press[0] && gain_sel   < 4'd8)  gain_sel   <= gain_sel + 4'd1;
        if (press[1] && gain_sel   > 4'd0)  gain_sel   <= gain_sel - 4'd1;
        if (press[2] && lambda_sel < 4'd15) lambda_sel <= lambda_sel + 4'd1;
        if (press[3] && lambda_sel > 4'd0)  lambda_sel <= lambda_sel - 4'd1;
    end

    // ---------------- audio!  ----------------
    denoiser_system sys (
        .clk(i_Clk), .mic_sd(i_Mic_SD), .mic_sck(o_Mic_SCK), .mic_ws(o_Mic_WS),
        .gain_sel(gain_sel), .lambda_sel(lambda_sel), .dac_out(o_Audio_Out));

    // ---------------- display ----------------
    wire [6:0] seg1, seg2;                           
    hex_to_7seg h1 (.value(gain_sel),   .seg(seg1));
    hex_to_7seg h2 (.value(lambda_sel), .seg(seg2));
    assign {o_Segment1_A, o_Segment1_B, o_Segment1_C, o_Segment1_D, o_Segment1_E, o_Segment1_F, o_Segment1_G} = ~seg1;
    assign {o_Segment2_A, o_Segment2_B, o_Segment2_C, o_Segment2_D, o_Segment2_E, o_Segment2_F, o_Segment2_G} = ~seg2;

    // heartbeat on LED1 shows the FPGA is configured/clocked
    reg [24:0] hb = 25'd0;
    always @(posedge i_Clk) hb <= hb + 25'd1;
    assign o_LED_1 = hb[24];
    assign o_LED_2 = 1'b0;
    assign o_LED_3 = 1'b0;
    assign o_LED_4 = 1'b0;
endmodule

// 20 ms debounce at 25 MHz; emits one pulse when the (stable) input goes high
module debounce_press #(parameter LIMIT = 19'd499999) (
    input  wire clk, input wire in, output reg press
);
    reg s0 = 0, s1 = 0, stable = 0; reg [18:0] cnt = 0;
    always @(posedge clk) begin
        s0 <= in; s1 <= s0; press <= 1'b0;
        if (s1 == stable) cnt <= 0;
        else if (cnt == LIMIT) begin stable <= s1; cnt <= 0; if (s1) press <= 1'b1; end
        else cnt <= cnt + 19'd1;
    end
endmodule

module hex_to_7seg (input wire [3:0] value, output reg [6:0] seg);   // seg = {A,B,C,D,E,F,G}
    always @* case (value)
        4'h0: seg = 7'b1111110;  4'h1: seg = 7'b0110000;  4'h2: seg = 7'b1101101;  4'h3: seg = 7'b1111001;
        4'h4: seg = 7'b0110011;  4'h5: seg = 7'b1011011;  4'h6: seg = 7'b1011111;  4'h7: seg = 7'b1110000;
        4'h8: seg = 7'b1111111;  4'h9: seg = 7'b1111011;  4'hA: seg = 7'b1110111;  4'hB: seg = 7'b0011111;
        4'hC: seg = 7'b1001110;  4'hD: seg = 7'b0111101;  4'hE: seg = 7'b1001111;  4'hF: seg = 7'b1000111;
    endcase
endmodule