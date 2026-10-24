// Mic (INMP441, I2S) -> gain -> Haar lifting denoiser -> sigma-delta DAC pin
module denoiser_system (
    input  wire       clk,          // 25 MHz Go Board clock
    input  wire       mic_sd,       // INMP441 SD
    output wire       mic_sck,      // INMP441 SCK
    output wire       mic_ws,       // INMP441 WS  (tie the mic's L/R pin to GND = left channel)
    input  wire [3:0] gain_sel,     // 0..8 : digital gain 2^gain_sel on the 16-bit slice
    input  wire [3:0] lambda_sel,   // 0 = off, else threshold = 2^(lambda_sel-1)
    output wire       dac_out       // 1-bit sigma-delta to the RC filter
);
    // power-on reset
    reg [3:0] por = 4'd0;
    always @(posedge clk) if (!(&por)) por <= por + 4'd1;
    wire rst_n = &por;

    wire [23:0]        mic_sample;
    wire               mic_valid;
    wire signed [15:0] s_in;
    wire               s_in_valid;

    i2s_rx #(.HALF(12)) rx (
        .clk(clk), .rst_n(rst_n), .sd(mic_sd), .sck(mic_sck), .ws(mic_ws),
        .sample(mic_sample), .sample_valid(mic_valid));

    input_gain gain (
        .clk(clk), .rst_n(rst_n), .sample(mic_sample), .sample_valid(mic_valid),
        .gain_sel(gain_sel), .s_in(s_in), .s_in_valid(s_in_valid));

    wire [15:0] lambda = (lambda_sel == 4'd0) ? 16'd0 : (16'd1 << (lambda_sel - 4'd1));

    wavelet_denoising_top #(.WIDTH(16)) core (
        .clk(clk), .rst_n(rst_n), .s_in(s_in), .s_in_valid(s_in_valid),
        .lambda(lambda), .dac_out_wire(dac_out));
endmodule