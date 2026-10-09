`timescale 1ns / 1ps

// Self-checking testbench for the combinational soft-threshold module.
//
// Valid input range: for WIDTH-bit input samples, a Haar detail is
//   d = x_odd - x_even, so |d| <= 2^WIDTH - 1 (i.e. -65535..65535 for WIDTH=16).
// The 17-bit value -65536 can never occur and is deliberately not tested.
//
// Run:  iverilog -g2005 -Wall -o thr.vvp threshold.v threshold_tb.v && vvp thr.vvp
// Waves (big file!):  add -DDUMP to the iverilog command.

module threshold_tb;
    localparam WIDTH = 16;
    localparam integer MAXD = (1 << WIDTH) - 1;     // 65535

    reg  signed [WIDTH:0]   detail;
    reg         [WIDTH-1:0] lambda;
    wire signed [WIDTH:0]   detail_thresh;

    threshold #(.WIDTH(WIDTH)) dut (
        .detail        (detail),
        .lambda        (lambda),
        .detail_thresh (detail_thresh)
    );

    integer errors  = 0;
    integer checked = 0;

    // ---------------- reference model (plain integers) ----------------
    function integer ref_soft(input integer d, input integer lam);
        integer a, r;
        begin
            a = (d < 0) ? -d : d;
            r = (a > lam) ? (a - lam) : 0;
            ref_soft = (d < 0) ? -r : r;
        end
    endfunction

    // Drive one (d, lambda) pair and compare against `expected`.
    task check_exact(input integer d, input integer lam, input integer expected);
        integer got;
        begin
            detail = d;
            lambda = lam;
            #1;
            got = detail_thresh;                    // signed wire -> sign-extended
            checked = checked + 1;
            if (got !== expected) begin
                errors = errors + 1;
                if (errors <= 20)
                    $display("FAIL d=%0d lambda=%0d: got %0d, expected %0d",
                             d, lam, got, expected);
            end
        end
    endtask

    // Drive one pair and compare against the reference model.
    task check(input integer d, input integer lam);
        begin
            check_exact(d, lam, ref_soft(d, lam));
        end
    endtask

    // ---------------- stimulus ----------------
    integer d, i, k;
    integer seed = 20261008;
    integer r1, r2;
    integer lam_set [0:14];
    integer d_set   [0:14];

    initial begin
`ifdef DUMP
`endif

        // ---- 1. directed cases with hand-computed answers ----
        check_exact(   10,     3,      7);
        check_exact(  -10,     3,     -7);
        check_exact(    4,     3,      1);
        check_exact(   -4,     3,     -1);
        check_exact(    3,     3,      0);   // |d| == lambda -> 0
        check_exact(   -3,     3,      0);
        check_exact(    2,     3,      0);   // below threshold
        check_exact(   -2,     3,      0);
        check_exact(    0,     5,      0);
        check_exact(    1,     0,      1);   // lambda = 0 -> pass-through
        check_exact(   -1,     0,     -1);
        check_exact(MAXD,      0,   MAXD);
        check_exact(-MAXD,     0,  -MAXD);
        check_exact(MAXD,      1,   MAXD-1);
        check_exact(-MAXD,     1,  -(MAXD-1));
        check_exact(MAXD,   MAXD,      0);   // lambda at max -> everything zeroed
        check_exact(-MAXD,  MAXD,      0);

        // ---- 2. every legal d, for a set of lambdas ----
        lam_set[0]  = 0;      lam_set[1]  = 1;     lam_set[2]  = 2;
        lam_set[3]  = 3;      lam_set[4]  = 7;     lam_set[5]  = 100;
        lam_set[6]  = 255;    lam_set[7]  = 256;   lam_set[8]  = 1000;
        lam_set[9]  = 4095;   lam_set[10] = 32767; lam_set[11] = 32768;
        lam_set[12] = 50000;  lam_set[13] = 65534; lam_set[14] = 65535;
        for (k = 0; k < 15; k = k + 1)
            for (d = -MAXD; d <= MAXD; d = d + 1)
                check(d, lam_set[k]);

        // ---- 3. every lambda, for a set of d values ----
        d_set[0]  = 0;      d_set[1]  = 1;      d_set[2]  = -1;
        d_set[3]  = 2;      d_set[4]  = -2;     d_set[5]  = 255;
        d_set[6]  = -255;   d_set[7]  = 32767;  d_set[8]  = -32767;
        d_set[9]  = 32768;  d_set[10] = -32768; d_set[11] = MAXD;
        d_set[12] = -MAXD;  d_set[13] = 12345;  d_set[14] = -12345;
        for (k = 0; k < 15; k = k + 1)
            for (i = 0; i <= MAXD; i = i + 1)
                check(d_set[k], i);

        // ---- 4. random (d, lambda) pairs ----
        for (i = 0; i < 200000; i = i + 1) begin
            r1 = $random(seed);
            r2 = $random(seed);
            d  = (r1 & 32'h1FFFF) - MAXD;           // -65535 .. 65536
            if (d > MAXD) d = MAXD;                 // 65536 is not a legal detail
            check(d, r2 & 32'hFFFF);
        end

        // ---- report ----
        if (errors == 0)
            $display("PASS: %0d cases checked, no mismatches", checked);
        else
            $display("FAILED: %0d mismatches in %0d cases", errors, checked);
        $finish;
    end
endmodule