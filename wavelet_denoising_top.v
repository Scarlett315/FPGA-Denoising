module wavelet_denoising_top #(parameter WIDTH = 16) (
    input wire clk,
    input wire rst_n,
    input wire signed [WIDTH-1:0] s_in,
    input wire s_in_valid,
    input wire [WIDTH-1:0] lambda,

    output wire signed [WIDTH-1:0] s_out,
    output wire s_out_valid
);

    // wire instantiation
    wire signed [WIDTH-1:0] approx;
    wire signed [WIDTH:0] detail;
    wire odd_pending;

    wire signed [WIDTH:0] detail_thresh;
    wire thresh_out_valid;

    // module instantiation
    lifting_haar lwt (
        .clk(clk),
        .rst_n(rst_n),
        .s_in(s_in),
        .s_in_valid(s_in_valid),

        .approx(approx),
        .detail(detail),
        .odd_pending(odd_pending)
    );

    threshold thresh (
        .lambda(lambda),
        .detail(detail),
        .detail_thresh(detail_thresh)
    );

    inverse_lwt inv(
        .clk(clk),
        .rst_n(rst_n),

        .approx(approx),
        .detail(detail_thresh),
        .odd_pending(odd_pending),

        .s_out(s_out),
        .s_out_valid(s_out_valid)
    );

endmodule