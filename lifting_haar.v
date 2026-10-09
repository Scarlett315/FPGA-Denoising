module lifting_haar #(parameter WIDTH = 16) (
    input wire clk,
    input wire rst_n,

    // inputs
    input wire signed [WIDTH-1:0] s_in, // input signal
    input wire s_in_valid,

    // outputs
    output wire signed [WIDTH-1:0] approx, 
    output wire signed [WIDTH:0] detail,
    output reg odd_pending
); 

    reg split_phase; // 0 = even, 1 = odd
    reg signed [WIDTH-1:0] s_even;
    reg signed [WIDTH:0] diff;

    assign odd_pending = split_phase;

    // approximation = even values + differences/2, detail = differences
    // i.e. this is the "update" step
    assign approx = s_even + (diff >>> 1);
    assign detail = diff;

    always @(posedge clk) begin
        
        // reset to even first
        if (!rst_n) begin
            split_phase <= 1'b0;
        end

        // split + predict
        else if (s_in_valid) begin
            split_phase <= ~split_phase; // flip~
            
            // store even sample
            if (~split_phase) begin
                s_even <= s_in;
            end 
            
            // and predict + update on the odd samples
            // for Haar, the prediction for the odd sample = the even sample to its left
            else begin
                diff <= s_in - s_even; // current (odd) - even to its left
            end
        end
    end
endmodule