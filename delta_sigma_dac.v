module delta_sigma_dac #( parameter WIDTH = 16 )(
    input  wire clk,      
    input  wire rst_n,    
    input  wire [WIDTH-1:0] dac_in,   
    output reg  dac_out   
);

    // accumulator / integrator
    reg [WIDTH+1:0] accum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum <= 0;
            dac_out <= 1'b0;
        end else begin

            //feedback gets rid of quantization error
            if (dac_out) begin // subtract the max value (2^BIT_WIDTH) from the feedback path
                accum <= accum + dac_in - (1'b1 << WIDTH); // i.e. 2^WIDTH
            end else begin // if not js accumulate~
                accum <= accum + dac_in;
            end
            
            // 1 if accumulator's MSB is 1, and v.v.
            //
            dac_out <= accum[WIDTH+1];
        end
    end

endmodule