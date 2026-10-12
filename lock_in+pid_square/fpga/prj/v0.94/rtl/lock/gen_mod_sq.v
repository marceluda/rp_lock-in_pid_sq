`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// gen_mod_sq: square modulation generator of lock_in+pid_square (Square lock-in+PID).
//
// Square counterpart of the square generator of gen_mod2.v (lock_in+pid, "sq_ref",
// "sq_quad", "sq_phas"), written again for this App (v2.0.0):
//
//   - one counter c over the whole period P = 2*(sqp+1) clock ticks (8 ns each):
//       f = 125 MHz / (2*(sqp+1))      sqp = 0 -> 62.5 MHz, 1 -> 31.25 MHz, ..., 2^32-1 -> 0.029 Hz
//   - sq_ref  = 1 during the first half of the period (c < sqp+1), 0 during the second half
//   - sq_quad = sq_ref delayed by Q = floor((sqp+1)/2) ticks (a quarter of the period: 90 deg).
//               Exact quadrature when sqp is odd (P multiple of 4 ticks), e.g. sqp = 1:
//               31.25 MHz, P = 4 ticks, sq_quad 1 tick (90 deg) behind sq_ref.
//               With sqp even the delay is rounded down (sqp = 2: 60 deg); sqp = 0: no quadrature.
//   - sq_phas = sq_ref delayed by phase_sq ticks (0 .. P-1, i.e. 360 deg * phase_sq / P);
//               values >= P are taken as P-1.
//   - square_trig: one tick pulse at the start of every period (rising edge of sq_ref).
//
// The three outputs are computed in a 3 stage pipeline from the same counter value, so they
// keep their relative timing exactly and all of them have the same latency (3 ticks).
// The period/phase registers can change at any time: the counter wraps as soon as it is
// at or beyond the new end of period.
//
//////////////////////////////////////////////////////////////////////////////////

module gen_mod_sq
(
    input                    clk,
    input                    rst,
    input           [32-1:0] sqp,          // half period - 1 (ticks)
    input           [32-1:0] phase_sq,     // delay of sq_phas (ticks)
    output reg               sq_ref,       // reference
    output reg               sq_quad,      // quadrature (90 deg behind sq_ref)
    output reg               sq_phas,      // reference delayed by phase_sq
    output reg               square_trig   // start of the period
);

    // static values, registered (they only change when the registers are written)
    // v2.0.0 (timing): only the counter has a reset; the other registers start at 0 when the FPGA is configured
    // and are refreshed every clock (the reset net of adc_clk has a large fan-out)
    reg  [33-1:0] half    = 33'd1;   // H = sqp + 1                 (ticks of each half period)
    reg  [34-1:0] per_m1  = 34'd1;   // P - 1 = 2*sqp + 1           (last value of the counter)
    reg  [34-1:0] per     = 34'd2;   // P = 2*sqp + 2
    reg  [33-1:0] quarter = 33'd0;   // Q = floor(H/2)
    reg  [34-1:0] phas    = 34'd0;   // phase_sq limited to P-1

    always @(posedge clk) begin
        half     <= {1'b0, sqp} + 33'd1 ;
        per_m1   <= {1'b0, sqp, 1'b1} ;          // 2*sqp + 1
        per      <= {1'b0, sqp, 1'b1} + 34'd1 ;  // 2*sqp + 2
        quarter  <= half >> 1 ;
        phas     <= ( {2'b0, phase_sq} > per_m1 ) ? per_m1 : {2'b0, phase_sq} ;
    end

    // period counter 0 .. P-1
    reg  [34-1:0] c ;
    always @(posedge clk)
    if (rst)
        c <= 34'd0 ;
    else
        c <= ( c >= per_m1 ) ? 34'd0 : c + 34'd1 ;

    // stage 1: differences
    reg  [34-1:0] c1 = 34'd0 ;
    reg  signed [35-1:0] dq1 = 35'sd0, dp1 = 35'sd0 ;
    // stage 2: modulo P
    reg  [34-1:0] c2 = 34'd0 ;
    reg  [35-1:0] wq2 = 35'd0, wp2 = 35'd0 ;

    initial begin sq_ref = 1'b0; sq_quad = 1'b0; sq_phas = 1'b0; square_trig = 1'b0; end

    always @(posedge clk) begin
        // 1: c - Q and c - phase (may be negative)
        c1  <= c ;
        dq1 <= $signed({1'b0, c}) - $signed({2'b0, quarter}) ;
        dp1 <= $signed({1'b0, c}) - $signed({1'b0, phas}) ;
        // 2: wrap into 0 .. P-1
        c2  <= c1 ;
        wq2 <= dq1[34] ? dq1 + $signed({1'b0, per}) : dq1 ;
        wp2 <= dp1[34] ? dp1 + $signed({1'b0, per}) : dp1 ;
        // 3: first half of the period -> 1
        sq_ref      <= ( {1'b0, c2} < {2'b0, half} ) ;
        sq_quad     <= ( wq2        < {2'b0, half} ) ;
        sq_phas     <= ( wp2        < {2'b0, half} ) ;
        square_trig <= ( c2 == 34'd0 ) ;
    end

endmodule

/*
gen_mod_sq i_gen_mod_sq ( .clk(clk), .rst(rst), .sqp(SQP), .phase_sq(PHASE),
                          .sq_ref(REF), .sq_quad(QUAD), .sq_phas(PHAS), .square_trig(TRIG) );
*/
