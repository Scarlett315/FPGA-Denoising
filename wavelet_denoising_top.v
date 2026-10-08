/*module wavelet_denoising_top #(parameter WIDTH = 16) (
    input wire clk,
    input wire rst_n,
    input wire [WIDTH-1:0] s_in,

    ouput wire [WIDTH-1:0] s_out,
    output wire s_out_valid
);

    // wire instantiation
    wire [WIDTH-1:0] approx;
    wire [WIDTH:0] detail;
    wire lwt_out_valid;
    wire lwt_in_valid;

    wire [WIDTH:0] detail_thresh;
    wire thresh_out_valid;

    // module instantiation
    lifting_haar lwt (
        .clk(clk),
        .rst_n(rst_n),
        .s_in(s_in),
        .s_in_valid(lwt_in_valid),

        .approx(approx),
        .detail(detail),
        .out_valid(lwt_out_valid)
    );

    threshold thresh (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(lwt_out_valid)
        .detail_in(detail),
        .detail_thresh(detail_thresh)
    );

endmodule

*/