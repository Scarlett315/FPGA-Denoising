// I2S master-mode receiver for a mic such as the INMP441 (FPGA generates SCK and WS).
// SCK = clk / (2*HALF), 64 SCK per frame (32-bit slots), left channel captured (mic L/R pin = GND).
// 25 MHz, HALF = 12  ->  SCK = 1.0417 MHz, fs = 16.276 kHz.
module i2s_rx #(parameter HALF = 12) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sd,// mic data
    output reg         sck,
    output wire        ws,            // low = left
    output reg  [23:0] sample,        // 24-bit two's complement, held until the next sample
    output reg         sample_valid   // one-clock pulse when `sample` is updated
);
    reg [7:0] div;
    reg [5:0] fc;                     // bit counter, advances on SCK falling edges
    reg [23:0] sh;
    reg sd_m, sd_s;                   // 2-FF synchroniser for the mic data
 
    assign ws = fc[5];
    wire tick = (div == HALF-1);
 
    always @(posedge clk) begin
        sd_m <= sd;  sd_s <= sd_m;
        sample_valid <= 1'b0;
        if (!rst_n) begin
            div <= 0;  sck <= 1'b0;  fc <= 6'd63;  sh <= 0;  sample <= 0;
        end else begin
            div <= tick ? 8'd0 : div + 8'd1;
            if (tick) begin
                sck <= ~sck;
                if (sck) begin
                    fc <= fc + 6'd1; // falling edge: WS / bit counter update
                end else if (fc >= 6'd1 && fc <= 6'd24) begin // rising edge: MSB arrives one SCK after WS
                    sh <= {sh[22:0], sd_s};
                    if (fc == 6'd24) begin
                        sample       <= {sh[22:0], sd_s};
                        sample_valid <= 1'b1;
                    end
                end
            end
        end
    end
endmodule