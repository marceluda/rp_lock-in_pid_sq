`timescale 1ns / 1ps
// lock_latency_tb.sv (lock_in+pid_square v2.0.1, from lock_in+pid_harmonic v2.3.19): the lock.v of this version (N) side by side with the one of a previous
// version (O, modules renamed with the prefix o_ by test/lock_latency_sim.sh), same bus writes. Checks that
// every signal of N is the one of O delayed by the documented latency (doc/lock_latency.md), bit by bit,
// and measures the latency of a step.
// lock_in+pid_square: the generator is the same (already registered); its references reach the lock-in 1 clock
// later (compensation of the output register). With dly_in = 1, N gets in1/in2 1 clock later (as in a real loop):
// then every signal of N is the one of O delayed by 1 + the registers added in v2.0.1 (the square lock-in itself
// is not changed: sqXo..sqFo = 1). With dly_in = 0 only the paths that do not use the references are compared.
// Run with test/lock_latency_sim.sh (Vivado 2020.1 xsim). Prints "TB RESULT: PASS" or "TB RESULT: FAIL".
//
// Parts:
//   U1  sat14 (new, mask) vs o_sat14 (old, barrel shift): RES 64 and 15, random inputs, lim 0..80
//   U2  shift_sat14 vs o_satprotect2(W->RO) + o_satprotect2(17->14): X (38/53/38/5) and F (28/43/28/4)
//   S1  "lock mode" (lpf_F0 33, sg_amp0 5, error = Yo, PID A on error, PID B on F1o, out1/out2 = ctrl_A/B)
//   S2  both LPF bypassed, sg_amp 0..31 (saturation and wrap of the shift), PID A on Xo, PID B on F3o
//   S3  PIDs on in1 / in2, PSR/ISR/DSR/SAT/kd/ki swept (integrator saturation, sat14)
//   S4  modulation on (out1 = in1 + mod, out2 = mod), S4b the same without delaying in1 (modulation +2,
//       references +1: the modulation leaves 1 clock later with respect to the reference of the lock-in)
//   S5  level trigger of lock_ctrl on Xo: the lock comes 2 clocks later (3 with the delayed input)
//   S6  step response: first clock in which each output moves after a step of in1
module lock_latency_tb;

    reg clk = 1'b0;
    always #4 clk = ~clk;

    reg                rst = 1'b1;
    reg  signed [13:0] in1 = 14'sd0, in2 = 14'sd0;
    reg  signed [13:0] in1_d = 14'sd0, in2_d = 14'sd0;   // in1/in2 one clock later
    bit                dly_in = 0;                       // N gets in1_d/in2_d
    wire signed [13:0] n_in1 = dly_in ? in1_d : in1;
    wire signed [13:0] n_in2 = dly_in ? in2_d : in2;
    always @(posedge clk) begin in1_d <= in1; in2_d <= in2; end
    reg         [31:0] addr = 32'd0, wdata = 32'd0;
    reg                wen = 1'b0;

    wire signed [13:0] n_out1, n_out2, n_osc1, n_osc2, o_out1, o_out2, o_osc1, o_osc2;

    lock N (
        .clk(clk), .rst(rst), .in1(n_in1), .in2(n_in2), .external_trigger(1'b0),
        .out1(n_out1), .out2(n_out2), .osc1(n_osc1), .osc2(n_osc2),
        .trigger(), .digital_modulation(), .ramp_direction_out(),
        .pwm_cfg_a(), .pwm_cfg_b(), .pwm_cfg_c(), .pwm_cfg_d(), .osc_ctrl_w(),
        .sys_addr(addr), .sys_wdata(wdata), .sys_sel(4'hF), .sys_wen(wen), .sys_ren(1'b0),
        .sys_rdata(), .sys_err(), .sys_ack()
    );

    o_lock O (
        .clk(clk), .rst(rst), .in1(in1), .in2(in2), .external_trigger(1'b0),
        .out1(o_out1), .out2(o_out2), .osc1(o_osc1), .osc2(o_osc2),
        .trigger(), .digital_modulation(), .ramp_direction_out(),
        .pwm_cfg_a(), .pwm_cfg_b(), .pwm_cfg_c(), .pwm_cfg_d(), .osc_ctrl_w(),
        .sys_addr(addr), .sys_wdata(wdata), .sys_sel(4'hF), .sys_wen(wen), .sys_ren(1'b0),
        .sys_rdata(), .sys_err(), .sys_ack()
    );

    // ---------------------------------------------------------------- signals compared
    localparam NS = 20;
    localparam MAXC = 160000;
    string names [NS] = '{"sqXo","sqYo","sqFo","sqXo","sqYo","pidA_out_cache","pidB_out_cache","pidA_out","pidB_out",
                          "error","out1","out2","osc1","osc2","lock_ctrl_signal","X_28","ctrl_A","lock_status",
                          "sq_ref","square_trig"};
    int hn [NS][];
    int ho [NS][];
    int cyc = 0;
    bit rec = 0;

    initial begin
        for (int k = 0; k < NS; k++) begin hn[k] = new[MAXC]; ho[k] = new[MAXC]; end
    end

    always @(posedge clk) if (rec) begin
        #1;
        if (cyc < MAXC) begin
            hn[0][cyc]  = N.sqXo;              ho[0][cyc]  = O.sqXo;
            hn[1][cyc]  = N.sqYo;              ho[1][cyc]  = O.sqYo;
            hn[2][cyc]  = N.sqFo;             ho[2][cyc]  = O.sqFo;
            hn[3][cyc]  = N.sqXo;             ho[3][cyc]  = O.sqXo;
            hn[4][cyc]  = N.sqYo;             ho[4][cyc]  = O.sqYo;
            hn[5][cyc]  = N.pidA_out_cache;  ho[5][cyc]  = O.pidA_out_cache;
            hn[6][cyc]  = N.pidB_out_cache;  ho[6][cyc]  = O.pidB_out_cache;
            hn[7][cyc]  = N.pidA_out;        ho[7][cyc]  = O.pidA_out;
            hn[8][cyc]  = N.pidB_out;        ho[8][cyc]  = O.pidB_out;
            hn[9][cyc]  = N.error;           ho[9][cyc]  = O.error;
            hn[10][cyc] = n_out1;            ho[10][cyc] = o_out1;
            hn[11][cyc] = n_out2;            ho[11][cyc] = o_out2;
            hn[12][cyc] = n_osc1;            ho[12][cyc] = o_osc1;
            hn[13][cyc] = n_osc2;            ho[13][cyc] = o_osc2;
            hn[14][cyc] = N.lock_ctrl_signal; ho[14][cyc] = O.lock_ctrl_signal;
            hn[15][cyc] = N.sqX_28;            ho[15][cyc] = O.sqX_28;
            hn[16][cyc] = N.ctrl_A;          ho[16][cyc] = O.ctrl_A;
            hn[17][cyc] = N.lock_status;     ho[17][cyc] = O.lock_status;
            hn[18][cyc] = N.sq_ref;         ho[18][cyc] = O.sq_ref;
            hn[19][cyc] = N.square_trig;   ho[19][cyc] = O.square_trig;
        end
        cyc++;
    end

    int fails = 0;
    int checks = 0;

    // compare N[t] with O[t-L] for t in [t0, cyc-1]; L < 0: not compared
    task automatic compare(input string scen, input int L [NS], input int t0);
        for (int k = 0; k < NS; k++) begin
            int bad = 0, first = -1, nchg = 0;
            if (L[k] < 0) continue;
            for (int t = t0; t < cyc && t < MAXC; t++) begin
                if (hn[k][t] !== ho[k][t-L[k]]) begin bad++; if (first < 0) first = t; end
                if (t > t0 && ho[k][t-L[k]] != ho[k][t-L[k]-1]) nchg++;
            end
            checks++;
            if (bad) begin
                fails++;
                $display("FAIL %s %-16s latency %0d: %0d of %0d clocks differ, first at %0d (new %0d, old %0d)",
                         scen, names[k], L[k], bad, cyc - t0, first, hn[k][first], ho[k][first-L[k]]);
            end else
                $display("ok   %s %-16s = old delayed %0d clock(s) (%0d ns), %0d clocks, %0d changes",
                         scen, names[k], L[k], 8*L[k], cyc - t0, nchg);
        end
    endtask

    // ---------------------------------------------------------------- bus and stimulus
    task automatic wr(input [31:0] a, input [31:0] d);
        @(negedge clk); addr = a; wdata = d; wen = 1'b1;
        @(negedge clk); wen = 1'b0;
    endtask

    bit stim_on = 0;
    real A1 = 3000.0, A2 = 1500.0, NOISE = 200.0, P1 = 2520.0, P2 = 97000.0;
    int  t_stim = 0;
    reg [31:0] lfsr = 32'hACE1_2345;
    function automatic int clamp14(input real v);
        if (v >  8191.0) return  8191;
        if (v < -8192.0) return -8192;
        return $rtoi(v);
    endfunction
    // the inputs change at the rising edge, like the ADC registers of red_pitaya_top.sv (adc_dat)
    bit step_on = 0;
    always @(posedge clk) begin
        lfsr = {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
        if (step_on) begin
            in1 <= 14'sd6000; in2 <= 14'sd0;
        end else if (stim_on) begin
            real s, nz;
            nz  = (real'(lfsr[11:0]) / 4096.0 - 0.5) * 2.0 * NOISE;
            s   = A1*$sin(6.283185307*t_stim/P1) + A2*$sin(6.283185307*t_stim/P2 + 1.0) + nz;
            in1 <= clamp14(s);
            in2 <= clamp14(0.5*s + 0.7*A1*$cos(6.283185307*t_stim/(P1/2.0)) - nz);
            t_stim++;
        end else begin
            in1 <= 14'sd0; in2 <= 14'sd0;
        end
    end

    // reset both, keep the inputs at 0 while configuring (the LPFs stay at 0), then start
    task automatic start_scen();
        stim_on = 0; rec = 0;
        @(negedge clk); rst = 1'b1;
        repeat (5) @(negedge clk);
        rst = 1'b0;
        repeat (3) @(negedge clk);
    endtask
    task automatic run(input int n);
        t_stim = 0; cyc = 0; rec = 1; stim_on = 1;
        repeat (n) @(posedge clk);
        @(negedge clk); rec = 0; stim_on = 0;
    endtask

    localparam OSCA=32'h00, OSCB=32'h04, OUT1=32'h10, OUT2=32'h14, LCTRL=32'h18, TVAL=32'h20, TSW=32'h28,
               SIGSW=32'h4C, SGSQ=32'h54, SGSQF=32'h58, LPFSQ=32'h5C, LPFSQF=32'h60, ERRSW=32'h64,
               MOD1=32'h78, MOD2=32'h7C, SQP=32'h80, PHSQ=32'h84,
               ASW=32'hEC, APSR=32'hF0, AISR=32'hF4, ADSR=32'hF8, ASAT=32'hFC, ASP=32'h100, AKP=32'h104, AKI=32'h108, AKD=32'h10C,
               BSW=32'h120, BPSR=32'h124, BISR=32'h128, BDSR=32'h12C, BSAT=32'h130, BSP=32'h134, BKP=32'h138, BKI=32'h13C, BKD=32'h140;

    // ---------------------------------------------------------------- U1, U2: unit equivalences
    reg  signed [63:0] u64;  reg [63:0] l64;  wire signed [63:0] s64n, s64o;
    reg  signed [14:0] u15;  reg [14:0] l15;  wire signed [14:0] s15n, s15o;
    sat14   #(.RES(64)) u_n64 (.in(u64), .lim(l64), .out(s64n));
    o_sat14 #(.RES(64)) u_o64 (.in(u64), .lim(l64), .out(s64o));
    sat14   #(.RES(15)) u_n15 (.in(u15), .lim(l15), .out(s15n));
    o_sat14 #(.RES(15)) u_o15 (.in(u15), .lim(l15), .out(s15o));

    function automatic logic [63:0] rnd_mag(input int width);   // random value with a random number of significant bits
        int b; logic [63:0] v;
        b = $urandom_range(width-1, 0);
        v = {$urandom, $urandom};
        v = v & ((64'd1 << b) - 1);
        if ($urandom_range(1,0)) v = ~v;               // negative: leading ones
        return v;
    endfunction

    task automatic unit_tests();
        int bad;
        bad = 0;
        for (int i = 0; i < 200000; i++) begin
            u64 = rnd_mag(64); l64 = $urandom_range(80, 0);
            u15 = rnd_mag(15); l15 = $urandom_range(20, 0);
            #1;
            if (s64n !== s64o) begin bad++; if (bad < 4) $display("U1 RES64 in %0d lim %0d new %0d old %0d", u64, l64, s64n, s64o); end
            if (s15n !== s15o) begin bad++; if (bad < 4) $display("U1 RES15 in %0d lim %0d new %0d old %0d", u15, l15, s15n, s15o); end
        end
        checks++; if (bad) begin fails++; $display("FAIL U1 sat14: %0d differences", bad); end
        else $display("ok   U1 sat14 (mask) = old sat14 (barrel shift): 2 x 200000 random vectors, lim 0..80 / 0..20");
    endtask

    // ---------------------------------------------------------------- scenarios
    int L [NS];
    // x: sqXo..sqFo, pa/pb: PID A/B, err, o1/o2: out1/out2, s1/s2: osc1/osc2, sig: signal of lock_ctrl,
    // x28: sqX_28 (bus), ca: ctrl_A, stat: lock_status; sq_ref and square_trig: 0 (generator unchanged)
    task automatic setL(input int x, input int pa, input int pb, input int err, input int o1, input int o2,
                        input int s1, input int s2, input int sig, input int x28, input int ca, input int stat);
        L = '{x, x, x, x, x, pa, pb, pa, pb, err, o1, o2, s1, s2, sig, x28, ca, stat, 0, 0};
    endtask

    task automatic config_sq(input int lpf, input int lpff, input int g, input int gf, input int sqp);
        wr(SIGSW, 0); wr(LPFSQ, lpf); wr(LPFSQF, lpff); wr(SGSQ, g); wr(SGSQF, gf); wr(SQP, sqp); wr(PHSQ, sqp/3);
    endtask

    int t_lock_n, t_lock_o;

    initial begin
        $display("lock_latency_tb: new lock.v (N) vs old lock.v (O)");
        unit_tests();

        // S1 lock mode: LPF 2nd order, error = sqYo, PID A on error, PID B on sqFo, out = ctrl ----------
        for (int q = 0; q < 3; q++) begin
            start_scen();
            config_sq(64 + 5 + 4*q, 32 + 3, 3, 2, (q == 0) ? 1 : (q == 1) ? 7 : 1259);
            wr(ERRSW, 2);
            wr(ASW, 0); wr(AKP, -250 & 16'h3FFF); wr(AKI, -20 & 16'h3FFF); wr(APSR, 3); wr(AISR, 8); wr(ASAT, 13);
            wr(BSW, 3); wr(BKP, 100); wr(BKI, 5); wr(BKD, 50); wr(BPSR, 2); wr(BISR, 5); wr(BDSR, 0); wr(BSAT, 10);
            wr(OUT1, 12); wr(OUT2, 13); wr(MOD1, 14'h3FFF); wr(MOD2, 14'h3FFF);
            wr(OSCA, 15); wr(OSCB, 10); wr(TSW, 1); wr(LCTRL, 12);
            repeat (5) @(negedge clk);
            A1 = 3000.0; A2 = 1500.0; NOISE = 200.0;
            dly_in = 1;
            run(40000);
            setL(1, 2, 2, 1, 3, 3, 1, 2, 1, 1, 2, 0);
            compare($sformatf("S1 sqp%0d", q), L, 20);
        end

        // S2 LPF off, gains 0..15 --------------------------------------------------------------------
        for (int g = 0; g < 16; g += 3) begin
            start_scen();
            config_sq(0, 0, g, (g+5) % 16, 7);
            wr(ERRSW, 1);
            wr(ASW, 1); wr(AKP, 1000); wr(AKI, 3); wr(APSR, 0); wr(AISR, 2); wr(ASAT, 13);
            wr(BSW, 3); wr(BKP, -2000); wr(BKI, -1); wr(BKD, 300); wr(BPSR, 1); wr(BISR, 0); wr(BDSR, 0); wr(BSAT, 12);
            wr(OUT1, 12); wr(OUT2, 13); wr(MOD1, 14'h3FFF); wr(MOD2, 14'h3FFF);
            wr(OSCA, 16); wr(OSCB, 17); wr(TSW, 3); wr(LCTRL, 12);
            repeat (5) @(negedge clk);
            A1 = 7000.0; A2 = 1000.0; NOISE = 1500.0;
            dly_in = 1;
            run(8000);
            setL(1, 2, 2, 1, 3, 3, 1, 1, 1, 1, 2, 0);
            compare($sformatf("S2 sg%0d", g), L, 20);
        end

        // S3 PIDs on in1 / in2 (no references: in1 not delayed) ---------------------------------------
        for (int j = 0; j < 10; j++) begin
            start_scen();
            config_sq(64 + 5, 32 + 5, 3, 0, 7);
            wr(ERRSW, 6);
            wr(ASW, 7); wr(AKP, 3000 - 700*j); wr(AKI, 200 + 50*j); wr(AKD, 1000); wr(APSR, j % 5); wr(AISR, j); wr(ADSR, j % 6); wr(ASAT, 13 - j);
            wr(BSW, 8); wr(BKP, -1500); wr(BKI, -(30*j+1) & 16'h3FFF); wr(BKD, 0); wr(BPSR, (j+2) % 5); wr(BISR, 9 - j); wr(BDSR, 0); wr(BSAT, 4 + j);
            wr(ASP, 100*j); wr(BSP, -50*j & 16'h3FFF);
            wr(OUT1, 12); wr(OUT2, 11); wr(MOD1, 14'h3FFF); wr(MOD2, 14'h3FFF);
            wr(OSCA, 4); wr(OSCB, 11); wr(TSW, 10); wr(LCTRL, 12);
            repeat (5) @(negedge clk);
            A1 = 2500.0; A2 = 3000.0; NOISE = 300.0;
            dly_in = 0;
            run(12000);
            setL(-1, 1, 1, 0, 2, 2, 1, 1, 1, -1, 1, 0);
            compare($sformatf("S3 j%0d", j), L, 20);
        end

        // S4 modulation: out1 = in1 + mod, out2 = mod only (in1 not delayed: +1 both) -------------------
        start_scen();
        config_sq(64 + 5, 32 + 5, 3, 0, 7);
        wr(OUT1, 1); wr(OUT2, 0); wr(MOD1, 100); wr(MOD2, 2000);
        wr(OSCA, 19); wr(OSCB, 20); wr(LCTRL, 0);
        repeat (5) @(negedge clk);
        A1 = 3000.0; A2 = 1500.0; NOISE = 200.0;
        dly_in = 0;
        run(10000);
        setL(-1, -1, -1, -1, 1, 1, 1, 1, -1, -1, -1, 0);
        compare("S4", L, 20);

        // S5 level trigger on sqXo ----------------------------------------------------------------------
        start_scen();
        config_sq(0, 0, 2, 0, 1259);
        wr(TSW, 1); wr(TVAL, 3000);
        wr(LCTRL, (1<<10) | (2<<8) | (1<<6));
        repeat (5) @(negedge clk);
        A1 = 3000.0; A2 = 1500.0; NOISE = 200.0;
        dly_in = 1;
        t_stim = 0; cyc = 0; rec = 1; stim_on = 1;
        repeat (2000) @(negedge clk);
        wr(LCTRL, (1<<10) | (2<<8) | (1<<6) | 2);
        repeat (18000) @(negedge clk);
        rec = 0; stim_on = 0;
        t_lock_n = -1; t_lock_o = -1;
        for (int t = 1; t < cyc; t++) begin
            if (t_lock_n < 0 && ((hn[17][t] >> 1) & 1) && !((hn[17][t-1] >> 1) & 1)) t_lock_n = t;
            if (t_lock_o < 0 && ((ho[17][t] >> 1) & 1) && !((ho[17][t-1] >> 1) & 1)) t_lock_o = t;
        end
        checks++;
        if (t_lock_o < 0 || t_lock_n != t_lock_o + 1) begin
            fails++; $display("FAIL S5 level trigger on sqXo: locked at clock %0d (old %0d), expected old + 1", t_lock_n, t_lock_o);
        end else
            $display("ok   S5 level trigger on sqXo: locked at clock %0d, old at %0d (+1 = the delayed input; sqXo unchanged)", t_lock_n, t_lock_o);
        setL(1, -1, -1, -1, -1, -1, -1, -1, 1, 1, -1, -1);
        compare("S5", L, 20);

        // S6 steps
        step_test("pidA_out (PID A on in1, kp only)", 1, 7, 0);
        step_test("out1 = ctrl_A (PID A on in1)", 2, 7, 0);
        step_test("out1 = in1", 3, 7, 0);

        $display("checks %0d, fails %0d", checks, fails);
        if (fails == 0) $display("TB RESULT: PASS"); else $display("TB RESULT: FAIL");
        $finish;
    end

    task automatic step_test(input string what, input int obs, input int asw, input int dly);
        int k, tn, to;
        start_scen();
        dly_in = dly;
        config_sq(0, 0, 0, 0, 7);
        wr(ASW, asw); wr(AKP, 4000); wr(AKI, 0); wr(AKD, 0); wr(APSR, 0); wr(AISR, 8); wr(ASAT, 13);
        wr(OUT1, (obs == 3) ? 1 : 12); wr(MOD1, 14'h3FFF); wr(LCTRL, 8);
        repeat (300) @(negedge clk);
        k = (obs == 1) ? 7 : 10;
        cyc = 0; rec = 1;
        repeat (100) @(negedge clk);
        step_on = 1;
        repeat (400) @(negedge clk);
        rec = 0; step_on = 0;
        tn = -1; to = -1;
        for (int t = 1; t < cyc; t++) begin
            if (tn < 0 && hn[k][t] != hn[k][t-1]) tn = t;
            if (to < 0 && ho[k][t] != ho[k][t-1]) to = t;
        end
        $display("step %-36s: first change %0d clocks after in1 (old %0d): +%0d clocks = %0d ns",
                 what, tn - 100 - dly, to - 100, tn - to - dly, 8*(tn - to - dly));
    endtask

endmodule
