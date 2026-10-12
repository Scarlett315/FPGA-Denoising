`timescale 1ns / 1ps
// Full-chain testbench: lifting_haar -> threshold -> inverse_lwt -> delta_sigma_dac
//
//   iverilog -g2005 -o top.vvp lifting_haar.v threshold.v inverse_lwt.v delta_sigma_dac.v \
//            wavelet_denoising_top.v wavelet_denoising_top_tb.v && vvp top.vvp
//
// Checks
//  1. s_out (read hierarchically) is bit-exact vs an integer golden model of forward lifting,
//     soft threshold and inverse lifting, in the right order, for 7 lambdas incl. 0 (lossless)
//  2. s_out_valid is high from the first sample on; s_out only changes 2 clocks after a strobe
//  3. Delta-sigma bitstream: within each held sample, #ones ~= L * x / 2^WIDTH (tolerance TOL),
//     where x is s_out in offset binary; this proves the MSB flip and sigma-delta feedback
//  4. Reset (async, mid-stream): dac_out low, s_out/s_out_valid cleared, clean restart
//  5. Demo: sine + noise, reports SNR through the digital chain and after averaging the bitstream
// Timing is realistic: PERIOD = 25 MHz / 16 kHz = 1562 clocks per sample.
module wavelet_denoising_top_tb;
    localparam WIDTH         = 16;
    localparam PERIOD        = 1562;
    localparam NPHASE        = 7;
    localparam PHASE_SAMPLES = 400;               // must be even
    localparam NSINE         = 1500;
    localparam MAXN          = NPHASE*PHASE_SAMPLES + NSINE + 400;
    localparam WIN_START     = 16;                // skip the first clocks after a strobe
    localparam TOL           = 4;                 // allowed |ones - ideal| in a window

    reg clk = 1'b0;
    always #20 clk = ~clk;                        // 25 MHz

    reg                    rst_n = 1'b0;
    reg signed [WIDTH-1:0] s_in  = 0;
    reg                    s_in_valid = 1'b0;
    reg        [WIDTH-1:0] lambda = 0;
    wire                   dac_out_wire;

    wavelet_denoising_top #(.WIDTH(WIDTH)) dut (
        .clk(clk), .rst_n(rst_n), .s_in(s_in), .s_in_valid(s_in_valid),
        .lambda(lambda), .dac_out_wire(dac_out_wire));

    // internal probes
    wire signed [WIDTH-1:0] s_out       = dut.s_out;
    wire                    s_out_valid = dut.s_out_valid;

    // ---------------- golden model ----------------
    function integer ref_soft(input integer d, input integer lam);
        integer a, r;
        begin
            a = (d < 0) ? -d : d;
            r = (a > lam) ? (a - lam) : 0;
            ref_soft = (d < 0) ? -r : r;
        end
    endfunction

    integer yexp [0:MAXN-1];
    integer yout [0:MAXN-1];      // captured s_out
    real    vdac [0:MAXN-1];      // averaged bitstream (0..1)
    integer in_cnt = 0, have_even = 0, pend_even = 0;
    integer errors = 0, range_viol = 0, model_err = 0, timing_err = 0, dac_err = 0;
    integer max_dac_dev = 0;

    // ---------------- per-clock monitors ----------------
    integer since = 0, ones_win = 0, win_len = 0, t_strobe_valid = 0;
    reg started = 1'b0, rst_prev = 1'b0;
    reg signed [WIDTH-1:0] prev_s = 0;
    always @(posedge clk) begin
        rst_prev <= rst_n;
        prev_s   <= s_out;
        if (s_in_valid) begin since = 0; ones_win = 0; win_len = 0; end
        else            since = since + 1;
        if (since >= WIN_START) begin
            ones_win = ones_win + dac_out_wire;
            win_len  = win_len + 1;
        end
        // s_out must only change exactly 2 clocks after a strobe (outside reset)
        if (started && rst_n && rst_prev && (s_out !== prev_s) && (since != 2)) begin
            timing_err = timing_err + 1;
            if (timing_err <= 5) $display("TIMING: s_out changed %0d clocks after strobe", since);
        end
    end

    // ---------------- driver ----------------
    task send_sample(input integer v);
        integer d, s, dh, ye, yo, k, expv, xoff, dev;
        real ideal;
        begin
            k = in_cnt;
            @(negedge clk);
            s_in = v; s_in_valid = 1'b1; started = 1'b1;
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

            // ---- end of period: check digital output and DAC bitstream ----
            expv = (k == 0) ? 0 : yexp[k-1];
            if (k > 0) yout[k-1] = s_out;
            if (s_out_valid !== 1'b1 || s_out !== expv) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("FAIL strobe %0d: s_out=%0d valid=%b expected %0d (lambda=%0d)",
                             k, s_out, s_out_valid, expv, lambda);
            end
            xoff  = expv + 32768;                       // offset binary
            ideal = win_len * (xoff / 65536.0);
            dev   = (ones_win > ideal) ? (ones_win - ideal + 0.999) : (ideal - ones_win + 0.999);
            if (dev > max_dac_dev) max_dac_dev = dev;
            if (dev > TOL) begin
                dac_err = dac_err + 1;
                if (dac_err <= 5)
                    $display("DAC: strobe %0d x=%0d ones=%0d ideal=%0f (window %0d)", k, xoff, ones_win, ideal, win_len);
            end
            if (k > 0) vdac[k-1] = ones_win * 1.0 / win_len;
        end
    endtask

    // ---------------- stimulus ----------------
    integer ph, i, r1, r2, v, n;
    integer seed = 20261011;
    integer lam_list [0:NPHASE-1];
    real    cl, noi, sig, e_in, e_dig, e_dac, e_sig, rec;

    initial begin
        lam_list[0]=0; lam_list[1]=1; lam_list[2]=7; lam_list[3]=100;
        lam_list[4]=2000; lam_list[5]=30000; lam_list[6]=65535;

        // ---- reset state ----
        repeat (4) @(negedge clk);
        if (dac_out_wire !== 1'b0 || s_out_valid !== 1'b0 || s_out !== 0) begin
            errors = errors + 1; $display("FAIL: outputs not cleared in reset");
        end
        @(negedge clk) rst_n = 1'b1;
        repeat (3) @(negedge clk);
        if (s_out_valid !== 1'b0) begin errors = errors + 1; $display("FAIL: valid before first sample"); end

        // ---- Tests 1-3: random + extreme vectors, 7 lambdas ----
        for (ph = 0; ph < NPHASE; ph = ph + 1)
            for (i = 0; i < PHASE_SAMPLES; i = i + 1) begin
                r1 = $random(seed); r2 = $random(seed);
                case (r1 & 3)
                    0:       v = (r2 & 1) ? 32767 : -32768;
                    1:       v = r2 % 64;
                    default: v = $signed(r2[15:0]);
                endcase
                send_sample(v);
                if (i == 0) lambda = lam_list[ph];       // only while the stored odd sample is held
            end
        $display("Tests 1-3 done: %0d samples, errors %0d, DAC window errors %0d (max dev %0d ones)",
                 in_cnt, errors, dac_err, max_dac_dev);

        // ---- Test 4: asynchronous reset in mid-stream, then restart ----
        send_sample(1234);
        if (in_cnt % 2 == 0) send_sample(55);            // leave an even sample pending
        n = 0;                                           // wait for dac_out = 1 so an async clear is visible
        while (dac_out_wire !== 1'b1 && n < 3000) begin @(negedge clk); n = n + 1; end
        if (n >= 3000) $display("NOTE: dac_out never high, async-reset check is vacuous");
        #3 rst_n = 1'b0;                                 // mid-cycle, not aligned to the clock
        #1 if (dac_out_wire !== 1'b0) begin errors = errors + 1; $display("FAIL: dac_out not async-reset"); end
        repeat (3) @(negedge clk);
        if (s_out_valid !== 1'b0 || s_out !== 0 || dac_out_wire !== 1'b0) begin
            errors = errors + 1; $display("FAIL: not cleared by mid-stream reset");
        end
        @(negedge clk) rst_n = 1'b1;
        repeat (3) @(negedge clk);
        in_cnt = 0; have_even = 0; lambda = 100;
        for (i = 0; i < 100; i = i + 1) send_sample($signed($random(seed)) % 20000);
        $display("Test 4 done, errors %0d", errors);

        // ---- Test 5: sine + noise demo ----
        @(negedge clk) rst_n = 1'b0;
        repeat (3) @(negedge clk);
        @(negedge clk) rst_n = 1'b1;
        repeat (3) @(negedge clk);
        in_cnt = 0; have_even = 0; lambda = 2500;
        e_in = 0; e_dig = 0; e_dac = 0; e_sig = 0;
        for (i = 0; i < NSINE; i = i + 1) begin
            cl  = 8000.0 * $sin(6.283185307 * i / 64.0);
            r1  = $random(seed);
            noi = (r1 & 32'hFFFF) * (3000.0/65536.0) - 1500.0;       // uniform +-1500
            sig = cl + noi;
            v   = (sig >= 0) ? $rtoi(sig + 0.5) : $rtoi(sig - 0.5);
            send_sample(v);
            if (i >= 2) begin                                         // output i-1 now available
                cl  = 8000.0 * $sin(6.283185307 * (i-1) / 64.0);
                rec = (vdac[i-1] - 0.5) * 65536.0;                    // bitstream average -> counts
                e_dig = e_dig + (yout[i-1] - cl) * (yout[i-1] - cl);
                e_dac = e_dac + (rec - cl) * (rec - cl);
                e_sig = e_sig + cl * cl;
            end
        end
        e_in = (1500.0*1500.0/3.0) * (NSINE-2);                       // uniform noise variance
        $display("Test 5: SNR in   = %f dB", 10.0*$log10(e_sig/e_in));
        $display("        SNR chain = %f dB (digital s_out)", 10.0*$log10(e_sig/e_dig));
        $display("        SNR DAC   = %f dB (bitstream averaged per sample)", 10.0*$log10(e_sig/e_dac));
        if (10.0*$log10(e_in/e_dig) < 0.5) begin errors = errors + 1; $display("FAIL: no denoising gain"); end
        if (10.0*$log10(e_dig/e_dac) > 1.0) begin errors = errors + 1; $display("FAIL: DAC adds more than 1 dB error"); end

        errors = errors + range_viol + model_err + timing_err + dac_err;
        if (errors == 0) $display("PASS: all checks");
        else $display("FAILED: %0d errors (range %0d, model %0d, timing %0d, dac %0d)",
                      errors, range_viol, model_err, timing_err, dac_err);
        $finish;
    end
endmodule