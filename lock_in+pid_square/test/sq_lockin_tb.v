`timescale 1ns / 1ps
// Testbench of the square generator (lock/gen_mod_sq.v) and of the square lock-in of lock.v
// (lock_in+pid_square v2.0.0). Run with test/sq_lockin_sim.sh (Vivado 2020.1 xsim).
// Prints "TB RESULT: PASS" or "TB RESULT: FAIL (n)".
//
// Part A, gen_mod_sq alone, for several gen_mod_sqp / gen_mod_phase_sq:
//   - period of sq_ref = 2*(sqp+1) ticks, high time sqp+1 ticks
//   - sq_quad delay = floor((sqp+1)/2) ticks (90 deg when sqp is odd: 1 tick at 31.25 MHz)
//   - sq_phas delay = phase_sq ticks (phase_sq >= P taken as P-1)
//   - square_trig on the rising edge of sq_ref, once per period
//
// Part B, the whole lock module with OUT1 looped back to IN1 through a delay of D ticks:
//   out1_sw = 0, mod_out1 = 2000 -> OUT1 = +-1000 with sq_ref; signal_sw = in1.
//   sqX, sqY, sqF (registers sq?_28 / 2^13) are compared with the correlation of the
//   references with the delayed square (computed here), at 31.25 MHz (sqp = 1) and at
//   625 kHz (sqp = 99). At 31.25 MHz one tick more of delay rotates (X, Y) by 90 deg.
//   Also: gains (sqXo = sqX * 2^sg_amp, saturated), lpf order OFF (no filter),
//   OUT2 modulation with sq_quad, mod_out1 = -1 (off), first order time constant.

module sq_lockin_tb;

    reg clk = 1'b0;
    always #4 clk = ~clk;         // 125 MHz
    reg rst = 1'b1;
    integer fails = 0;

    // ------------------------------------------------------------------ Part A
    reg  [32-1:0] a_sqp = 32'd1, a_ph = 32'd0;
    wire a_ref, a_quad, a_phas, a_trig;
    gen_mod_sq i_gen (.clk(clk), .rst(rst), .sqp(a_sqp), .phase_sq(a_ph),
                      .sq_ref(a_ref), .sq_quad(a_quad), .sq_phas(a_phas), .square_trig(a_trig));

    // time (ticks) of the rising edges
    integer t = 0;
    always @(posedge clk) t <= t + 1;
    reg a_ref_d = 0, a_quad_d = 0, a_phas_d = 0;
    integer r_rise = -1, r_rise_prev = -1, r_fall = -1, q_rise = -1, p_rise = -1, trig_t = -1, n_trig = 0;
    always @(posedge clk) begin
        a_ref_d <= a_ref; a_quad_d <= a_quad; a_phas_d <= a_phas;
        if ( a_ref & ~a_ref_d) begin r_rise_prev <= r_rise; r_rise <= t; end
        if (~a_ref &  a_ref_d) r_fall <= t;
        if ( a_quad & ~a_quad_d) q_rise <= t;
        if ( a_phas & ~a_phas_d) p_rise <= t;
        if ( a_trig ) begin trig_t <= t; n_trig <= n_trig + 1; end
    end

    task check_gen(input [31:0] sqp, input [31:0] ph);
        integer P, H, Q, PH, dq, dp, per, high, wait_t, n0;
        begin
            a_sqp = sqp; a_ph = ph;
            P = 2*(sqp+1); H = sqp+1; Q = H/2; PH = (ph > P-1) ? P-1 : ph;
            wait_t = 4*P + 20;
            repeat (wait_t) @(posedge clk);
            n0 = n_trig;
            repeat (2*P) @(posedge clk);
            @(posedge clk); #1;
            per  = r_rise - r_rise_prev;
            high = (r_fall > r_rise) ? r_fall - r_rise : r_fall - r_rise_prev;
            dq   = (q_rise - r_rise + 4*P) % P;
            dp   = (p_rise - r_rise + 4*P) % P;
            if (q_rise < r_rise) dq = (q_rise - r_rise + 4*P) % P;
            if (per != P || high != H || dq != Q || dp != PH || trig_t != r_rise || (n_trig - n0) < 2 || (n_trig - n0) > 3) begin
                $display("FAIL gen sqp=%0d ph=%0d: period %0d (exp %0d), high %0d (exp %0d), quad %0d (exp %0d), phas %0d (exp %0d), trig@%0d ref@%0d, %0d trig in 2 periods",
                         sqp, ph, per, P, high, H, dq, Q, dp, PH, trig_t, r_rise, n_trig - n0);
                fails = fails + 1;
            end else
                $display("gen sqp=%0d ph=%0d: f = %.6f MHz, period %0d, high %0d, quad delay %0d (%.1f deg), phas delay %0d (%.1f deg), trig OK",
                         sqp, ph, 125.0/P, per, high, dq, 360.0*dq/P, dp, 360.0*dp/P);
        end
    endtask

    // ------------------------------------------------------------------ Part B
    reg  [32-1:0] sys_addr = 0, sys_wdata = 0;
    reg           sys_wen = 0, sys_ren = 0;
    wire [32-1:0] sys_rdata;
    wire          sys_err, sys_ack;
    reg  signed [14-1:0] in1 = 0, in2 = 0;
    wire signed [14-1:0] out1, out2, osc1, osc2;
    wire [24-1:0] pa, pb, pc, pd;
    wire [32-1:0] osc_ctrl_w;
    wire trigger, dmod, rdir;

    lock dut (
        .clk(clk), .rst(rst),
        .in1(in1), .in2(in2), .external_trigger(1'b0),
        .out1(out1), .out2(out2), .osc1(osc1), .osc2(osc2),
        .trigger(trigger), .digital_modulation(dmod), .ramp_direction_out(rdir),
        .pwm_cfg_a(pa), .pwm_cfg_b(pb), .pwm_cfg_c(pc), .pwm_cfg_d(pd),
        .osc_ctrl_w(osc_ctrl_w),
        .sys_addr(sys_addr), .sys_wdata(sys_wdata), .sys_sel(4'hF), .sys_wen(sys_wen), .sys_ren(sys_ren),
        .sys_rdata(sys_rdata), .sys_err(sys_err), .sys_ack(sys_ack)
    );

    // loop back OUT1 -> IN1 and OUT2 -> IN2 with D ticks of delay
    integer D = 0;
    reg signed [14-1:0] dl1 [0:63];
    reg signed [14-1:0] dl2 [0:63];
    integer k;
    always @(posedge clk) begin
        dl1[0] <= out1; dl2[0] <= out2;
        for (k = 1; k < 64; k = k + 1) begin dl1[k] <= dl1[k-1]; dl2[k] <= dl2[k-1]; end
        // the datapath registers of the square lock-in have no reset (v2.0.0, timing): keep X (unknown values
        // of OUT1 before the reset, a simulation artifact) out of their accumulators
        in1 <= (rst || ^dl1[D] === 1'bx) ? 14'sd0 : dl1[D];
        in2 <= (rst || ^dl2[D] === 1'bx) ? 14'sd0 : dl2[D];
    end

    task wr(input [31:0] a, input [31:0] d);
        begin
            @(negedge clk); sys_addr = a; sys_wdata = d; sys_wen = 1'b1;
            @(negedge clk); sys_wen = 1'b0;
        end
    endtask

    localparam A_OSC_A = 32'h00, A_OUT1 = 32'h10, A_OUT2 = 32'h14, A_SIG = 32'h4C, A_AMP = 32'h54, A_AMPF = 32'h58,
               A_LPF = 32'h5C, A_LPFF = 32'h60, A_MOD1 = 32'h78, A_MOD2 = 32'h7C, A_SQP = 32'h80, A_PH = 32'h84;

    // expected mean of (2 ref(t - s) - 1) * (2 ref(t - d) - 1), ref(t) = (t mod P) < H
    function real corr(input integer P, input integer s, input integer d);
        integer tt, a, b, acc;
        begin
            acc = 0;
            for (tt = 0; tt < P; tt = tt + 1) begin
                a = (((tt - s) % P + P) % P) < (P/2) ? 1 : -1;
                b = (((tt - d) % P + P) % P) < (P/2) ? 1 : -1;
                acc = acc + a*b;
            end
            corr = acc * 1.0 / P;
        end
    endfunction

    real X, Y, F, eX, eY, eF;
    integer L;   // latency of the loop inside the module (ticks), measured

    // v2.0.1: out1/out2 come 1 clock after the modulation (register before the DAC): compared with the references
    // of the clock before
    reg sq_ref_b_d1 = 1'b0, sq_quad_b_d1 = 1'b0;
    always @(posedge clk) begin sq_ref_b_d1 <= dut.sq_ref_b; sq_quad_b_d1 <= dut.sq_quad_b; end

    task measure(input integer settle);
        begin
            repeat (settle) @(posedge clk);
            #1;
            X = $itor($signed(dut.sqX_28)) / 8192.0;
            Y = $itor($signed(dut.sqY_28)) / 8192.0;
            F = $itor($signed(dut.sqF_28)) / 8192.0;
        end
    endtask

    function ok(input real m, input real e);
        ok = ( (m - e) < (2.0 + 0.005*((e<0)?-e:e)) ) && ( (e - m) < (2.0 + 0.005*((e<0)?-e:e)) );
    endfunction

    task check_lockin(input integer sqp, input integer ph, input integer dly, input integer settle);
        integer P, Q;
        begin
            P = 2*(sqp+1); Q = (sqp+1)/2;
            wr(A_SQP, sqp); wr(A_PH, ph); D = dly;
            // filter: 1.02 us (tau 4) at MHz, 32.8 us (tau 9) at kHz (2nd order)
            wr(A_LPF,  (2<<5) + ((P > 10) ? 9 : 4));
            wr(A_LPFF, (2<<5) + ((P > 10) ? 9 : 4));
            measure(settle);
            eX = 1000.0*corr(P, 0, dly+L); eY = 1000.0*corr(P, Q, dly+L); eF = 1000.0*corr(P, ph, dly+L);
            if (ok(X,eX) && ok(Y,eY) && ok(F,eF))
                $display("lock-in f=%.4f MHz D=%0d ph=%0d: X=%8.2f Y=%8.2f F=%8.2f  (expected %8.2f %8.2f %8.2f) OK",
                         125.0/P, dly, ph, X, Y, F, eX, eY, eF);
            else begin
                $display("FAIL lock-in f=%.4f MHz D=%0d ph=%0d: X=%8.2f Y=%8.2f F=%8.2f  (expected %8.2f %8.2f %8.2f)",
                         125.0/P, dly, ph, X, Y, F, eX, eY, eF);
                fails = fails + 1;
            end
        end
    endtask

    integer i, n_on, v;
    real tau_meas, x63;

    initial begin
        for (k = 0; k < 64; k = k + 1) begin dl1[k] = 0; dl2[k] = 0; end
        repeat (10) @(posedge clk);
        rst = 1'b0;

        // ---------------- Part A
        check_gen(1, 0);    check_gen(1, 1);    check_gen(1, 2);   check_gen(1, 3);  check_gen(1, 9);
        check_gen(3, 0);    check_gen(3, 5);
        check_gen(2, 4);    check_gen(0, 1);
        check_gen(99, 37);  check_gen(99, 150); check_gen(1249, 625);
        check_gen(1, 0);

        // ---------------- Part B
        wr(A_OUT1, 0); wr(A_OUT2, 0);
        wr(A_SIG, 0);                  // signal_i = in1
        wr(A_AMP, 0); wr(A_AMPF, 0);
        wr(A_LPF,  (2<<5) + 4);        // 2nd order, tau 4: 8 ns * 2^7 = 1.02 us
        wr(A_LPFF, (2<<5) + 4);
        wr(A_MOD1, 2000);              // OUT1 = +-1000 with sq_ref
        wr(A_MOD2, -1);

        // latency of the loop: 625 kHz (P = 200), D = 0: X = 1000 (1 - 4 L / P)
        L = 0;
        wr(A_SQP, 99); wr(A_PH, 0); D = 0;
        wr(A_LPF,  (2<<5) + 9);
        measure(100000);
        L = $rtoi( (1.0 - X/1000.0) * 200.0 / 4.0 + 0.5 );
        $display("loop latency inside the module (sq_ref -> OUT1 ... IN1 -> product): %0d ticks (X = %.2f at D = 0)", L, X);
        if (L < 1 || L > 8) begin $display("FAIL latency"); fails = fails + 1; end

        // 31.25 MHz: four delays, the (X, Y) pair rotates 90 deg per tick
        for (i = 0; i < 4; i = i + 1) check_lockin(1, 0, i, 6000);
        check_lockin(1, 1, 0, 6000);
        check_lockin(1, 2, 1, 6000);
        check_lockin(1, 3, 3, 6000);
        // 625 kHz
        check_lockin(99, 0,  0, 100000);
        check_lockin(99, 30, 10, 100000);
        check_lockin(99, 120, 25, 100000);
        check_lockin(99, 199, 60, 100000);
        // 20.83 MHz (sqp = 2, quadrature 60 deg)
        check_lockin(2, 2, 1, 6000);

        // gains: sqp = 1, D giving X = +1000 exactly
        D = (4 - (L % 4)) % 4;
        wr(A_SQP, 1); wr(A_PH, 0);
        wr(A_LPF,  (2<<5) + 4);
        wr(A_AMP, 3);                  // x8
        measure(6000);
        if (dut.sqXo !== 14'sd8000) begin $display("FAIL gain x8: sqXo = %0d (expected 8000)", dut.sqXo); fails = fails + 1; end
        else $display("gain x8: sqXo = %0d OK", dut.sqXo);
        wr(A_AMP, 4);                  // x16 -> saturated
        measure(100);
        if (dut.sqXo !== 14'sd8191) begin $display("FAIL gain x16: sqXo = %0d (expected 8191, saturated)", dut.sqXo); fails = fails + 1; end
        else $display("gain x16: sqXo = %0d (saturated) OK", dut.sqXo);
        wr(A_MOD1, 6000);              // OUT1 = +-3000, D such that X = -3000: x4 -> -8192 saturated
        D = (D + 2) % 64;
        wr(A_AMP, 2);
        measure(6000);
        if (dut.sqXo !== -14'sd8192) begin $display("FAIL gain x4 negative: sqXo = %0d (expected -8192)", dut.sqXo); fails = fails + 1; end
        else $display("gain x4, X = -3000: sqXo = %0d (saturated) OK", dut.sqXo);
        wr(A_AMP, 0); wr(A_MOD1, 2000);
        D = (D + 2) % 64;

        // OUT1 must be +-1000 following sq_ref (out1_sw = 0)
        n_on = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk); #1;
            if (out1 !== (sq_ref_b_d1 ? 14'sd1000 : -14'sd1000)) n_on = n_on + 1;
        end
        if (n_on != 0) begin $display("FAIL OUT1 modulation: %0d samples differ from +-1000 (sq_ref)", n_on); fails = fails + 1; end
        else $display("OUT1 = +-1000 with sq_ref OK");
        // OUT2 with sq_quad
        wr(A_MOD2, 1000);
        n_on = 0;
        repeat (5) @(posedge clk);
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk); #1;
            if (out2 !== (sq_quad_b_d1 ? 14'sd500 : -14'sd500)) n_on = n_on + 1;
        end
        if (n_on != 0) begin $display("FAIL OUT2 modulation: %0d samples differ from +-500 (sq_quad)", n_on); fails = fails + 1; end
        else $display("OUT2 = +-500 with sq_quad OK");
        wr(A_MOD2, -1);
        // modulation off
        wr(A_MOD1, -1);
        repeat (5) @(posedge clk);
        n_on = 0;
        for (i = 0; i < 40; i = i + 1) begin @(posedge clk); #1; if (out1 !== 14'sd0) n_on = n_on + 1; end
        if (n_on != 0) begin $display("FAIL mod_out1 = -1 does not switch the modulation off"); fails = fails + 1; end
        else $display("mod_out1 = -1: OUT1 = 0 OK");
        wr(A_MOD1, 2000);

        // order OFF: no filter, sqX follows the product (at 31.25 MHz with X = 0 it alternates +-1000)
        D = (4 - (L % 4) + 1) % 4;     // X = 0, Y = 1000
        wr(A_LPF, 0);
        repeat (50) @(posedge clk);
        n_on = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk); #1;
            v = $signed(dut.sqX_28) / 8192;
            if (v != 1000 && v != -1000) n_on = n_on + 1;
        end
        if (n_on != 0) begin $display("FAIL lpf order OFF: sqX is not +-1000"); fails = fails + 1; end
        else $display("lpf order OFF: sqX = +-1000 (no filter) OK");

        // first order time constant: tau 7 -> 8 ns * 2^10 = 1024 ticks. Step: modulation on, D for X = +1000
        D = (4 - (L % 4)) % 4;
        wr(A_LPF, (1<<5) + 7);
        wr(A_MOD1, -1);
        repeat (20000) @(posedge clk);
        wr(A_MOD1, 2000);
        i = 0;
        x63 = 1000.0 * (1.0 - 1.0/2.718281828);
        X = 0;
        while (X < x63 && i < 5000) begin
            @(posedge clk); #1; i = i + 1;
            X = $itor($signed(dut.sqX_28)) / 8192.0;
        end
        tau_meas = i;
        if (tau_meas < 1024*0.95 || tau_meas > 1024*1.05 + 10) begin
            $display("FAIL first order: 63%% after %0d ticks (expected ~1024)", i); fails = fails + 1;
        end else $display("first order tau 7: 63%% of the step after %0d ticks (expected 1024 + latency) OK", i);

        if (fails == 0) $display("TB RESULT: PASS");
        else            $display("TB RESULT: FAIL (%0d)", fails);
        $finish;
    end

endmodule
