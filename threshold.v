module threshold #(parameter WIDTH = 16) (
    input wire signed [WIDTH:0] detail,
    input wire [WIDTH-1:0] lambda, // soft threshold value
    
    output wire signed [WIDTH:0] detail_thresh
);
    /*  Soft Thresholding!
    if |detail| > lambda, |detail_thresh| = detail - lambda
    Otherwise, detail_thresh = 0 
    
    since this is arguably kinda long for combinational i may  pipeline it
    */

    // absolute value + store whether it was negative or not
    wire [WIDTH-1:0] detail_abs;
    wire neg;
    assign detail_abs = (detail < 0) ? -detail : detail;
    assign neg = (detail < 0);

    // threshold and put sign back
    wire [WIDTH-1:0] detail_thresh_abs;
    assign detail_thresh_abs = (detail_abs > lambda) ? detail_abs - lambda : 0;
    
    assign detail_thresh = (neg) ? -detail_thresh_abs : detail_thresh_abs;    


endmodule