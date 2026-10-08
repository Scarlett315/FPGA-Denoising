`timescale 1ns / 1ps

module lifting_haar_tb;
    localparam WIDTH      = 16;
    localparam NUM_PAIRS  = 2000;          // random pairs after the directed ones
    localparam GAP_CYCLES = 4;             // idle clocks between samples

    // ---------------- DUT connections ----------------
    reg                     clk = 1'b0;
    reg                     rst_n = 1'b0;
    reg  signed [WIDTH-1:0] x_in = 0;
    reg                     x_valid = 1'b0;

    wire signed [WIDTH-1:0] approx;
    wire signed [WIDTH:0]   detail;
    wire                    out_valid;

    lifting_haar #(.WIDTH(WIDTH)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .s_in     (x_in),
        .s_in_valid  (x_valid),
        .approx   (approx),
        .detail   (detail),
        .out_valid(out_valid)
    );

    // 10 ns clock
    always #5 clk = ~clk;

    // ---------------- Golden model + scoreboard ----------------
    // Expected (s, d) pushed when the odd sample is driven; popped on out_valid.
    reg signed [WIDTH-1:0] exp_s [0:NUM_PAIRS+63];
    reg signed [WIDTH:0]   exp_d [0:NUM_PAIRS+63];
    integer wr_idx   = 0;
    integer rd_idx   = 0;
    integer errors   = 0;
    integer checked  = 0;

    reg signed [WIDTH-1:0] prev_even;      // golden model state
    reg                    have_even = 1'b0;

    // Floor division by 2 via arithmetic shift, same as the RTL.
    function signed [WIDTH:0] diff_f(input signed [WIDTH-1:0] xo,
                                     input signed [WIDTH-1:0] xe);
        diff_f = xo - xe;
    endfunction

    // Drive one sample with a valid strobe, then idle for GAP_CYCLES.
    task send_sample(input signed [WIDTH-1:0] v);
        reg signed [WIDTH:0] d;
        begin
            @(negedge clk);
            x_in    = v;
            x_valid = 1'b1;
            // golden model
            if (!have_even) begin
                prev_even = v;
                have_even = 1'b1;
            end else begin
                d = diff_f(v, prev_even);
                exp_d[wr_idx] = d;
                exp_s[wr_idx] = prev_even + (d >>> 1);
                wr_idx = wr_idx + 1;
                have_even = 1'b0;
            end
            @(negedge clk);
            x_valid = 1'b0;
            repeat (GAP_CYCLES) @(negedge clk);
        end
    endtask

    task send_pair(input signed [WIDTH-1:0] xe, input signed [WIDTH-1:0] xo);
        begin
            send_sample(xe);
            send_sample(xo);
        end
    endtask

    // Check outputs on every out_valid pulse.
    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            if (rd_idx >= wr_idx) begin
                $display("FAIL @%0t: out_valid with no expected result queued", $time);
                errors = errors + 1;
            end else begin
                if (approx !== exp_s[rd_idx] || detail !== exp_d[rd_idx]) begin
                    $display("FAIL @%0t pair %0d: got s=%0d d=%0d, expected s=%0d d=%0d",
                             $time, rd_idx, approx, detail, exp_s[rd_idx], exp_d[rd_idx]);
                    errors = errors + 1;
                end
                checked = checked + 1;
                rd_idx  = rd_idx + 1;
            end
        end
    end

    // out_valid must be a single-cycle pulse and must never fire during reset.
    reg out_valid_q = 1'b0;
    always @(posedge clk) begin
        out_valid_q <= out_valid;
        if (out_valid && out_valid_q) begin
            $display("FAIL @%0t: out_valid held high for more than one cycle", $time);
            errors = errors + 1;
        end
    end

    // ---------------- Stimulus ----------------
    integer i;
    integer seed = 12345;
    reg signed [WIDTH-1:0] ra, rb;
    localparam signed [WIDTH-1:0] MAXV =  16'sh7FFF;
    localparam signed [WIDTH-1:0] MINV = -16'sh8000;

    initial begin
        $dumpvars(0, lifting_haar_tb);

        // Reset, released a little after a clock edge.
        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        #2 rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // ---- directed pairs (xe, xo) ----
        send_pair(  0,    0);
        send_pair( 10,   20);      // d= 10, s= 15
        send_pair( 20,   10);      // d=-10, s= 15
        send_pair( -5,    4);      // d=  9, floor behaviour on odd d
        send_pair(  3,   -4);      // d= -7, floor of negative odd
        send_pair( -1,   -2);      // d= -1, s=-2 (floor(-1/2) = -1)
        send_pair(100,  100);      // flat signal -> d = 0
        send_pair(MAXV, MINV);     // largest negative d (needs 17 bits)
        send_pair(MINV, MAXV);     // largest positive d (needs 17 bits)
        send_pair(MAXV, MAXV);
        send_pair(MINV, MINV);

        // ---- random pairs ----
        for (i = 0; i < NUM_PAIRS; i = i + 1) begin
            ra = $random(seed);
            rb = $random(seed);
            send_pair(ra, rb);
        end

        // ---- mid-stream reset: phase must return to "even" ----
        send_sample(16'sd7);       // lone even sample, then reset discards it
        have_even = 1'b0;          // golden model forgets it too
        @(negedge clk) rst_n = 1'b0;
        @(negedge clk) rst_n = 1'b1;
        repeat (2) @(negedge clk);
        send_pair(40, 60);         // d= 20, s= 50 -- must pair correctly
        send_pair(-8, -9);

        repeat (10) @(negedge clk);

        // ---- report ----
        if (rd_idx != wr_idx) begin
            $display("FAIL: expected %0d results, saw %0d", wr_idx, rd_idx);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS: %0d pairs checked, no mismatches", checked);
        else
            $display("FAILED: %0d errors over %0d pairs", errors, checked);
        $finish;
    end

    // Watchdog
    initial begin
        #50_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule