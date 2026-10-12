`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// LP_filter_sq: first order low pass filter stage of the square lock-in of
// lock_in+pid_square (v2.0.0).
//
//     y[n+1] = y[n] + ( x[n] - y[n-1] ) / 2^k        k = tau + BASE   (tau limited to TMAX)
//
// implemented with an accumulator: sum <= sum + x - y ; y <= sum >>> k (registered, in two steps).
// In steady state y = x (unity DC gain) and the time constant is
//
//     tau_s = 8 ns * 2^k      (k = BASE .. BASE+TMAX; BASE=3, TMAX=27: 64 ns .. 8.6 s)
//
// The feedback uses y two ticks late (registered input and two-step shift, for timing). With k >= 3
// the extra poles are small and the response is the one of the ideal first order filter.
//
// on = 0: bypass (out = in). The accumulator keeps running, so switching the filter on
// later starts from the current mean value.
//
// Sizes: |in| < 2^(R-1); the accumulator holds in * 2^k: S >= R + BASE + TMAX + 1.
//
//////////////////////////////////////////////////////////////////////////////////

module LP_filter_sq #(
    parameter R    = 28,   // width of in / out
    parameter S    = 64,   // width of the accumulator
    parameter BASE = 3,    // minimum shift
    parameter TMAX = 27    // maximum tau
)(
    input                    clk,
    input                    rst,
    input                    on,       // 1: filter, 0: bypass
    input           [ 5-1:0] tau,      // time constant: 8 ns * 2^(tau+BASE)
    input  signed   [ R-1:0] in,
    output signed   [ R-1:0] out
);

    // v2.0.0 (timing): the accumulator is reset by a local copy of rst (one per filter stage), so the reset net of
    // adc_clk (large fan-out, its paths to the R pins failed timing) only drives this register.
    // The input is registered (in_r: the bypass mux of the previous stage and the selector do not reach the
    // 64-bit adder) and the variable shift is done in two registered steps (multiples of 8, then 0..7), so
    // y is the shift of the accumulator of 2 ticks before: z^3 - z^2 + a = 0 with a = 2^-k <= 1/8 has its
    // dominant root at ~1 - a (the time constant of the ideal filter) and the other two inside |z| < 0.6.
    (* max_fanout = 128 *) reg rst_r = 1'b1 ;
    reg  signed [R-1:0] in_r = {R{1'b0}} ;
    reg  signed [S-1:0] sum  = {S{1'b0}} ;
    reg  signed [S-1:0] yc   = {S{1'b0}} ;
    reg  signed [R-1:0] y    = {R{1'b0}} ;
    reg         [ 6-1:0] k   = BASE ;
    reg         [ 3-1:0] kf  = BASE ;

    always @(posedge clk) begin
        rst_r <= rst ;
        k     <= ( tau > TMAX ) ? (TMAX + BASE) : ( {1'b0, tau} + BASE ) ;
        in_r  <= in ;
        if (rst_r) begin
            sum <= {S{1'b0}} ;
            yc  <= {S{1'b0}} ;
            y   <= {R{1'b0}} ;
            kf  <= BASE ;
        end else begin
            sum <= sum + $signed(in_r) - $signed(y) ;
            yc  <= sum >>> { k[5:3], 3'b000 } ;   // coarse shift
            kf  <= k[2:0] ;
            y   <= yc  >>> kf ;                   // fine shift
        end
    end

    assign out = on ? y : in ;

endmodule

/*
LP_filter_sq #(.R(28)) NAME (.clk(clk), .rst(rst), .on(ON), .tau(TAU), .in(IN), .out(OUT) );
*/

/** Values of tau (BASE = 3): tau_s = 8 ns * 2^(tau+3), f = 1/(2 pi tau_s)
  *   |  0 |   64 ns | 2.49 MHz |   |  14 |  1.05 ms | 152 Hz  |
  *   |  1 |  128 ns | 1.24 MHz |   |  15 |  2.10 ms |  75.9 Hz|
  *   |  2 |  256 ns |  622 kHz |   |  16 |  4.19 ms |  37.9 Hz|
  *   |  3 |  512 ns |  311 kHz |   |  17 |  8.39 ms |  19.0 Hz|
  *   |  4 | 1.02 us |  155 kHz |   |  18 |  16.8 ms |  9.49 Hz|
  *   |  5 | 2.05 us | 77.7 kHz |   |  19 |  33.6 ms |  4.74 Hz|
  *   |  6 | 4.10 us | 38.9 kHz |   |  20 |  67.1 ms |  2.37 Hz|
  *   |  7 | 8.19 us | 19.4 kHz |   |  21 |   134 ms |  1.19 Hz|
  *   |  8 | 16.4 us | 9.71 kHz |   |  22 |   268 ms |   593 mHz|
  *   |  9 | 32.8 us | 4.86 kHz |   |  23 |   537 ms |   296 mHz|
  *   | 10 | 65.5 us | 2.43 kHz |   |  24 |  1.07 s  |   148 mHz|
  *   | 11 |  131 us | 1.21 kHz |   |  25 |  2.15 s  |  74.1 mHz|
  *   | 12 |  262 us |  607 Hz  |   |  26 |  4.29 s  |  37.1 mHz|
  *   | 13 |  524 us |  304 Hz  |   |  27 |  8.59 s  |  18.5 mHz|
  */
