// 24-bit mic sample -> 16-bit signed sample with digital gain and saturation.
// s_in = sat16( floor( sample * 2^g / 256 ) ),  g = min(gain_sel, 8)
//   g = 0 : plain top-16-bit slice (sample[23:8])      g = 4 : +24 dB (x16)      g = 8 : x256
module input_gain (
    input  wire               clk,
    input  wire               rst_n,
    input  wire        [23:0] sample,
    input  wire               sample_valid,   // one-clock pulse from i2s_rx
    input  wire        [3:0]  gain_sel,
    output reg  signed [15:0] s_in,
    output reg                s_in_valid      // one-clock pulse, s_in is stable while it is high
);
    wire [3:0] g = (gain_sel > 4'd8) ? 4'd8 : gain_sel;
    wire signed [31:0] ext     = {{8{sample[23]}}, sample};
    wire signed [31:0] shifted = ext <<< g;
    // fits in 16 bits only if bits [31:23] of the shifted value are all equal (sign copies)
    wire fits = (&shifted[31:23]) | ~(|shifted[31:23]);
    wire signed [15:0] sat = fits ? shifted[23:8] : (sample[23] ? 16'sh8000 : 16'sh7FFF);
 
    always @(posedge clk) begin
        s_in_valid <= 1'b0;
        if (!rst_n) s_in <= 0;
        else if (sample_valid) begin
            s_in       <= sat;
            s_in_valid <= 1'b1;
        end
    end
endmodule