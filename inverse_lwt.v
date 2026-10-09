module inverse_lwt #(parameter WIDTH = 16) (
    input wire clk,
    input wire rst_n,

    // inputs - approximation and detil coeffs
    input wire signed [WIDTH-1:0] approx, 
    input wire signed [WIDTH:0] detail,
    input wire odd_pending, // lifting_haar odd_pending is true, which means it is in the even phase
                            // if true, inputs are not valid right now

    // outputs
    output wire signed [WIDTH-1:0] s_out, // denoised signal
    output wire s_out_valid
); 

    wire signed [WIDTH-1:0]  s_even;
    wire signed [WIDTH-1:0]  s_odd;
    
    // basically going back
    assign s_even = approx - (detail >>> 1); // even values = approximation - details/2
    assign s_odd = detail + s_even;

    reg signed [WIDTH-1:0] s_out_reg;
    assign s_out = s_out_reg;

    reg [WIDTH-1:0] odd_reg; // store odd  

    // to catch startup problems
    reg start_output;

    reg s_out_valid_reg;
    assign s_out_valid = s_out_valid_reg;

    // merge
    always @(posedge clk) begin
        s_out_valid_reg <= 1'b0;
        
        // reset to even first
        if (!rst_n) begin
            s_out_reg <= 0;
            start_output <= 1'b0;
            odd_reg <= 0;
            s_out_valid_reg <= 1'b0;
        end 
        
        // if in odd phase, inputs are valid. output even and store odd
        else if (!odd_pending) begin
            if (start_output) begin
                s_out_reg <= s_even;
                odd_reg <= s_odd;
                s_out_valid_reg <= 1'b1;
            end
        end 
        
        // if in even phase, inputs are updating. output stored odd sample
        else begin
            start_output <= 1; // first even sample has been stored
            s_out_reg <= odd_reg; // on the first round, it will output zero 
            s_out_valid_reg <= 1'b1;
        end
    end
 
endmodule