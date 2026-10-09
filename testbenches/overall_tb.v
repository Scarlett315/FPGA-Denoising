`timescale 1ns / 1ps
// Overall testbench: wavelet_denoising_top (lifting_haar -> threshold -> inverse_lwt)
// Run: iverilog -g2005 -o top.vvp lifting_haar.v threshold.v inverse_lwt.v wavelet_denoising_top.v wavelet_denoising_top_tb.v && vvp top.vvp
//
// Test 1: bit-exact vs integer golden model, random/extreme data, 7 lambdas (incl. 0 = lossless)
// Test 2: output timing (s_out changes 2 clocks after the strobe, held otherwise); s_out_valid level
// Test 3: reset in mid-stream -> outputs 0/invalid, then a clean restart
// Test 4: sine + noise demo, reports SNR gain (informational + loose pass bound)
module wavelet_denoising_top_tb;
    localparam WIDTH = 16, PERIOD = 20, NPHASE = 7, PHASE_SAMPLES = 4000;
    localparam MAXN = NPHASE*PHASE_SAMPLES + 16;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg                    rst_n = 1'b0;
    reg signed [WIDTH-1:0] s_in = 0;
    reg                    s_in_valid = 1'b0;
    reg        [WIDTH-1:0] lambda = 0;
    wire signed [WIDTH-1:0] s_out;
    wire                    s_out_valid;

    wavelet_denoising_top #(.WIDTH(WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .s_in(s_in), .s_in_valid(s_in_valid),
        .lambda(lambda), .s_out(s_out), .s_out_valid(s_out_valid));

    // ---------- golden model ----------
    function integer ref_soft(input integer d, input integer lam);
        integer a, r;
        begin
            a = (d < 0) ? -d : d;
            r = (a > lam) ? (a - lam) : 0;
            ref_soft = (d < 0) ? -r : r;
        end
    endfunction

    integer yexp [0:MAXN-1];
    integer yout [0:MAXN-1];
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    integer in_cnt = 0, have_even = 0, pend_even = 0;
    integer errors = 0, range_viol = 0, model_err = 0, timing_err = 0;
    integer t_strobe = 0, chg_cyc = -1;
    reg signed [WIDTH-1:0] prev_s = 0;
    reg started = 0;
    reg rst_prev = 0;
    always @(posedge clk) rst_prev <= rst_n;

    // record the clock at which s_out last changed
    always @(posedge clk) begin
        prev_s <= s_out;
        if (s_out !== prev_s) chg_cyc = cyc;
    end
    // outside of the window "strobe+2" s_out must never change
    always @(posedge clk) if (started && rst_n && rst_prev && (s_out !== prev_s) && (cyc - t_strobe != 2)) begin
        timing_err = timing_err + 1;
        if (timing_err <= 5) $display("TIMING cyc %0d: s_out changed %0d clocks after strobe", cyc, cyc - t_strobe);
    end
    always @(posedge clk) if (s_in_valid) t_strobe = cyc;

    task send_sample(input integer v);
        integer d, s, dh, ye, yo, k, expv, prevv;
        begin
            k = in_cnt;
            @(negedge clk);
            s_in = v; s_in_valid = 1'b1;
            started = 1;
            if (!have_even) begin
                pend_even = v; have_even = 1;
            end else begin
                d  = v - pend_even;
                s  = pend_even + (d >>> 1);
                dh = ref_soft(d, lambda);
                ye = s - (dh >>> 1);
                yo = dh + ye;
                yexp[k-1] = ye; yexp[k] = yo;
                if (ye < -32768 || ye > 32767 || yo < -32768 || yo > 32767) range_viol = range_viol + 1;
                if (lambda == 0 && (ye != pend_even || yo != v)) model_err = model_err + 1;
                have_even = 0;
            end
            in_cnt = in_cnt + 1;
            @(negedge clk);
            s_in_valid = 1'b0;
            repeat (PERIOD - 2) @(negedge clk);
            // end of period: s_out holds output k-1 (first strobe -> leading silent 0)
            expv = (k == 0) ? 0 : yexp[k-1];
            if (k > 0) yout[k-1] = s_out;
            if (s_out_valid !== 1'b1 || s_out !== expv) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("FAIL strobe %0d: s_out=%0d valid=%b expected %0d (lambda=%0d)", k, s_out, s_out_valid, expv, lambda);
            end
        end
    endtask

    integer ph, i, r1, r2, v, n;
    integer seed = 20261008;
    integer lam_list [0:NPHASE-1];
    real    sig, noi, cl, e_in, e_out, e_sig;

    initial begin
        lam_list[0]=0; lam_list[1]=1; lam_list[2]=7; lam_list[3]=100;
        lam_list[4]=2000; lam_list[5]=30000; lam_list[6]=65535;

        // ---- reset behaviour ----
        repeat (4) @(negedge clk);
        if (s_out_valid !== 1'b0 || s_out !== 0) begin errors = errors + 1; $display("FAIL: outputs not 0/invalid in reset"); end
        @(negedge clk) rst_n = 1'b1;
        repeat (3) @(negedge clk);
        if (s_out_valid !== 1'b0) begin errors = errors + 1; $display("FAIL: valid before first sample"); end

        // ---- Test 1/2: random vectors ----
        for (ph = 0; ph < NPHASE; ph = ph + 1)
            for (i = 0; i < PHASE_SAMPLES; i = i + 1) begin
                r1 = $random(seed); r2 = $random(seed);
                case (r1 & 3)
                    0:       v = (r2 & 1) ? 32767 : -32768;
                    1:       v = r2 % 64;
                    default: v = $signed(r2[15:0]);
                endcase
                send_sample(v);
                if (i == 0) lambda = lam_list[ph];   // change only while the stored odd sample is held
            end
        $display("Test 1/2 done: %0d samples, errors so far %0d", in_cnt, errors);

        // ---- Test 3: reset mid-stream, then restart ----
        send_sample(1234);                     // leave an even sample pending (odd count)
        if (in_cnt % 2 == 0) send_sample(55);
        @(negedge clk) rst_n = 1'b0;
        repeat (3) @(negedge clk);
        if (s_out_valid !== 1'b0 || s_out !== 0) begin errors = errors + 1; $display("FAIL: not cleared by mid-stream reset"); end
        @(negedge clk) rst_n = 1'b1;
        repeat (3) @(negedge clk);
        in_cnt = 0; have_even = 0; lambda = 100;
        for (i = 0; i < 400; i = i + 1) send_sample($signed($random(seed)) % 20000);
        $display("Test 3 done, errors so far %0d", errors);

        // ---- Test 4: sine + noise ----
        @(negedge clk) rst_n = 1'b0;
        repeat (3) @(negedge clk);
        @(negedge clk) rst_n = 1'b1;
        repeat (3) @(negedge clk);
        in_cnt = 0; have_even = 0; lambda = 2500;
        n = 4000;
        e_in = 0; e_out = 0; e_sig = 0;
        for (i = 0; i < n; i = i + 1) begin
            cl  = 8000.0 * $sin(6.283185307 * i / 64.0);
            r1  = $random(seed);
            noi = (r1 & 32'hFFFF) * (3000.0/65536.0) - 1500.0;      // uniform +-1500
            sig = cl + noi;
            v   = (sig >= 0) ? $rtoi(sig + 0.5) : $rtoi(sig - 0.5);
            send_sample(v);
            if (i >= 2) begin                // output i-1 is available after strobe i
                cl = 8000.0 * $sin(6.283185307 * (i-1) / 64.0);
                e_out = e_out + (yout[i-1] - cl) * (yout[i-1] - cl);
                e_sig = e_sig + cl*cl;
            end
            // input error for sample i-1 (kept in model: noise only)
        end
        // regenerate input error with same seed sequence is awkward; compute theory instead:
        // uniform +-1500 => variance = 1500^2/3
        e_in = (1500.0*1500.0/3.0) * (n-2);
        $display("Test 4: SNR in  = %f dB", 10.0*$log10(e_sig/e_in));
        $display("        SNR out = %f dB", 10.0*$log10(e_sig/e_out));
        $display("        gain    = %f dB", 10.0*$log10(e_in/e_out));
        if (10.0*$log10(e_in/e_out) < 0.5) begin errors = errors + 1; $display("FAIL: no denoising gain"); end

        errors = errors + range_viol + model_err + timing_err;
        if (errors == 0) $display("PASS: all checks");
        else $display("FAILED: %0d errors (range %0d, model %0d, timing %0d)", errors, range_viol, model_err, timing_err);
        $finish;
    end
endmodule