`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 08.02.2017 17:17:16
// Design Name:
// Module Name: lock
// Project Name: lock_in+pid_square (Square lock-in+PID), derived from lock_in+pid_harmonic v2.3.18
// Target Devices:
// Tool Versions:
// Description: v2.0.0: the harmonic modulation generator and lock-in of lock_in+pid_harmonic are
//              replaced by a square generator (gen_mod_sq: sq_ref, sq_quad, sq_phas, up to 31.25 MHz
//              with exact quadrature) and a square lock-in (sqX, sqY, sqF), as the square part of
//              lock_in+pid. The rest (PIDs, ramp, lock control, bus, scope, streaming) is the one of
//              lock_in+pid_harmonic v2.3.18.
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

//(* dont_touch = "true" *)
//(* keep = "true" *)
//(* use_dsp48 = "yes" *)
//(* fsm_encoding = "gray" *)


//(* keep_hierarchy = "yes" *)
module lock(
    input clk,rst,
    // inputs
    input  signed   [14-1:0] in1,in2,
    input                    external_trigger,   // External triger input

    // outputs
    output signed   [14-1:0] out1,out2,
    output signed   [14-1:0] osc1,osc2,
    output                   trigger,            // Oscilloscope trigger output
    output                   digital_modulation, // Modulation for digital otuput
    output                   ramp_direction_out, // Output of RAMP slope singn, for trigger purposes
    output reg      [24-1:0] pwm_cfg_a,pwm_cfg_b,pwm_cfg_c,pwm_cfg_d,
    output          [32-1:0] osc_ctrl_w,

    // system bus
    input           [32-1:0] sys_addr        ,  //!< bus address
    input           [32-1:0] sys_wdata       ,  //!< bus write data
    input           [ 4-1:0] sys_sel         ,  //!< bus write byte select
    input                    sys_wen         ,  //!< bus write enable
    input                    sys_ren         ,  //!< bus read enable
    output reg      [32-1:0] sys_rdata       ,  //!< bus read data
    output reg               sys_err         ,  //!< bus error indicator
    output reg               sys_ack            //!< bus acknowledge signal
    );

    // Module starts here  *********************************************


    // [WIREREG DOCK]
    // gen_mod --------------------------
    reg         [32-1:0] gen_mod_sqp,gen_mod_phase_sq;
    
    // gen_ramp --------------------------
    reg                  ramp_reset,ramp_enable,ramp_direction,ramp_sawtooth;
    reg         [32-1:0] ramp_step;
    reg  signed [14-1:0] ramp_low_lim,ramp_hig_lim,ramp_B_factor;
    wire signed [14-1:0] ramp_A,ramp_B;
    
    // inout --------------------------
    wire signed [14-1:0] oscA,oscB;
    
    // lock-in --------------------------
    reg         [ 3-1:0] signal_sw,error_sw;
    reg         [ 4-1:0] sg_amp_sq,sg_amp_sqF;
    reg         [ 7-1:0] lpf_sq,lpf_sqF;
    reg  signed [14-1:0] error_offset,mod_out1,mod_out2;
    wire signed [14-1:0] signal_i,error;
    wire signed [32-1:0] error_mean,error_std;
    
    // lock_control --------------------------
    reg         [ 3-1:0] rl_signal_sw,rl_config;
    reg         [ 4-1:0] lock_trig_sw;
    reg         [ 5-1:0] sf_config;
    reg         [11-1:0] lock_control;
    reg         [13-1:0] rl_error_threshold;
    reg         [32-1:0] lock_trig_time;
    reg  signed [14-1:0] lock_trig_val,rl_signal_threshold,sf_jumpA,sf_jumpB;
    wire        [ 5-1:0] rl_state;
    wire        [16-1:0] lock_status;
    
    // mix --------------------------
    reg  signed [14-1:0] aux_A,aux_B;
    
    // modulation --------------------------
    wire signed [14-1:0] sq_ref,sq_quad,sq_phas;
    
    // outputs --------------------------
    reg         [ 4-1:0] out1_sw,out2_sw;
    
    // pidA --------------------------
    reg         [ 3-1:0] pidA_PSR,pidA_DSR,pidA_ctrl;
    reg         [ 4-1:0] pidA_sw,pidA_ISR;
    reg         [14-1:0] pidA_SAT;
    reg  signed [14-1:0] pidA_sp,pidA_kp,pidA_ki,pidA_kd;
    wire signed [14-1:0] pidA_in,pidA_out,ctrl_A;
    
    // pidB --------------------------
    reg         [ 3-1:0] pidB_PSR,pidB_DSR,pidB_ctrl;
    reg         [ 4-1:0] pidB_sw,pidB_ISR;
    reg         [14-1:0] pidB_SAT;
    reg  signed [14-1:0] pidB_sp,pidB_kp,pidB_ki,pidB_kd;
    wire signed [14-1:0] pidB_in,pidB_out,ctrl_B;
    
    // product_signals --------------------------
    reg         [ 3-1:0] read_ctrl;
    wire        [32-1:0] cnt_clk,cnt_clk2;
    wire signed [28-1:0] sqX_28,sqY_28,sqF_28;
    
    // scope --------------------------
    reg         [ 5-1:0] oscA_sw,oscB_sw;
    reg         [ 8-1:0] trig_sw;
    
    // streaming --------------------------
    reg         [17-1:0] stream_rate;
    reg         [32-1:0] stream_ip,stream_port,stream_cmd;
    
    // [WIREREG DOCK END]


    reg         [ 2-1:0] osc_ctrl;

    assign rl_state = 5'b0 ; // LOLO ERASE

    wire        [14-1:0] test14;
    wire        [14-1:0] rl_signal;
    wire        [ 8-1:0] trigger_signals;

    wire        [13-1:0] error_abs ;
    wire signed [28-1:0] error_pow ;
    wire signed [41-1:0] error_mean_41;
    wire signed [54-1:0] error_std_54;

    wire                 signal_fail,error_fail,locked,out_of_lock;
    //ERASE wire                 rl_signal_threshold,rl_error_threshold;

    wire        [24-1:0] pwm_cfg_a_w,pwm_cfg_b_w,pwm_cfg_c_w,pwm_cfg_d_w;
    wire        [32-1:0] test32  ;

    //pidA_ctrl: [ pidA_ifreeze: integrator freeze , pidA_freeze: output freeze , pidA_irst:integrator reset]
    wire                 pidA_irst,pidB_irst,  pidA_freeze,pidB_freeze  , pidA_ifreeze,pidB_ifreeze;

    wire                 ramp_floor_trig,ramp_ceil_trig,param_change,lock_ctrl_trig;
    //wire                 ramp_direction_out;

    wire  signed [15-1:0] out1_plus,out2_plus;
    wire  signed [14-1:0] out1_tmp ,out2_tmp;
    //wire  signed [14-1:0] in1_lpf,in2_lpf;

    assign    pidA_irst    = pidA_ctrl[0];
    assign    pidA_freeze  = pidA_ctrl[1];
    assign    pidA_ifreeze = pidA_ctrl[2];

    assign    pidB_irst    = pidB_ctrl[0];
    assign    pidB_freeze  = pidB_ctrl[1];
    assign    pidB_ifreeze = pidB_ctrl[2];


    assign    test14 = 14'b0 ;

    wire signed  [14-1:0] error_sel , error_val ;
    wire signed  [15-1:0] error_minus_offset ;


    always @(posedge clk)
    if (rst) begin
        pwm_cfg_a  <= 24'h0 ;
        pwm_cfg_b  <= 24'h0 ;
        pwm_cfg_c  <= 24'h0 ;
        pwm_cfg_d  <= 24'h0 ;
    end
    else begin
        pwm_cfg_a  <= pwm_cfg_a_w ;
        pwm_cfg_b  <= pwm_cfg_b_w ;
        pwm_cfg_c  <= pwm_cfg_c_w ;
        pwm_cfg_d  <= pwm_cfg_d_w ;
    end

    // Definition of wires and regs ************************************

    wire                 lock_trig_rise ;
    wire                 trig_val,trig_time,set_ramp_enable,set_pidA_enable,set_pidB_enable,ramp_enable_ctrl,pidA_enable_ctrl,pidB_enable_ctrl,launch_lock_trig,lock_now;

    // ERASE lolo // wire                 ramp_trig ;


    reg  signed [14-1:0] sqXo,sqYo,sqFo ;   // v2.0.0: square lock-in outputs (registered)


    wire signed [14-1:0] slow_out1_14,slow_out2_14,slow_out3_14,slow_out4_14 ;
    wire        [16-1:0] slow_out1_au,slow_out2_au,slow_out3_au,slow_out4_au ;
    wire        [24-1:0] slow_out1_aux,slow_out2_aux,slow_out3_aux,slow_out4_aux ;

    wire signed [14-1:0] pidA_out_cache,pidB_out_cache ;
    reg                  pidA_enable_d=1'b0,pidB_enable_d=1'b0 ;                            // v2.0.1
    reg  signed [14-1:0] out1_tmp_r=14'd0,out2_tmp_r=14'd0 ;                               // v2.0.1
    reg  signed [15-1:0] mod_half1_r=15'd0,mod_half2_r=15'd0 ;                             // v2.0.1

    wire signed [15-1:0] in1_m_in2,in1_m_in2_aux;

    wire signed [16-1:0] pidA_plus_ramp,pidB_plus_ramp;
    wire  jump_started,jump_trigger;
    wire signed [14-1:0] sf_jumpA_val,sf_jumpB_val;

    reg  signed [28-1:0] sqX_28_reg,sqY_28_reg,sqF_28_reg;
    reg  signed [14-1:0] error_reg,ctrl_A_reg,ctrl_B_reg,signal_i_reg;
    reg         [50-1:0] cnt,cnt_reg;

    // v2.3.17: registered copies of the read-only wires, used only by the bus read mux (sys_rdata)
    reg  signed [14-1:0] in1_rd,in2_rd,out1_rd,out2_rd,oscA_rd,oscB_rd;
    reg  signed [14-1:0] pidA_in_rd,pidA_out_rd,pidB_in_rd,pidB_out_rd,ramp_A_rd,ramp_B_rd;
    reg  signed [14-1:0] sq_ref_rd,sq_quad_rd,sq_phas_rd;
    reg  signed [32-1:0] error_mean_rd,error_std_rd;
    reg         [16-1:0] lock_status_rd;
    wire        [50-1:0] cnt_next;
    wire                 freeze ;


    // v2.0.0: square modulation (1 bit references of gen_mod_sq) and square lock-in
    wire                      sq_ref_b, sq_quad_b, sq_phas_b, square_trig;
    wire signed  [ 15-1: 0]   mod_half1, mod_half2;

    reg  stream_cmd_last;
    wire stream_cmd_last_next;

    always @(posedge clk)
    if (rst) begin
        stream_cmd_last  <=  1'b0 ;
    end else begin
        stream_cmd_last  <=  stream_cmd_last_next ;
    end
    assign stream_cmd_last_next =  stream_cmd ;

    // Oscilloscope control
    assign osc_ctrl_w = { 11'b0, &{stream_cmd_last==1'b1,stream_cmd==1'b0} , stream_rate   , stream_cmd[0] , osc_ctrl };




    //ERASE wire signed [14-1:0] LPF_A_in  , LPF_B_in  ;

    // Slow DACs decoders

    aDACdecoder i_aDACdecoder_a (  .clk(clk), .rst(rst), .in(slow_out1),  .out(pwm_cfg_a_w)  );
    aDACdecoder i_aDACdecoder_b (  .clk(clk), .rst(rst), .in(slow_out2),  .out(pwm_cfg_b_w)  );
    aDACdecoder i_aDACdecoder_c (  .clk(clk), .rst(rst), .in(slow_out3),  .out(pwm_cfg_c_w)  );
    aDACdecoder i_aDACdecoder_d (  .clk(clk), .rst(rst), .in(slow_out4),  .out(pwm_cfg_d_w)  );




    jump_control #(.N(16)) i_jump_control  ( .clk(clk), .rst(rst), .start(sf_config[0]) , .out(jump_started) , .tick(jump_trigger) );

    assign sf_jumpA_val = jump_started ? sf_jumpA : 14'b0 ;
    assign sf_jumpB_val = jump_started ? sf_jumpB : 14'b0 ;

    assign pidA_plus_ramp  = $signed(pidA_out) + $signed(ramp_A) + $signed(sf_jumpA_val) ;
    satprotect #(.Ri(16),.Ro(14),.SAT(14)) i_satprotect_ctrl_A  ( .in(pidA_plus_ramp),  .out(ctrl_A) );

    assign pidB_plus_ramp = $signed(pidB_out) + $signed(ramp_B)  + $signed(sf_jumpB_val) ;
    satprotect #(.Ri(16),.Ro(14),.SAT(14)) i_satprotect_ctrl_B  ( .in(pidB_plus_ramp),  .out(ctrl_B) );

    // Muxers  *********************************************************

    // Scopes outputs *************
    muxer_reg5  #(.RES(14)) i_muxer5_scope1 (
        // input
        .clk(clk), .rst(rst),
        .sel  ( oscA_sw ), // select cable
        .in0  ( 14'b0 ),
        .in1  ( in1     ),   .in2  ( in2     ),
        .in3  ( error  ),
        .in4  ( ctrl_A  ),   .in5  ( ctrl_B  ),
        .in6  ( ramp_A  ),   .in7  ( ramp_B  ),
        .in8  ( pidA_in ),   .in9  ( pidB_in ),
        .in10 ( pidA_out_cache ),    .in11 ( pidB_out_cache  ),
        .in12 ( sq_ref  ),   .in13 ( sq_quad ),   .in14 ( sq_phas ),
        .in15 ( sqXo    ),   .in16 ( sqYo    ),   .in17 ( sqFo    ),
        .in18 ( signal_i ),
        .in19 ( out1     ),  .in20 ( out2    ),
        .in21 ( 14'b0 ),     .in22 ( 14'b0 ),     .in23 ( 14'b0 ),    .in24 ( 14'b0 ),
        .in25 ( 14'b0 ),     .in26 ( 14'b0 ),
        .in27 ( 14'b0 ),     .in28 ( 14'b0 ),     .in29 ( 14'b0 ),
        .in30 ( 14'b0 ), // in30
        .in31 ( 14'b0 ), // in31
        // output
        .out ( oscA  )
    );

    muxer_reg5  #(.RES(14)) i_muxer5_scope2 (
        // input
        .clk(clk), .rst(rst),
        .sel  ( oscB_sw ), // select cable
        .in0  ( 14'b0 ),
        .in1  ( in1     ),   .in2  ( in2     ),
        .in3  ( error  ),
        .in4  ( ctrl_A  ),   .in5  ( ctrl_B  ),
        .in6  ( ramp_A  ),   .in7  ( ramp_B  ),
        .in8  ( pidA_in ),   .in9  ( pidB_in ),
        .in10 ( pidA_out_cache ),    .in11 ( pidB_out_cache  ),
        .in12 ( sq_ref  ),   .in13 ( sq_quad ),   .in14 ( sq_phas ),
        .in15 ( sqXo    ),   .in16 ( sqYo    ),   .in17 ( sqFo    ),
        .in18 ( signal_i ),
        .in19 ( out1     ),  .in20 ( out2    ),
        .in21 ( 14'b0 ),     .in22 ( 14'b0 ),     .in23 ( 14'b0 ),    .in24 ( 14'b0 ),
        .in25 ( 14'b0 ),     .in26 ( 14'b0 ),
        .in27 ( 14'b0 ),     .in28 ( 14'b0 ),     .in29 ( 14'b0 ),
        .in30 ( 14'b0 ), // in30
        .in31 ( 14'b0 ), // in31
        // output
        .out ( oscB  )
    );

    assign osc1 = oscA;
    assign osc2 = oscB;


    //  External Trigger  selection ******************

    //assign trigger          = trig_time ? ramp_trig : external_trigger ;
    // items=['Pin','Ramp floor','Ramp ceil','Square mod.','-','Out of lock','Jump trigger','Lock control trig'],

    assign  param_change    = 1'b0; // LOLO complete

    assign  trigger_signals = {  lock_ctrl_trig   ,
                                 jump_trigger     ,
                                 out_of_lock      ,
                                 1'b0             ,    // (bit 4: unused)
                                 square_trig      ,    // v2.0.0: start of the square modulation period (bit 3, it was harmonic_trig)
                                 ramp_ceil_trig   ,
                                 ramp_floor_trig  ,
                                 external_trigger
                              } ;


    //assign trigger          = trigger_signals & trig_sw ;

    trigger_input  #(.R(8),.N(3)) i_trigger_input (
        // input
        .clk(clk), .rst(rst),
        .trig_in ( trigger_signals ),
        .trig_sel( trig_sw         ),
        // output
        .trig_tick(trigger)
    ) ;


    // Fast DAC outputs *************

    muxer4  #(.RES(14)) out1_sw_m (
        // input
        .sel  ( out1_sw           ), // select cable
        .in0  ( 14'b0             ), // in0
        .in1  ( in1               ), // in1
        .in2  ( in2               ), // in1-in2
        .in3  ( in1_m_in2[14-1:0] ), // in3
        .in4  ( error             ), // in4
        .in5  ( sq_ref            ), // in5
        .in6  ( sq_quad           ), // in6
        .in7  ( sq_phas           ), // in7
        .in8  ( sqXo              ), // in8
        .in9  ( sqYo              ), // in9
        .in10 ( pidA_out           ), // in10
        .in11 ( pidB_out          ), // in11
        .in12 ( ctrl_A            ), // in12
        .in13 ( ctrl_B            ), // in13
        .in14 ( aux_A             ), // in14
        .in15 ( aux_B             ), // in15

        // output
        .out ( out1_tmp   )
    );


    muxer4  #(.RES(14)) out2_sw_m (
        // input
        .sel  ( out2_sw          ), // select cable
        .in0  ( 14'b0             ), // in0
        .in1  ( in1               ), // in1
        .in2  ( in2               ), // in1-in2
        .in3  ( in1_m_in2[14-1:0] ), // in3
        .in4  ( error             ), // in4
        .in5  ( sq_ref            ), // in5
        .in6  ( sq_quad           ), // in6
        .in7  ( sq_phas           ), // in7
        .in8  ( sqXo              ), // in8
        .in9  ( sqYo              ), // in9
        .in10 ( pidA_out           ), // in10
        .in11 ( pidB_out          ), // in11
        .in12 ( ctrl_A            ), // in12
        .in13 ( ctrl_B            ), // in13
        .in14 ( aux_A             ), // in14
        .in15 ( aux_B             ), // in15
        // output
        .out ( out2_tmp  )
    );


    // Adding modulation to outputs
    // v2.0.0: square modulation of amplitude mod_out/2 (the same peak amplitude as the harmonic
    // modulation of lock_in+pid_harmonic for the same mod_out): OUT1 gets +-mod_out1/2 with sq_ref,
    // OUT2 gets +-mod_out2/2 with sq_quad (quadrature, as sin_ref in lock_in+pid_harmonic).
    // Off with a negative mod_out*. No multiplier: only a sign change.

    assign mod_half1   = sq_ref_b  ? $signed({ {2{mod_out1[13]}}, mod_out1[13:1] }) : -$signed({ {2{mod_out1[13]}}, mod_out1[13:1] }) ;
    assign mod_half2   = sq_quad_b ? $signed({ {2{mod_out2[13]}}, mod_out2[13:1] }) : -$signed({ {2{mod_out2[13]}}, mod_out2[13:1] }) ;

    // v2.0.1 (from lock_in+pid_harmonic v2.3.19): the outputs to the DACs come 1 clock (8 ns) later, for everything
    // that goes out (PID/ctrl, ramp, modulation, in1...): the two terms of the sum (output of the out1/out2 mux and
    // modulation) are registered and added after the register. Same values: ~mod[13] ? tmp + half : tmp ==
    // tmp + (~mod[13] ? half : 0). See doc/lock_latency.md.
    always @(posedge clk) begin
        out1_tmp_r   <=  out1_tmp ;
        out2_tmp_r   <=  out2_tmp ;
        mod_half1_r  <=  ~mod_out1[13] ? mod_half1 : 15'b0 ;
        mod_half2_r  <=  ~mod_out2[13] ? mod_half2 : 15'b0 ;
    end

    assign out1_plus   = $signed(out1_tmp_r) + $signed(mod_half1_r) ;
    assign out2_plus   = $signed(out2_tmp_r) + $signed(mod_half2_r) ;

    satprotect #(.Ri(15),.Ro(14),.SAT(14)) i_satprotect_out1  ( .in(out1_plus),  .out(out1) );
    satprotect #(.Ri(15),.Ro(14),.SAT(14)) i_satprotect_out2  ( .in(out2_plus),  .out(out2) );


    // test an debug



    // Slow DACs outputs *************
    // map to 0 - 1.8 V

    //assign slow_out1_au  =  $signed(slow_out1_14) + $signed(15'd8192)  ;
    //assign slow_out2_au  =  $signed(slow_out2_14) + $signed(15'd8192)  ;
    assign slow_out3_au  =  $signed(slow_out3_14) + $signed(15'd8192)  ;
    assign slow_out4_au  =  $signed(slow_out4_14) + $signed(15'd8192)  ;

    //assign slow_out1_aux = slow_out1_au * 8'd156 ;
    //assign slow_out2_aux = slow_out2_au * 8'd156 ;

    pipe_mult #(.R(16),.level(4)) i_mult_slow_out3_aux (.clk(clk), .a(slow_out3_au) , .b(16'd156), .pdt(slow_out3_aux));
    pipe_mult #(.R(16),.level(4)) i_mult_slow_out4_aux (.clk(clk), .a(slow_out4_au) , .b(16'd156), .pdt(slow_out4_aux));
    //assign slow_out3_aux = slow_out3_au * 8'd156 ;
    //assign slow_out4_aux = slow_out4_au * 8'd156 ;

    //assign slow_out1     = slow_out1_aux[22-1:10];
    //assign slow_out2     = slow_out2_aux[22-1:10];
    assign slow_out3     = slow_out3_aux[22-1:10];
    assign slow_out4     = slow_out4_aux[22-1:10];





    assign     slow_out1_14 = 14'b10000000000000 ;
    assign     slow_out2_14 = 14'b10000000000000 ;


    muxer_reg4  #(.RES(14)) slow_out3_sw_m (
        // input
        .clk(clk), .rst(rst),
        .sel  ( slow_out3_sw ), // select cable
        .in0  ( 14'b10000000000000),
        .in1  ( in1               ), // in1
        .in2  ( in2               ), // in1-in2
        .in3  ( in1_m_in2[14-1:0] ), // in3
        .in4  ( sq_ref            ), // in4
        .in5  ( sqXo              ), // in5
        .in6  ( sqYo              ), // in6
        .in7  ( sqFo              ), // in7
        .in8  ( sq_quad           ), // in8
        .in9  ( sq_phas           ), // in9
        .in10 ( ramp_A            ), // in10
        .in11 ( pidA_out          ), // in11
        .in12 ( ctrl_A            ), // in12
        .in13 ( ctrl_B            ), // in13
        .in14 ( error             ), // in14
        .in15 ( aux_A             ), // in15
        // output
        .out ( slow_out3_14  )
    );


    muxer_reg4  #(.RES(14)) slow_out4_sw_m (
        // input
        .clk(clk), .rst(rst),
        .sel  ( slow_out4_sw ), // select cable
        .in0  ( 14'b10000000000000),
        .in1  ( in1               ), // in1
        .in2  ( in2               ), // in1-in2
        .in3  ( in1_m_in2[14-1:0] ), // in3
        .in4  ( sq_quad           ), // in4
        .in5  ( sqXo              ), // in5
        .in6  ( sqYo              ), // in6
        .in7  ( sqFo              ), // in7
        .in8  ( sq_ref            ), // in8
        .in9  ( sq_phas           ), // in9
        .in10 ( ramp_B            ), // in10
        .in11 ( pidA_out          ), // in11
        .in12 ( ctrl_A            ), // in12
        .in13 ( ctrl_B            ), // in13
        .in14 ( error             ), // in14
        .in15 ( aux_B             ), // in15
        // output
        .out ( slow_out4_14  )
    );

    // signal_i conditioning  ******************************************

    assign in1_m_in2_aux = $signed(in1) - $signed(in2) ;
    sat14 #(.RES(15)) i_sat15_in1in2 ( .in(in1_m_in2_aux), .lim( 15'd13  ), .out(in1_m_in2) );

    muxer3  #(.RES(14)) muxer_signal_i (
        // input
        .sel (  signal_sw  ), // select cable
        .in0  ( in1 ), // in0
        .in1  ( in2 ), // in1
        .in2  ( in1_m_in2[14-1:0] ), // in1-in2
        .in3  ( sq_ref  ), // in3
        .in4  ( sq_quad ), // in4
        .in5  ( sq_phas ), // in5
        .in6  ( aux_A ), // in6
        .in7  ( ramp_A ), // in7
        // output
        .out ( signal_i   )
    );



    muxer_reg3  #(.RES(14)) muxer3_error_i (
        // input
        .clk(clk), .rst(rst),
        .sel  (  error_sw  ), // select cable
        .in0  ( 14'b0      ), // in0
        .in1  ( sqXo       ), // in1
        .in2  ( sqYo       ), // in2
        .in3  ( sqFo       ), // in3
        .in4  ( signal_i   ), // in4
        .in5  ( in2        ), // in5
        .in6  ( in1        ), // in6
        .in7  ( in1_m_in2[14-1:0]    ), // in7
        // output
        .out ( error_sel   )
    );


    assign error_minus_offset  = $signed(error_sel) - $signed(error_offset);
    //satprotect #(.Ri(15),.Ro(14),.SAT(14)) i_satprotect_error  ( .in(error_minus_offset),  .out(error) );

    assign error = $signed(error_minus_offset[14-1:0]) ;

    sum_2N2  #(.R1(27),.R2(14),.N(27)) i_sum_2N_error_std  (.clk(clk), .rst(rst), .in1( error_pow[27-1:0] ), .out1( error_std_54  ) , .in2( error     ), .out2( error_mean_41 ));

    assign error_mean = $signed( error_mean_41[41-1:9] );
    assign error_std  = $signed( error_std_54[54-1:22] ) ;
    //assign error_pow  = $signed(error) * $signed(error);

    // mult_dsp_14  i_mult_dps_error_pow (.CLK(clk), .A($signed(error)) , .B(error), .P(error_pow));
    pipe_mult #(.R(13),.level(4)) i_mult_error_pow (.clk(clk), .a(error_abs) , .b(error_abs), .pdt(error_pow));


    // Function generator **********************************************
    // v2.0.0: square generator (lock/gen_mod_sq.v). f = 125 MHz / (2*(gen_mod_sqp+1)),
    // sq_quad 90 deg behind sq_ref (exact for odd gen_mod_sqp), sq_phas gen_mod_phase_sq ticks behind.

    gen_mod_sq  i_gen_mod_sq (
      .clk         (  clk              ),
      .rst         (  rst              ),
      .sqp         (  gen_mod_sqp      ),  // half period - 1 (ticks)
      .phase_sq    (  gen_mod_phase_sq ),  // delay of sq_phas (ticks)
      .sq_ref      (  sq_ref_b         ),  // reference
      .sq_quad     (  sq_quad_b        ),  // quadrature
      .sq_phas     (  sq_phas_b        ),  // reference with phase
      .square_trig (  square_trig      )   // start of the period
    );

    // 14 bit signals: +4096 (1) / -4096 (0), about +-0.5 V, as the references of lock_in+pid
    assign sq_ref  = { ~sq_ref_b  , 1'b1, 12'b0 } ;
    assign sq_quad = { ~sq_quad_b , 1'b1, 12'b0 } ;
    assign sq_phas = { ~sq_phas_b , 1'b1, 12'b0 } ;

    // digital reference on DIO7_N (exp_n_io[7]), as in lock_in+pid
    assign digital_modulation = sq_ref_b ;

    /* end function generator *****************************************/


    // Ramp generator **************************************************

    gen_ramp #(.R(14)) i_gen_ramp (
        .clk(clk),  .rst(rst),
        // inputs
        .ramp_step     ( ramp_step       ),
        .ramp_low_lim  ( ramp_low_lim    ),
        .ramp_hig_lim  ( ramp_hig_lim    ),
        .ramp_reset    ( ramp_reset      ),
        .ramp_enable   ( ramp_enable & ramp_enable_ctrl    ),
        .ramp_direction( ramp_direction  ),
        .ramp_sawtooth ( ramp_sawtooth   ),
        .ramp_B_factor ( ramp_B_factor   ),
        .relock_enable ( |rl_config[1:0] ),
        .out_of_lock   ( out_of_lock     ),
        .relock_reset  ( rl_config[2]    ),
        // outputs
        .trigger_low   ( ramp_floor_trig ),
        .trigger_hig   ( ramp_ceil_trig  ),
        .ramp_direction_out ( ramp_direction_out ),
        .outA          ( ramp_A          ),
        .outB          ( ramp_B          )
    );


    /* end Ramp generator *********************************************/


    // LOCK control  ***************************************************

    wire signed [ 14-1:0] lock_ctrl_signal;

    muxer4  #(.RES(14)) i_muxer4_lock_trig_sw (
        // input
        .sel  ( lock_trig_sw ), // select cable
        .in0  ( error             ), // in0
        .in1  ( sqXo              ), // in1
        .in2  ( sqYo              ), // in2
        .in3  ( sqFo              ), // in3
        .in4  ( signal_i          ), // in4
        .in5  ( ramp_A            ), // in5
        .in6  ( aux_A             ), // in6
        .in7  ( in1               ), // in7
        .in8  ( in2               ), // in8
        .in9  ( in1_m_in2[14-1:0] ), // in9
        .in10 ( pidA_out_cache    ), // in10
        .in11 ( pidB_out_cache    ), // in11
        .in12 ( ctrl_A            ), // in12
        .in13 ( ctrl_B            ), // in13
        .in14 ( ramp_B            ), // in14
        .in15 ( aux_B             ), // in15
        // output
        .out ( lock_ctrl_signal  )
    );

    wire trigger_found_aux;

    lock_ctrl i_lock_ctrl (
        .clk(clk),  .rst(rst),
        // inputs
        .lock_ctrl            ( lock_control[9:0]  ),
        .signal               ( lock_ctrl_signal   ),
        .ramp_trigger         ( ramp_floor_trig    ),
        .ramp_run             ( ramp_enable & ~ramp_reset ),   // v2.0.3 (as lock_in+pid_harmonic v2.3.23): generator running (see lock_ctrl.v cnt_ok)
        .time_threshold       ( lock_trig_time     ),
        .level_threshold      ( lock_trig_val      ),
        .level_rising_trigger ( lock_trig_rise     ),
        // outputs
        .ramp_enable          ( ramp_enable_ctrl   ),
        .pidA_enable          ( pidA_enable_ctrl   ),
        .pidB_enable          ( pidB_enable_ctrl   ),
        .lock_ctrl_trig       ( lock_ctrl_trig     ),
        .lock_status          ( lock_status        )   // read only status (0x1C), replaces lock_feedback
    );

    // v2.3.13: lock_control is command + configuration and is never rewritten from the FPGA state;
    // the lock state machine lives in lock_ctrl and is published in lock_status (doc/lock_control.md)
    assign lock_trig_rise      =  lock_control[10];

    assign   trig_time        =   lock_control[8];


    muxer3  #(.RES(14)) muxer3_rl_signal_sw (
        // input
        .sel (  rl_signal_sw  ), // select cable
        .in0  ( in1   ), // in0
        .in1  ( in2   ), // in1
        .in2  ( in1_m_in2[14-1:0] ), // in2
        .in3  ( aux_A ), // in3
        .in4  ( aux_B ), // in4
        .in5  ( sqXo  ), // in5
        .in6  ( sqYo  ), // in6
        .in7  ( sqFo  ), // in7
        // output
        .out ( rl_signal   )
    );


    assign rl_signal_enable = rl_config[1] ;
    assign rl_error_enable  = rl_config[0] ;

    assign error_abs = error[13] ? (~error[13-1:0]) + 1'b1  : error[13-1:0] ;

    assign signal_fail = /*enable_signal_th ?*/ rl_signal < rl_signal_threshold /*: 1'b0*/ ;
    assign error_fail  = /*enable_error_th  ?*/ error_abs >  rl_error_threshold /*: 1'b0 */;
    //assign out_of_lock = (|rl_config[1:0]) ? signal_fail|error_fail : 1'b0 ;

    lock_debounce #(.N0(7),.N1(4)) i_debounce_out_of_lock ( .clk(clk), .reset(rst), .in(signal_fail|error_fail), .db_level(out_of_lock), .db_tick ( )  );


    /* end LOCK control  **********************************************/



    // Signal Processing  **********************************************
    // v2.0.0: square lock-in. signal_i is multiplied by +-1 with the 1 bit references (sq_ref,
    // sq_quad, sq_phas), filtered by two cascaded first order low pass stages (lock/LP_filter_sq.v)
    // and amplified by 2^sg_amp:
    //
    //   signal_i -+- x(+-1, sq_ref ) - LPF(lpf_sq ) - sqX_28 - x2^sg_amp_sq  - sat - sqXo
    //             +- x(+-1, sq_quad) - LPF(lpf_sq ) - sqY_28 - x2^sg_amp_sq  - sat - sqYo
    //             +- x(+-1, sq_phas) - LPF(lpf_sqF) - sqF_28 - x2^sg_amp_sqF - sat - sqFo
    //
    // sq?_28 = mean( +-signal_i ) * 2^13 (13 fractional bits); with gain x1 sq?o = mean( +-signal_i ):
    // a square input of amplitude A in phase with the reference reads A, a sinusoidal one 2A/pi.
    // lpf_sq / lpf_sqF: [4:0] tau (8 ns * 2^(tau+3), 64 ns .. 8.6 s), [6:5] order (0 off, 1, 2).

    // v2.0.0 (timing): signal_i (a combinational mux, with in1-in2 saturated) and the references are registered
    // before the product (1 tick more of latency, the same for the three lines); no reset on these datapath
    // registers (they start at 0 when the FPGA is configured)
    reg  signed [15-1:0] signal_i_15 = 15'sd0 ;
    reg                  ref_X = 1'b0, ref_Y = 1'b0, ref_F = 1'b0 ;
    // v2.0.1 (from lock_in+pid_harmonic v2.3.19): one more register for the references (ref_*0): the outputs to the
    // DACs got a register (+1 clock, also for the square modulation), so the reference and the signal that comes
    // back through DAC -> system -> ADC keep the phase of before (essential at 31.25 MHz, where 1 clock is 90 deg).
    // The lock-in outputs keep their latency from in1. See doc/lock_latency.md.
    reg                  ref_X0 = 1'b0, ref_Y0 = 1'b0, ref_F0 = 1'b0 ;
    reg  signed [15-1:0] prod_X = 15'sd0, prod_Y = 15'sd0, prod_F = 15'sd0 ;   // +-signal_i (15 bits: -(-8192) fits)

    always @(posedge clk) begin
        signal_i_15 <= { signal_i[13], signal_i } ;
        ref_X0      <= sq_ref_b  ;
        ref_Y0      <= sq_quad_b ;
        ref_F0      <= sq_phas_b ;
        ref_X       <= ref_X0    ;
        ref_Y       <= ref_Y0    ;
        ref_F       <= ref_F0    ;
        prod_X      <= ref_X ? signal_i_15 : -signal_i_15 ;
        prod_Y      <= ref_Y ? signal_i_15 : -signal_i_15 ;
        prod_F      <= ref_F ? signal_i_15 : -signal_i_15 ;
    end

    wire signed [28-1:0] in_X, in_Y, in_F ;
    assign in_X = { prod_X, 13'b0 } ;
    assign in_Y = { prod_Y, 13'b0 } ;
    assign in_F = { prod_F, 13'b0 } ;

    wire                 lpf_XY_onA, lpf_XY_onB, lpf_F_onA, lpf_F_onB ;
    assign lpf_XY_onA = |lpf_sq[6:5]  ;   // order 1 or 2
    assign lpf_XY_onB =  lpf_sq[6]    ;   // order 2
    assign lpf_F_onA  = |lpf_sqF[6:5] ;
    assign lpf_F_onB  =  lpf_sqF[6]   ;

    wire signed [28-1:0] X_lpf1, Y_lpf1, F_lpf1 ;

    LP_filter_sq #(.R(28)) i_LP_filter_X_A (.clk(clk), .rst(rst), .on(lpf_XY_onA), .tau(lpf_sq[4:0] ), .in(in_X  ), .out(X_lpf1) );
    LP_filter_sq #(.R(28)) i_LP_filter_Y_A (.clk(clk), .rst(rst), .on(lpf_XY_onA), .tau(lpf_sq[4:0] ), .in(in_Y  ), .out(Y_lpf1) );
    LP_filter_sq #(.R(28)) i_LP_filter_F_A (.clk(clk), .rst(rst), .on(lpf_F_onA ), .tau(lpf_sqF[4:0]), .in(in_F  ), .out(F_lpf1) );

    LP_filter_sq #(.R(28)) i_LP_filter_X_B (.clk(clk), .rst(rst), .on(lpf_XY_onB), .tau(lpf_sq[4:0] ), .in(X_lpf1), .out(sqX_28) );
    LP_filter_sq #(.R(28)) i_LP_filter_Y_B (.clk(clk), .rst(rst), .on(lpf_XY_onB), .tau(lpf_sq[4:0] ), .in(Y_lpf1), .out(sqY_28) );
    LP_filter_sq #(.R(28)) i_LP_filter_F_B (.clk(clk), .rst(rst), .on(lpf_F_onB ), .tau(lpf_sqF[4:0]), .in(F_lpf1), .out(sqF_28) );

    // gain 2^sg_amp (0..15) and saturation to 14 bits. v2.0.0 (timing): the shifted value is registered (30 bits)
    // before the saturation, and the saturated value again (2 ticks); no reset on these datapath registers
    wire signed [43-1:0] sqX_43, sqY_43, sqF_43 ;
    reg  signed [30-1:0] sqX_30 = 30'sd0, sqY_30 = 30'sd0, sqF_30 = 30'sd0 ;
    wire signed [14-1:0] sqXo_w, sqYo_w, sqFo_w ;
    assign sqX_43 = sqX_28 <<< sg_amp_sq  ;
    assign sqY_43 = sqY_28 <<< sg_amp_sq  ;
    assign sqF_43 = sqF_28 <<< sg_amp_sqF ;

    always @(posedge clk) begin
        sqX_30 <= sqX_43[43-1:13] ;
        sqY_30 <= sqY_43[43-1:13] ;
        sqF_30 <= sqF_43[43-1:13] ;
    end

    satprotect2 #(.Ri(30),.Ro(14)) i_satprotect_sqXo ( .in( sqX_30 ), .out( sqXo_w ) );
    satprotect2 #(.Ri(30),.Ro(14)) i_satprotect_sqYo ( .in( sqY_30 ), .out( sqYo_w ) );
    satprotect2 #(.Ri(30),.Ro(14)) i_satprotect_sqFo ( .in( sqF_30 ), .out( sqFo_w ) );

    initial begin sqXo = 14'sd0; sqYo = 14'sd0; sqFo = 14'sd0; end
    always @(posedge clk) begin
        sqXo <= sqXo_w ;
        sqYo <= sqYo_w ;
        sqFo <= sqFo_w ;
    end

    always @(posedge clk) begin
        if(rst) begin
            sqX_28_reg   <=  28'b0;
            sqY_28_reg   <=  28'b0;
            sqF_28_reg   <=  28'b0;
            signal_i_reg <=  14'b0;
            error_reg    <=  14'b0;
            ctrl_A_reg   <=  14'b0;
            ctrl_B_reg   <=  14'b0;
            cnt          <=  50'b0;
            cnt_reg      <=  50'b0;
        end
        else begin
            if(freeze) begin
                sqX_28_reg   <=  sqX_28_reg;
                sqY_28_reg   <=  sqY_28_reg;
                sqF_28_reg   <=  sqF_28_reg;
                signal_i_reg <=  signal_i_reg;
                error_reg    <=  error_reg;
                ctrl_A_reg   <=  ctrl_A_reg;
                ctrl_B_reg   <=  ctrl_B_reg;
                cnt_reg      <=  cnt_reg;
            end
            else begin
                sqX_28_reg   <=  sqX_28;
                sqY_28_reg   <=  sqY_28;
                sqF_28_reg   <=  sqF_28;
                signal_i_reg <=  signal_i;
                error_reg    <=  error;
                ctrl_A_reg   <=  ctrl_A;
                ctrl_B_reg   <=  ctrl_B;
                cnt_reg      <=  cnt;
            end
            cnt     <=  cnt_next;
        end
    end

    // v2.3.17: the copies are also held while a bus read is requested (sys_ren, 2 clocks), so that the
    // inputs of sys_rdata do not change during the read (see "Bus read copies" and the FPGA MEMORY dock)
    assign freeze   = read_ctrl[0] | sys_ren ;
    assign cnt_clk  = cnt_reg[32-1:0] ;
    assign cnt_clk2 = { 14'b0, cnt_reg[50-1:32] } ;
    assign cnt_next = read_ctrl[1] ? cnt + 1'b1 : 50'b0 ;

    // Bus read copies (v2.3.17) ------------------------------------------------------
    // The bus reads these registers instead of the wires, so every input of the read mux
    // of sys_rdata (FPGA MEMORY dock) is a register of this clock domain and the long
    // combinational paths of the loop (PID, out1/out2, in1-in2...) no longer end in
    // sys_rdata. One clock (8 ns) of extra latency, only for the bus reads; the real time
    // loop does not use them. Not frozen by read_ctrl[0] (same as the wires before), but held
    // while a read is requested (sys_ren): sys_bus_cdc keeps sys_ren = 1 for 2 clocks with the
    // address already stable, sys_rdata is loaded in both and the PS takes the second one, so
    // every input of sys_rdata is stable for 2 clocks (multicycle constraint in
    // prj/v0.94/sdc/red_pitaya.xdc). The copies keep the value of the clock before the read.
    always @(posedge clk) if (!sys_ren) begin
        in1_rd         <= in1         ;
        in2_rd         <= in2         ;
        out1_rd        <= out1        ;
        out2_rd        <= out2        ;
        oscA_rd        <= oscA        ;
        oscB_rd        <= oscB        ;
        pidA_in_rd     <= pidA_in     ;
        pidA_out_rd    <= pidA_out    ;
        pidB_in_rd     <= pidB_in     ;
        pidB_out_rd    <= pidB_out    ;
        ramp_A_rd      <= ramp_A      ;
        ramp_B_rd      <= ramp_B      ;
        sq_ref_rd      <= sq_ref      ;
        sq_quad_rd     <= sq_quad     ;
        sq_phas_rd     <= sq_phas     ;
        error_mean_rd  <= error_mean  ;
        error_std_rd   <= error_std   ;
        lock_status_rd <= lock_status ;
    end
    //read_ctrl

    /* end Signal Processing  *****************************************/



    // PIDs Blocks  ****************************************************

    muxer4  #(.RES(14)) i_muxer5_pidA (
        // input
        .sel  ( pidA_sw ), // select cable
        .in0   ( error          ),
        .in1   ( sqXo           ),        .in2   ( sqYo           ),        .in3   ( sqFo           ),
        .in4   ( signal_i       ),        .in5   ( ramp_A         ),
        .in6   ( in1_m_in2[14-1:0] ),     .in7   ( in1            ),        .in8   (  in2           ),
        .in9   ( aux_A          ),        .in10  ( aux_B          ),
        .in11  ( sq_ref         ),        .in12  ( sq_quad        ),        .in13  ( sq_phas        ),
        .in14  ( 14'b0          ),        .in15  ( 14'b0          ),
        // output
        .out ( pidA_in  )
    );

    wire   pidA_freeze_sf,pidA_ifreeze_sf;
    assign pidA_freeze_sf  = sf_config[1] & jump_started ;
    assign pidA_ifreeze_sf = sf_config[2] & jump_started ;

    lock_pid_block i_lock_pid_block_A (
       // data
      .clk_i        (  clk            ),  // clock
      .rstn_i       (  rst            ),  // reset
      .pid_freeze   (  pidA_freeze  | pidA_freeze_sf   ),  // freeze output value
      .pid_ifreeze  (  pidA_ifreeze | pidA_ifreeze_sf  ),  // freeze integrator memory value
      .dat_i        (  pidA_in        ),  // input data
      .sat_i        (  pidA_SAT       ),  // saturacion
      .dat_o        (  pidA_out_cache ),  // output data

       // settings

      .PSR          (  pidA_PSR     ),
      .ISR          (  pidA_ISR     ),
      .DSR          (  pidA_DSR     ),

      .set_sp_i     (  pidA_sp      ),  // set point
      .set_kp_i     (  pidA_kp      ),  // Kp
      .set_ki_i     (  pidA_ki      ),  // Ki
      .set_kd_i     (  pidA_kd      ),  // Kd
      .int_rst_i    (  pidA_irst|(~pidA_enable_ctrl)    )   // integrator reset
    );

    // v2.0.1 (from lock_in+pid_harmonic v2.3.19): the PID output is registered inside lock_pid_block (+1 clock);
    // the enable that gates it is delayed by the same clock, so pidA_out is the old one one clock later
    always @(posedge clk) pidA_enable_d <= pidA_enable_ctrl ;
    assign pidA_out = pidA_enable_d ? pidA_out_cache : 14'b0 ;

    muxer4  #(.RES(14)) i_muxer5_pidB (
        // input
        .sel  ( pidB_sw ), // select cable
        .in0   ( error          ),
        .in1   ( sqXo           ),        .in2   ( sqYo           ),        .in3   ( sqFo           ),
        .in4   ( signal_i       ),        .in5   ( ramp_A         ),
        .in6   ( in1_m_in2[14-1:0] ),     .in7   ( in1            ),        .in8   (  in2           ),
        .in9   ( aux_A          ),        .in10  ( aux_B          ),
        .in11  ( sq_ref         ),        .in12  ( sq_quad        ),        .in13  ( sq_phas        ),
        .in14  ( 14'b0          ),        .in15  ( 14'b0          ),
        // output
        .out ( pidB_in  )
    );

    wire   pidB_freeze_sf,pidB_ifreeze_sf;
    assign pidB_freeze_sf  = sf_config[3] & jump_started ;
    assign pidB_ifreeze_sf = sf_config[4] & jump_started ;

    lock_pid_block i_lock_pid_block_B (
       // data
      .clk_i        (  clk            ),  // clock
      .rstn_i       (  rst            ),  // reset
      .pid_freeze   (  pidB_freeze   | pidB_freeze_sf  ),  // freeze output value
      .pid_ifreeze  (  pidB_ifreeze  | pidB_ifreeze_sf ),  // freeze integrator memory value
      .dat_i        (  pidB_in        ),  // input data
      .sat_i        (  pidB_SAT       ),  // saturacion
      .dat_o        (  pidB_out_cache       ),  // output data

       // settings

      .PSR          (  pidB_PSR     ),
      .ISR          (  pidB_ISR     ),
      .DSR          (  pidB_DSR     ),

      .set_sp_i     (  pidB_sp      ),  // set point
      .set_kp_i     (  pidB_kp      ),  // Kp
      .set_ki_i     (  pidB_ki      ),  // Ki
      .set_kd_i     (  pidB_kd      ),  // Kd
      .int_rst_i    (  pidB_irst|(~pidB_enable_ctrl)    )   // integrator reset
    );

    always @(posedge clk) pidB_enable_d <= pidB_enable_ctrl ;
    assign pidB_out = pidB_enable_d ? pidB_out_cache : 14'b0 ;


    /* end PIDs Blocks  ***********************************************/



    // [FPGA MEMORY DOCK]
    //---------------------------------------------------------------------------------
    //
    //  System bus connection
    
    // SO --> MEMORIA --> FPGA
    
    always @(posedge clk)
    if (rst) begin
        oscA_sw                <=   5'd1     ; // switch for muxer oscA
        oscB_sw                <=   5'd2     ; // switch for muxer oscB
        osc_ctrl               <=   2'd3     ; // oscilloscope control // [osc2_filt_off,osc1_filt_off]
        trig_sw                <=   8'd0     ; // Select the external trigger signal
        out1_sw                <=   4'd0     ; // switch for muxer out1
        out2_sw                <=   4'd0     ; // switch for muxer out2
        lock_control           <=  11'd1148  ; // lock_control help
        lock_trig_val          <=  14'd0     ; // if lock_control ?? , this vals sets the voltage threshold that turns on the lock
        lock_trig_time         <=  32'd0     ; // if lock_control ?? , this vals sets the time threshold that turns on the lock
        lock_trig_sw           <=   4'd0     ; // selects signal for trigger
        rl_error_threshold     <=  13'd0     ; // Threshold for error signal. Launchs relock when |error| > rl_error_threshold
        rl_signal_sw           <=   3'd0     ; // selects signal for relock trigger
        rl_signal_threshold    <=  14'd0     ; // Threshold for signal. Launchs relock when signal < rl_signal_threshold
        rl_config              <=   3'd0     ; // Relock enable. [relock_reset,enable_signal_th,enable_error_th] 
        sf_jumpA               <=  14'd0     ; // Step function measure jump value for ctrl_A
        sf_jumpB               <=  14'd0     ; // Step function measure jump value for ctrl_B
        sf_config              <=   5'd0     ; // Step function configuration. [pidB_ifreeze,pidB_freeze,pidA_ifreeze,pidA_freeze,start] 
        signal_sw              <=   3'd0     ; // Input selector for signal_i
        sg_amp_sq              <=   4'd0     ; // amplification of sqXo, sqYo: 2^n
        sg_amp_sqF             <=   4'd0     ; // amplification of sqFo: 2^n
        lpf_sq                 <=   7'd71    ; // Low Pass Filter of sqX, sqY: [order(2),tau(5)]
        lpf_sqF                <=   7'd71    ; // Low Pass Filter of sqF: [order(2),tau(5)]
        error_sw               <=   3'd0     ; // select error signal
        error_offset           <=  14'd0     ; // offset for the error signal
        mod_out1               <= -14'd1     ; // Square modulation for out1: +-mod_out1/2 with sq_ref (off if negative)
        mod_out2               <= -14'd1     ; // Square modulation for out2: +-mod_out2/2 with sq_quad (off if negative)
        gen_mod_sqp            <=  32'd1     ; // square half period - 1 (ticks of 8 ns): period = 2*(gen_mod_sqp+1) ticks
        gen_mod_phase_sq       <=  32'd0     ; // delay of sq_phas respect to sq_ref (ticks of 8 ns, 0 .. 2*gen_mod_sqp+1)
        ramp_step              <=  32'd0     ; // period of the triangular ramp signal
        ramp_low_lim           <= -14'd5000  ; // ramp low limit
        ramp_hig_lim           <=  14'd5000  ; // ramp high limit
        ramp_reset             <=   1'd0     ; // ramp reset config
        ramp_enable            <=   1'd0     ; // ramp enable/disable switch
        ramp_direction         <=   1'd0     ; // ramp starting direction (up/down)
        ramp_sawtooth          <=   1'd0     ; // ramp Sawtooth wave form
        ramp_B_factor          <=  14'd4096  ; // proportional factor ramp_A/ramp_B. // ramp_B=ramp_A*ramp_B_factor/4096
        read_ctrl              <=   3'd0     ; // [unused,start_clk,Freeze]
        pidA_sw                <=   4'd0     ; // switch selector for pidA input
        pidA_PSR               <=   3'd3     ; // pidA PSR
        pidA_ISR               <=   4'd8     ; // pidA ISR
        pidA_DSR               <=   3'd0     ; // pidA DSR
        pidA_SAT               <=  14'd13    ; // pidA saturation control
        pidA_sp                <=  14'd0     ; // pidA set_point
        pidA_kp                <=  14'd0     ; // pidA proportional constant
        pidA_ki                <=  14'd0     ; // pidA integral constant
        pidA_kd                <=  14'd0     ; // pidA derivative constant
        pidA_ctrl              <=   3'd0     ; // pidA control: [ pidA_ifreeze: integrator freeze , pidA_freeze: output freeze , pidA_irst:integrator reset]
        pidB_sw                <=   4'd0     ; // switch selector for pidB input
        pidB_PSR               <=   3'd3     ; // pidB PSR
        pidB_ISR               <=   4'd8     ; // pidB ISR
        pidB_DSR               <=   3'd0     ; // pidB DSR
        pidB_SAT               <=  14'd13    ; // pidB saturation control
        pidB_sp                <=  14'd0     ; // pidB set_point
        pidB_kp                <=  14'd0     ; // pidB proportional constant
        pidB_ki                <=  14'd0     ; // pidB integral constant
        pidB_kd                <=  14'd0     ; // pidB derivative constant
        pidB_ctrl              <=   3'd0     ; // pidB control: [ pidB_ifreeze: integrator freeze , pidB_freeze: output freeze , pidB_irst:integrator reset]
        aux_A                  <=  14'd0     ; // auxiliar value of 14 bits
        aux_B                  <=  14'd0     ; // auxiliar value of 14 bits
        stream_ip              <=  32'd0     ; // Client IP for streaming
        stream_port            <=  32'd6000  ; // Client TCP port for streaming
        stream_rate            <=  17'd128   ; // Streaming rate config
        stream_cmd             <=  32'd0     ; // Streaming commands
    end else begin
        if (sys_wen) begin
            if (sys_addr[19:0]==20'h00000)  oscA_sw               <=  sys_wdata[ 5-1: 0] ; // switch for muxer oscA
            if (sys_addr[19:0]==20'h00004)  oscB_sw               <=  sys_wdata[ 5-1: 0] ; // switch for muxer oscB
            if (sys_addr[19:0]==20'h00008)  osc_ctrl              <=  sys_wdata[ 2-1: 0] ; // oscilloscope control // [osc2_filt_off,osc1_filt_off]
            if (sys_addr[19:0]==20'h0000C)  trig_sw               <=  sys_wdata[ 8-1: 0] ; // Select the external trigger signal
            if (sys_addr[19:0]==20'h00010)  out1_sw               <=  sys_wdata[ 4-1: 0] ; // switch for muxer out1
            if (sys_addr[19:0]==20'h00014)  out2_sw               <=  sys_wdata[ 4-1: 0] ; // switch for muxer out2
            if (sys_addr[19:0]==20'h00018)  lock_control          <=  sys_wdata[11-1: 0] ; // lock_control help
          //if (sys_addr[19:0]==20'h0001C)  lock_status           <=  sys_wdata[16-1: 0] ; // lock control status (read only): [lock_count(8),0,0,0,ramp_enable,pidA_enable,pidB_enable,locked,armed]
            if (sys_addr[19:0]==20'h00020)  lock_trig_val         <=  sys_wdata[14-1: 0] ; // if lock_control ?? , this vals sets the voltage threshold that turns on the lock
            if (sys_addr[19:0]==20'h00024)  lock_trig_time        <=  sys_wdata[32-1: 0] ; // if lock_control ?? , this vals sets the time threshold that turns on the lock
            if (sys_addr[19:0]==20'h00028)  lock_trig_sw          <=  sys_wdata[ 4-1: 0] ; // selects signal for trigger
            if (sys_addr[19:0]==20'h0002C)  rl_error_threshold    <=  sys_wdata[13-1: 0] ; // Threshold for error signal. Launchs relock when |error| > rl_error_threshold
            if (sys_addr[19:0]==20'h00030)  rl_signal_sw          <=  sys_wdata[ 3-1: 0] ; // selects signal for relock trigger
            if (sys_addr[19:0]==20'h00034)  rl_signal_threshold   <=  sys_wdata[14-1: 0] ; // Threshold for signal. Launchs relock when signal < rl_signal_threshold
            if (sys_addr[19:0]==20'h00038)  rl_config             <=  sys_wdata[ 3-1: 0] ; // Relock enable. [relock_reset,enable_signal_th,enable_error_th] 
          //if (sys_addr[19:0]==20'h0003C)  rl_state              <=  sys_wdata[ 5-1: 0] ; // Relock state: [state:idle|searching|failed,signal_fail,error_fail,locked] 
            if (sys_addr[19:0]==20'h00040)  sf_jumpA              <=  sys_wdata[14-1: 0] ; // Step function measure jump value for ctrl_A
            if (sys_addr[19:0]==20'h00044)  sf_jumpB              <=  sys_wdata[14-1: 0] ; // Step function measure jump value for ctrl_B
            if (sys_addr[19:0]==20'h00048)  sf_config             <=  sys_wdata[ 5-1: 0] ; // Step function configuration. [pidB_ifreeze,pidB_freeze,pidA_ifreeze,pidA_freeze,start] 
            if (sys_addr[19:0]==20'h0004C)  signal_sw             <=  sys_wdata[ 3-1: 0] ; // Input selector for signal_i
          //if (sys_addr[19:0]==20'h00050)  signal_i              <=  sys_wdata[14-1: 0] ; // signal for demodulation
            if (sys_addr[19:0]==20'h00054)  sg_amp_sq             <=  sys_wdata[ 4-1: 0] ; // amplification of sqXo, sqYo: 2^n
            if (sys_addr[19:0]==20'h00058)  sg_amp_sqF            <=  sys_wdata[ 4-1: 0] ; // amplification of sqFo: 2^n
            if (sys_addr[19:0]==20'h0005C)  lpf_sq                <=  sys_wdata[ 7-1: 0] ; // Low Pass Filter of sqX, sqY: [order(2),tau(5)]
            if (sys_addr[19:0]==20'h00060)  lpf_sqF               <=  sys_wdata[ 7-1: 0] ; // Low Pass Filter of sqF: [order(2),tau(5)]
            if (sys_addr[19:0]==20'h00064)  error_sw              <=  sys_wdata[ 3-1: 0] ; // select error signal
            if (sys_addr[19:0]==20'h00068)  error_offset          <=  sys_wdata[14-1: 0] ; // offset for the error signal
          //if (sys_addr[19:0]==20'h0006C)  error                 <=  sys_wdata[14-1: 0] ; // error signal value
          //if (sys_addr[19:0]==20'h00070)  error_mean            <=  sys_wdata[32-1: 0] ; // 1 sec error mean val
          //if (sys_addr[19:0]==20'h00074)  error_std             <=  sys_wdata[32-1: 0] ; // 1 sec error square sum val
            if (sys_addr[19:0]==20'h00078)  mod_out1              <=  sys_wdata[14-1: 0] ; // Square modulation for out1: +-mod_out1/2 with sq_ref (off if negative)
            if (sys_addr[19:0]==20'h0007C)  mod_out2              <=  sys_wdata[14-1: 0] ; // Square modulation for out2: +-mod_out2/2 with sq_quad (off if negative)
            if (sys_addr[19:0]==20'h00080)  gen_mod_sqp           <=  sys_wdata[32-1: 0] ; // square half period - 1 (ticks of 8 ns): period = 2*(gen_mod_sqp+1) ticks
            if (sys_addr[19:0]==20'h00084)  gen_mod_phase_sq      <=  sys_wdata[32-1: 0] ; // delay of sq_phas respect to sq_ref (ticks of 8 ns, 0 .. 2*gen_mod_sqp+1)
          //if (sys_addr[19:0]==20'h00088)  ramp_A                <=  sys_wdata[14-1: 0] ; // ramp signal A
          //if (sys_addr[19:0]==20'h0008C)  ramp_B                <=  sys_wdata[14-1: 0] ; // ramp signal B
            if (sys_addr[19:0]==20'h00090)  ramp_step             <=  sys_wdata[32-1: 0] ; // period of the triangular ramp signal
            if (sys_addr[19:0]==20'h00094)  ramp_low_lim          <=  sys_wdata[14-1: 0] ; // ramp low limit
            if (sys_addr[19:0]==20'h00098)  ramp_hig_lim          <=  sys_wdata[14-1: 0] ; // ramp high limit
            if (sys_addr[19:0]==20'h0009C)  ramp_reset            <= |sys_wdata[32-1: 0] ; // ramp reset config
            if (sys_addr[19:0]==20'h000A0)  ramp_enable           <= |sys_wdata[32-1: 0] ; // ramp enable/disable switch
            if (sys_addr[19:0]==20'h000A4)  ramp_direction        <= |sys_wdata[32-1: 0] ; // ramp starting direction (up/down)
            if (sys_addr[19:0]==20'h000A8)  ramp_sawtooth         <= |sys_wdata[32-1: 0] ; // ramp Sawtooth wave form
            if (sys_addr[19:0]==20'h000AC)  ramp_B_factor         <=  sys_wdata[14-1: 0] ; // proportional factor ramp_A/ramp_B. // ramp_B=ramp_A*ramp_B_factor/4096
          //if (sys_addr[19:0]==20'h000B0)  sq_ref                <=  sys_wdata[14-1: 0] ; // lock-in modulation square reference (+-4096)
          //if (sys_addr[19:0]==20'h000B4)  sq_quad               <=  sys_wdata[14-1: 0] ; // lock-in modulation square quadrature (+-4096)
          //if (sys_addr[19:0]==20'h000B8)  sq_phas               <=  sys_wdata[14-1: 0] ; // lock-in modulation square with phase relation to reference (+-4096)
          //if (sys_addr[19:0]==20'h000BC)  in1                   <=  sys_wdata[14-1: 0] ; // Input signal IN1
          //if (sys_addr[19:0]==20'h000C0)  in2                   <=  sys_wdata[14-1: 0] ; // Input signal IN2
          //if (sys_addr[19:0]==20'h000C4)  out1                  <=  sys_wdata[14-1: 0] ; // signal for RP RF DAC Out1
          //if (sys_addr[19:0]==20'h000C8)  out2                  <=  sys_wdata[14-1: 0] ; // signal for RP RF DAC Out2
          //if (sys_addr[19:0]==20'h000CC)  oscA                  <=  sys_wdata[14-1: 0] ; // signal for Oscilloscope Channel A
          //if (sys_addr[19:0]==20'h000D0)  oscB                  <=  sys_wdata[14-1: 0] ; // signal for Oscilloscope Channel B
          //if (sys_addr[19:0]==20'h000D4)  sqX_28                <=  sys_wdata[28-1: 0] ; // Demodulated signal from sq_ref (in phase): mean(+-signal_i)*2^13
          //if (sys_addr[19:0]==20'h000D8)  sqY_28                <=  sys_wdata[28-1: 0] ; // Demodulated signal from sq_quad (quadrature): mean(+-signal_i)*2^13
          //if (sys_addr[19:0]==20'h000DC)  sqF_28                <=  sys_wdata[28-1: 0] ; // Demodulated signal from sq_phas: mean(+-signal_i)*2^13
          //if (sys_addr[19:0]==20'h000E0)  cnt_clk               <=  sys_wdata[32-1: 0] ; // Clock count
          //if (sys_addr[19:0]==20'h000E4)  cnt_clk2              <=  sys_wdata[32-1: 0] ; // Clock count
            if (sys_addr[19:0]==20'h000E8)  read_ctrl             <=  sys_wdata[ 3-1: 0] ; // [unused,start_clk,Freeze]
            if (sys_addr[19:0]==20'h000EC)  pidA_sw               <=  sys_wdata[ 4-1: 0] ; // switch selector for pidA input
            if (sys_addr[19:0]==20'h000F0)  pidA_PSR              <=  sys_wdata[ 3-1: 0] ; // pidA PSR
            if (sys_addr[19:0]==20'h000F4)  pidA_ISR              <=  sys_wdata[ 4-1: 0] ; // pidA ISR
            if (sys_addr[19:0]==20'h000F8)  pidA_DSR              <=  sys_wdata[ 3-1: 0] ; // pidA DSR
            if (sys_addr[19:0]==20'h000FC)  pidA_SAT              <=  sys_wdata[14-1: 0] ; // pidA saturation control
            if (sys_addr[19:0]==20'h00100)  pidA_sp               <=  sys_wdata[14-1: 0] ; // pidA set_point
            if (sys_addr[19:0]==20'h00104)  pidA_kp               <=  sys_wdata[14-1: 0] ; // pidA proportional constant
            if (sys_addr[19:0]==20'h00108)  pidA_ki               <=  sys_wdata[14-1: 0] ; // pidA integral constant
            if (sys_addr[19:0]==20'h0010C)  pidA_kd               <=  sys_wdata[14-1: 0] ; // pidA derivative constant
          //if (sys_addr[19:0]==20'h00110)  pidA_in               <=  sys_wdata[14-1: 0] ; // pidA input
          //if (sys_addr[19:0]==20'h00114)  pidA_out              <=  sys_wdata[14-1: 0] ; // pidA output
            if (sys_addr[19:0]==20'h00118)  pidA_ctrl             <=  sys_wdata[ 3-1: 0] ; // pidA control: [ pidA_ifreeze: integrator freeze , pidA_freeze: output freeze , pidA_irst:integrator reset]
          //if (sys_addr[19:0]==20'h0011C)  ctrl_A                <=  sys_wdata[14-1: 0] ; // control_A: pidA_out + ramp_A
            if (sys_addr[19:0]==20'h00120)  pidB_sw               <=  sys_wdata[ 4-1: 0] ; // switch selector for pidB input
            if (sys_addr[19:0]==20'h00124)  pidB_PSR              <=  sys_wdata[ 3-1: 0] ; // pidB PSR
            if (sys_addr[19:0]==20'h00128)  pidB_ISR              <=  sys_wdata[ 4-1: 0] ; // pidB ISR
            if (sys_addr[19:0]==20'h0012C)  pidB_DSR              <=  sys_wdata[ 3-1: 0] ; // pidB DSR
            if (sys_addr[19:0]==20'h00130)  pidB_SAT              <=  sys_wdata[14-1: 0] ; // pidB saturation control
            if (sys_addr[19:0]==20'h00134)  pidB_sp               <=  sys_wdata[14-1: 0] ; // pidB set_point
            if (sys_addr[19:0]==20'h00138)  pidB_kp               <=  sys_wdata[14-1: 0] ; // pidB proportional constant
            if (sys_addr[19:0]==20'h0013C)  pidB_ki               <=  sys_wdata[14-1: 0] ; // pidB integral constant
            if (sys_addr[19:0]==20'h00140)  pidB_kd               <=  sys_wdata[14-1: 0] ; // pidB derivative constant
          //if (sys_addr[19:0]==20'h00144)  pidB_in               <=  sys_wdata[14-1: 0] ; // pidB input
          //if (sys_addr[19:0]==20'h00148)  pidB_out              <=  sys_wdata[14-1: 0] ; // pidB output
            if (sys_addr[19:0]==20'h0014C)  pidB_ctrl             <=  sys_wdata[ 3-1: 0] ; // pidB control: [ pidB_ifreeze: integrator freeze , pidB_freeze: output freeze , pidB_irst:integrator reset]
          //if (sys_addr[19:0]==20'h00150)  ctrl_B                <=  sys_wdata[14-1: 0] ; // control_B: pidB_out + ramp_B
            if (sys_addr[19:0]==20'h00154)  aux_A                 <=  sys_wdata[14-1: 0] ; // auxiliar value of 14 bits
            if (sys_addr[19:0]==20'h00158)  aux_B                 <=  sys_wdata[14-1: 0] ; // auxiliar value of 14 bits
            if (sys_addr[19:0]==20'h0015C)  stream_ip             <=  sys_wdata[32-1: 0] ; // Client IP for streaming
            if (sys_addr[19:0]==20'h00160)  stream_port           <=  sys_wdata[32-1: 0] ; // Client TCP port for streaming
            if (sys_addr[19:0]==20'h00164)  stream_rate           <=  sys_wdata[17-1: 0] ; // Streaming rate config
            if (sys_addr[19:0]==20'h00168)  stream_cmd            <=  sys_wdata[32-1: 0] ; // Streaming commands
        end
    end
    //---------------------------------------------------------------------------------
    // FPGA --> MEMORIA --> SO
    // v2.3.17: sys_rdata only changes while a read is requested (sys_ren) and then holds its
    // value. The PS side of the bus (sys_bus_cdc, clock fclk[0]) samples sys_rdata some
    // cycles after sys_ack, asynchronously to clk (adc_clk): if sys_rdata is reloaded every
    // cycle with a changing signal (in1, oscA...), the PS can get a mix of bits of two values.
    wire sys_en;
    assign sys_en = sys_wen | sys_ren;
    
    always @(posedge clk, posedge rst)
    if (rst) begin
        sys_err <= 1'b0  ;
        sys_ack <= 1'b0  ;
    end else begin
        sys_err <= 1'b0 ;
        sys_ack <= sys_en;
        
        if (sys_ren) begin
            casez (sys_addr[19:0])
                20'h00000 : sys_rdata <= {  27'b0                   ,          oscA_sw  }; // switch for muxer oscA
                20'h00004 : sys_rdata <= {  27'b0                   ,          oscB_sw  }; // switch for muxer oscB
                20'h00008 : sys_rdata <= {  30'b0                   ,         osc_ctrl  }; // oscilloscope control // [osc2_filt_off,osc1_filt_off]
                20'h0000C : sys_rdata <= {  24'b0                   ,          trig_sw  }; // Select the external trigger signal
                20'h00010 : sys_rdata <= {  28'b0                   ,          out1_sw  }; // switch for muxer out1
                20'h00014 : sys_rdata <= {  28'b0                   ,          out2_sw  }; // switch for muxer out2
                20'h00018 : sys_rdata <= {  21'b0                   ,     lock_control  }; // lock_control help
                20'h0001C : sys_rdata <= {  16'b0                   ,   lock_status_rd  }; // lock control status (read only): [lock_count(8),0,0,0,ramp_enable,pidA_enable,pidB_enable,locked,armed]
                20'h00020 : sys_rdata <= {  {18{lock_trig_val[13]}} ,    lock_trig_val  }; // if lock_control ?? , this vals sets the voltage threshold that turns on the lock
                20'h00024 : sys_rdata <=                                lock_trig_time   ; // if lock_control ?? , this vals sets the time threshold that turns on the lock
                20'h00028 : sys_rdata <= {  28'b0                   ,     lock_trig_sw  }; // selects signal for trigger
                20'h0002C : sys_rdata <= {  19'b0                   ,  rl_error_threshold  }; // Threshold for error signal. Launchs relock when |error| > rl_error_threshold
                20'h00030 : sys_rdata <= {  29'b0                   ,     rl_signal_sw  }; // selects signal for relock trigger
                20'h00034 : sys_rdata <= {  {18{rl_signal_threshold[13]}} ,  rl_signal_threshold  }; // Threshold for signal. Launchs relock when signal < rl_signal_threshold
                20'h00038 : sys_rdata <= {  29'b0                   ,        rl_config  }; // Relock enable. [relock_reset,enable_signal_th,enable_error_th] 
                20'h0003C : sys_rdata <= {  27'b0                   ,         rl_state  }; // Relock state: [state:idle|searching|failed,signal_fail,error_fail,locked] 
                20'h00040 : sys_rdata <= {  {18{sf_jumpA[13]}}      ,         sf_jumpA  }; // Step function measure jump value for ctrl_A
                20'h00044 : sys_rdata <= {  {18{sf_jumpB[13]}}      ,         sf_jumpB  }; // Step function measure jump value for ctrl_B
                20'h00048 : sys_rdata <= {  27'b0                   ,        sf_config  }; // Step function configuration. [pidB_ifreeze,pidB_freeze,pidA_ifreeze,pidA_freeze,start] 
                20'h0004C : sys_rdata <= {  29'b0                   ,        signal_sw  }; // Input selector for signal_i
                20'h00050 : sys_rdata <= {  {18{signal_i_reg[13]}}  ,     signal_i_reg  }; // signal for demodulation
                20'h00054 : sys_rdata <= {  28'b0                   ,        sg_amp_sq  }; // amplification of sqXo, sqYo: 2^n
                20'h00058 : sys_rdata <= {  28'b0                   ,       sg_amp_sqF  }; // amplification of sqFo: 2^n
                20'h0005C : sys_rdata <= {  25'b0                   ,           lpf_sq  }; // Low Pass Filter of sqX, sqY: [order(2),tau(5)]
                20'h00060 : sys_rdata <= {  25'b0                   ,          lpf_sqF  }; // Low Pass Filter of sqF: [order(2),tau(5)]
                20'h00064 : sys_rdata <= {  29'b0                   ,         error_sw  }; // select error signal
                20'h00068 : sys_rdata <= {  {18{error_offset[13]}}  ,     error_offset  }; // offset for the error signal
                20'h0006C : sys_rdata <= {  {18{error_reg[13]}}     ,        error_reg  }; // error signal value
                20'h00070 : sys_rdata <=                                 error_mean_rd   ; // 1 sec error mean val
                20'h00074 : sys_rdata <=                                  error_std_rd   ; // 1 sec error square sum val
                20'h00078 : sys_rdata <= {  {18{mod_out1[13]}}      ,         mod_out1  }; // Square modulation for out1: +-mod_out1/2 with sq_ref (off if negative)
                20'h0007C : sys_rdata <= {  {18{mod_out2[13]}}      ,         mod_out2  }; // Square modulation for out2: +-mod_out2/2 with sq_quad (off if negative)
                20'h00080 : sys_rdata <=                                   gen_mod_sqp   ; // square half period - 1 (ticks of 8 ns): period = 2*(gen_mod_sqp+1) ticks
                20'h00084 : sys_rdata <=                              gen_mod_phase_sq   ; // delay of sq_phas respect to sq_ref (ticks of 8 ns, 0 .. 2*gen_mod_sqp+1)
                20'h00088 : sys_rdata <= {  {18{ramp_A_rd[13]}}     ,        ramp_A_rd  }; // ramp signal A
                20'h0008C : sys_rdata <= {  {18{ramp_B_rd[13]}}     ,        ramp_B_rd  }; // ramp signal B
                20'h00090 : sys_rdata <=                                     ramp_step   ; // period of the triangular ramp signal
                20'h00094 : sys_rdata <= {  {18{ramp_low_lim[13]}}  ,     ramp_low_lim  }; // ramp low limit
                20'h00098 : sys_rdata <= {  {18{ramp_hig_lim[13]}}  ,     ramp_hig_lim  }; // ramp high limit
                20'h0009C : sys_rdata <= {  31'b0                   ,       ramp_reset  }; // ramp reset config
                20'h000A0 : sys_rdata <= {  31'b0                   ,      ramp_enable  }; // ramp enable/disable switch
                20'h000A4 : sys_rdata <= {  31'b0                   ,   ramp_direction  }; // ramp starting direction (up/down)
                20'h000A8 : sys_rdata <= {  31'b0                   ,    ramp_sawtooth  }; // ramp Sawtooth wave form
                20'h000AC : sys_rdata <= {  {18{ramp_B_factor[13]}} ,    ramp_B_factor  }; // proportional factor ramp_A/ramp_B. // ramp_B=ramp_A*ramp_B_factor/4096
                20'h000B0 : sys_rdata <= {  {18{sq_ref_rd[13]}}     ,        sq_ref_rd  }; // lock-in modulation square reference (+-4096)
                20'h000B4 : sys_rdata <= {  {18{sq_quad_rd[13]}}    ,       sq_quad_rd  }; // lock-in modulation square quadrature (+-4096)
                20'h000B8 : sys_rdata <= {  {18{sq_phas_rd[13]}}    ,       sq_phas_rd  }; // lock-in modulation square with phase relation to reference (+-4096)
                20'h000BC : sys_rdata <= {  {18{in1_rd[13]}}        ,           in1_rd  }; // Input signal IN1
                20'h000C0 : sys_rdata <= {  {18{in2_rd[13]}}        ,           in2_rd  }; // Input signal IN2
                20'h000C4 : sys_rdata <= {  {18{out1_rd[13]}}       ,          out1_rd  }; // signal for RP RF DAC Out1
                20'h000C8 : sys_rdata <= {  {18{out2_rd[13]}}       ,          out2_rd  }; // signal for RP RF DAC Out2
                20'h000CC : sys_rdata <= {  {18{oscA_rd[13]}}       ,          oscA_rd  }; // signal for Oscilloscope Channel A
                20'h000D0 : sys_rdata <= {  {18{oscB_rd[13]}}       ,          oscB_rd  }; // signal for Oscilloscope Channel B
                20'h000D4 : sys_rdata <= {  { 4{sqX_28_reg[27]}}    ,       sqX_28_reg  }; // Demodulated signal from sq_ref (in phase): mean(+-signal_i)*2^13
                20'h000D8 : sys_rdata <= {  { 4{sqY_28_reg[27]}}    ,       sqY_28_reg  }; // Demodulated signal from sq_quad (quadrature): mean(+-signal_i)*2^13
                20'h000DC : sys_rdata <= {  { 4{sqF_28_reg[27]}}    ,       sqF_28_reg  }; // Demodulated signal from sq_phas: mean(+-signal_i)*2^13
                20'h000E0 : sys_rdata <=                                       cnt_clk   ; // Clock count
                20'h000E4 : sys_rdata <=                                      cnt_clk2   ; // Clock count
                20'h000E8 : sys_rdata <= {  29'b0                   ,        read_ctrl  }; // [unused,start_clk,Freeze]
                20'h000EC : sys_rdata <= {  28'b0                   ,          pidA_sw  }; // switch selector for pidA input
                20'h000F0 : sys_rdata <= {  29'b0                   ,         pidA_PSR  }; // pidA PSR
                20'h000F4 : sys_rdata <= {  28'b0                   ,         pidA_ISR  }; // pidA ISR
                20'h000F8 : sys_rdata <= {  29'b0                   ,         pidA_DSR  }; // pidA DSR
                20'h000FC : sys_rdata <= {  18'b0                   ,         pidA_SAT  }; // pidA saturation control
                20'h00100 : sys_rdata <= {  {18{pidA_sp[13]}}       ,          pidA_sp  }; // pidA set_point
                20'h00104 : sys_rdata <= {  {18{pidA_kp[13]}}       ,          pidA_kp  }; // pidA proportional constant
                20'h00108 : sys_rdata <= {  {18{pidA_ki[13]}}       ,          pidA_ki  }; // pidA integral constant
                20'h0010C : sys_rdata <= {  {18{pidA_kd[13]}}       ,          pidA_kd  }; // pidA derivative constant
                20'h00110 : sys_rdata <= {  {18{pidA_in_rd[13]}}    ,       pidA_in_rd  }; // pidA input
                20'h00114 : sys_rdata <= {  {18{pidA_out_rd[13]}}   ,      pidA_out_rd  }; // pidA output
                20'h00118 : sys_rdata <= {  29'b0                   ,        pidA_ctrl  }; // pidA control: [ pidA_ifreeze: integrator freeze , pidA_freeze: output freeze , pidA_irst:integrator reset]
                20'h0011C : sys_rdata <= {  {18{ctrl_A_reg[13]}}    ,       ctrl_A_reg  }; // control_A: pidA_out + ramp_A
                20'h00120 : sys_rdata <= {  28'b0                   ,          pidB_sw  }; // switch selector for pidB input
                20'h00124 : sys_rdata <= {  29'b0                   ,         pidB_PSR  }; // pidB PSR
                20'h00128 : sys_rdata <= {  28'b0                   ,         pidB_ISR  }; // pidB ISR
                20'h0012C : sys_rdata <= {  29'b0                   ,         pidB_DSR  }; // pidB DSR
                20'h00130 : sys_rdata <= {  18'b0                   ,         pidB_SAT  }; // pidB saturation control
                20'h00134 : sys_rdata <= {  {18{pidB_sp[13]}}       ,          pidB_sp  }; // pidB set_point
                20'h00138 : sys_rdata <= {  {18{pidB_kp[13]}}       ,          pidB_kp  }; // pidB proportional constant
                20'h0013C : sys_rdata <= {  {18{pidB_ki[13]}}       ,          pidB_ki  }; // pidB integral constant
                20'h00140 : sys_rdata <= {  {18{pidB_kd[13]}}       ,          pidB_kd  }; // pidB derivative constant
                20'h00144 : sys_rdata <= {  {18{pidB_in_rd[13]}}    ,       pidB_in_rd  }; // pidB input
                20'h00148 : sys_rdata <= {  {18{pidB_out_rd[13]}}   ,      pidB_out_rd  }; // pidB output
                20'h0014C : sys_rdata <= {  29'b0                   ,        pidB_ctrl  }; // pidB control: [ pidB_ifreeze: integrator freeze , pidB_freeze: output freeze , pidB_irst:integrator reset]
                20'h00150 : sys_rdata <= {  {18{ctrl_B_reg[13]}}    ,       ctrl_B_reg  }; // control_B: pidB_out + ramp_B
                20'h00154 : sys_rdata <= {  {18{aux_A[13]}}         ,            aux_A  }; // auxiliar value of 14 bits
                20'h00158 : sys_rdata <= {  {18{aux_B[13]}}         ,            aux_B  }; // auxiliar value of 14 bits
                20'h0015C : sys_rdata <=                                     stream_ip   ; // Client IP for streaming
                20'h00160 : sys_rdata <=                                   stream_port   ; // Client TCP port for streaming
                20'h00164 : sys_rdata <= {  15'b0                   ,      stream_rate  }; // Streaming rate config
                20'h00168 : sys_rdata <=                                    stream_cmd   ; // Streaming commands
                default   : sys_rdata <=  32'h0        ;
            endcase
        end
    end
    // [FPGA MEMORY DOCK END]

endmodule
