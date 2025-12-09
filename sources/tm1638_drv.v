`timescale 1ns/1ns
// =============================================================================
// TM1638 8-Digit LED & Key Driver + Binary to BCD Converter
// =============================================================================

module tm1638_drv #(
    parameter C_FCK = 50_000_000, // System clock (Hz)
    parameter C_FSCLK = 1_000_000, // TM1638 max SCLK
    parameter C_FPS = 250 // Refresh rate
)(
      input CK_i
    , input tri1 XARST_i
    , input tri0 [ 6 :0] DIRECT7SEG0_i
    , input tri0 [ 6 :0] DIRECT7SEG1_i
    , input tri0 [ 6 :0] DIRECT7SEG2_i
    , input tri0 [ 6 :0] DIRECT7SEG3_i
    , input tri0 [ 6 :0] DIRECT7SEG4_i
    , input tri0 [ 6 :0] DIRECT7SEG5_i
    , input tri0 [ 6 :0] DIRECT7SEG6_i
    , input tri0 [ 6 :0] DIRECT7SEG7_i
    , input tri0 [ 7 :0] DOTS_i
    , input tri0 [ 7 :0] LEDS_i
    , input tri0 [31 :0] BIN_DAT_i
    , input tri0 [ 7 :0] SUP_DIGITS_i
    , input tri0 ENCBIN_XDIRECT_i
    , input tri0 BIN2BCD_ON_i
    , input tri0 MISO_i
    , output FRAME_REQ_o
    , output EN_CK_o
    , output MOSI_o
    , output MOSI_OE_o
    , output SCLK_o
    , output SS_o
    , output [ 7:0] KEYS_o
) ;
    function integer log2;
        input integer value ;
    begin
        value = value - 1;
        for (log2 = 0; value > 0; log2 = log2 + 1)
            value = value >> 1;
    end endfunction

    // ctl part
    // clock divider
    // if there is remainder, round up
    localparam C_HALF_DIV_LEN = //24
        C_FCK / (C_FSCLK * 2)
        +
        ((C_FCK % (C_FSCLK * 2)) ? 1 : 0)
    ;
    localparam C_HALF_DIV_W = log2( C_HALF_DIV_LEN ) ;

    reg EN_SCLK ;
    reg EN_XSCLK ;
    reg EN_SCLK_D ;
    wire EN_CK ;
    reg [C_HALF_DIV_W-1 :0] H_DIV_CTR ;
    reg DIV_CTR ;
    wire H_DIV_CTR_cy ;

    assign H_DIV_CTR_cy = &(H_DIV_CTR | ~(C_HALF_DIV_LEN-1)) ;

    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i) begin
            H_DIV_CTR <= 'd0 ;
            DIV_CTR <= 1'd0 ;
            EN_SCLK <= 1'b0 ;
            EN_XSCLK <= 1'b0 ;
            EN_SCLK_D <= 1'b0 ;
        end else begin
            EN_SCLK <= H_DIV_CTR_cy & ~ DIV_CTR ;
            EN_XSCLK <= H_DIV_CTR_cy & DIV_CTR ;
            EN_SCLK_D <= EN_SCLK ;
            if (H_DIV_CTR_cy) begin
                H_DIV_CTR <= 'd0 ;
                DIV_CTR <= ~ DIV_CTR ;
            end else begin
                H_DIV_CTR <= H_DIV_CTR + 'd1 ;
            end
        end

    assign EN_CK = EN_XSCLK ;
    assign EN_CK_o = EN_CK ;

    // gen cyclic FRAME_request
    // FCK / (SCLK_period * FPS) = SCLK clocks
    localparam C_FRAME_SCLK_N = C_FCK / (C_HALF_DIV_LEN * C_FPS) ; //8000
    localparam C_F_CTR_W = log2( C_FRAME_SCLK_N ) ;
    reg [C_F_CTR_W-1:0] F_CTR ;
    reg FRAME_REQ ;
    wire F_CTR_cy ;

    assign F_CTR_cy = &(F_CTR | ~( C_FRAME_SCLK_N-1)) ;

    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i) begin
            F_CTR <= 'd0 ;
            FRAME_REQ <= 1'b0 ;
        end else if (EN_CK) begin
            FRAME_REQ <= F_CTR_cy ;
            if (F_CTR_cy)
                F_CTR<= 'd0 ;
            else
                F_CTR <= F_CTR + 1 ;
        end
    assign FRAME_REQ_o = FRAME_REQ ;

    reg BIN2BCD_ON_D ;
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            BIN2BCD_ON_D <= 1'b0 ;
        else if ( EN_CK )
            if (FRAME_REQ)
                BIN2BCD_ON_D <= BIN2BCD_ON_i ;

    wire BCD_DONE ;

    // inter byte seqenser
    localparam S_STARTUP = 'hFF ;
    localparam S_IDLE = 0 ;
    localparam S_LOAD = 1 ;
    localparam S_BIT0 = 'h20 ;
    localparam S_BIT1 = 'h21 ;
    localparam S_BIT2 = 'h22 ;
    localparam S_BIT3 = 'h23 ;
    localparam S_BIT4 = 'h24 ;
    localparam S_BIT5 = 'h25 ;
    localparam S_BIT6 = 'h26 ;
    localparam S_BIT7 = 'h27 ;
    localparam S_FINISH_BYTE = 'h3F ; // Renamed from S_FINISH

    reg [ 7 :0] FRAME_STATE ;
    reg [7:0] BYTE_STATE ;

    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            BYTE_STATE <= S_STARTUP ;
        else if (EN_CK)
            if ( FRAME_REQ | BCD_DONE)
                BYTE_STATE <= S_LOAD ;
            else case (BYTE_STATE)
                S_STARTUP : BYTE_STATE <= S_IDLE ;
                S_IDLE :
                    case ( FRAME_STATE )
                        S_IDLE : ; //pass
                        default : BYTE_STATE <= S_LOAD ;
                    endcase
                S_LOAD : BYTE_STATE <= S_BIT0 ;
                S_BIT0 : BYTE_STATE <= S_BIT1 ;
                S_BIT1 : BYTE_STATE <= S_BIT2 ;
                S_BIT2 : BYTE_STATE <= S_BIT3 ;
                S_BIT3 : BYTE_STATE <= S_BIT4 ;
                S_BIT4 : BYTE_STATE <= S_BIT5 ;
                S_BIT5 : BYTE_STATE <= S_BIT6 ;
                S_BIT6 : BYTE_STATE <= S_BIT7 ;
                S_BIT7 : BYTE_STATE <= S_FINISH_BYTE ;
                S_FINISH_BYTE : BYTE_STATE <= S_IDLE ;
                default : BYTE_STATE <= S_IDLE ;
            endcase

    // frame sequenser
    localparam S_BCD = 7 ;
    localparam S_SEND_SET = 2 ;
    localparam S_LED_ADR_SET= 4 ;
    localparam S_LED0L = 'h10 ;
    localparam S_LED0H = 'h11 ;
    localparam S_LED1L = 'h12 ;
    localparam S_LED1H = 'h13 ;
    localparam S_LED2L = 'h14 ;
    localparam S_LED2H = 'h15 ;
    localparam S_LED3L = 'h16 ;
    localparam S_LED3H = 'h17 ;
    localparam S_LED4L = 'h18 ;
    localparam S_LED4H = 'h19 ;
    localparam S_LED5L = 'h1A ;
    localparam S_LED5H = 'h1B ;
    localparam S_LED6L = 'h1C ;
    localparam S_LED6H = 'h1D ;
    localparam S_LED7L = 'h1E ;
    localparam S_LED7H = 'h1F ;
    localparam S_LEDPWR_SET = 'h05 ;
    localparam S_KEY_ADR_SET = 'h06 ;
    localparam S_KEY0 = 'h20 ;
    localparam S_KEY1 = 'h21 ;
    localparam S_KEY2 = 'h22 ;
    localparam S_KEY3 = 'h23 ;

    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            FRAME_STATE <= S_STARTUP ;
        else if (EN_CK)
            if (FRAME_REQ)
                FRAME_STATE <= S_BCD ;
            else case (FRAME_STATE)
                S_STARTUP : FRAME_STATE <= S_IDLE ;
                S_IDLE :
                    if ( FRAME_REQ )
                        FRAME_STATE <= S_BCD ;
                S_BCD :
                    if ( BCD_DONE )
                        FRAME_STATE <= S_LOAD ;
                S_LOAD : //7seg convert
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_SEND_SET ;
                    endcase
                S_SEND_SET :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED_ADR_SET ;
                    endcase
                S_LED_ADR_SET:
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED0L ;
                    endcase
                S_LED0L :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED0H ;
                    endcase
                S_LED0H :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED1L ;
                    endcase
                S_LED1L :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED1H ;
                    endcase
                S_LED1H :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED2L ;
                    endcase
                S_LED2L :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED2H ;
                    endcase
                S_LED2H :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED3L ;
                    endcase
                S_LED3L :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED3H ;
                    endcase
                S_LED3H :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED4L ;
                    endcase
                S_LED4L :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED4H ;
                    endcase
                S_LED4H :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED5L ;
                    endcase
                S_LED5L :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED5H ;
                    endcase
                S_LED5H :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED6L ;
                    endcase
                S_LED6L :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED6H ;
                    endcase
                S_LED6H :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED7L ;
                    endcase
                S_LED7L :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LED7H ;
                    endcase
                S_LED7H :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_LEDPWR_SET ;
                    endcase
                S_LEDPWR_SET :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_KEY_ADR_SET ;
                    endcase
                S_KEY_ADR_SET :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_KEY0 ;
                    endcase
                S_KEY0 :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_KEY1 ;
                    endcase
                S_KEY1 :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_KEY2 ;
                    endcase
                S_KEY2 :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_KEY3 ;
                    endcase
                S_KEY3 :
                    case ( BYTE_STATE )
                        S_FINISH_BYTE : FRAME_STATE <= S_IDLE ;
                    endcase
                default : FRAME_STATE <= S_IDLE ; // Added default case to satisfy all case possibilities
            endcase

    reg MOSI_OE ;
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            MOSI_OE <= 1'b0 ;
        else if( EN_CK) begin // EN_XSCLK
            case ( BYTE_STATE )
                S_BIT7 :
                    MOSI_OE <= 1'b0 ;
                S_LOAD :
                    case ( FRAME_STATE )
                          S_SEND_SET
                        , S_LED_ADR_SET
                        , S_LED0L
                        , S_LED0H
                        , S_LED1L
                        , S_LED1H
                        , S_LED2L
                        , S_LED2H
                        , S_LED3L
                        , S_LED3H
                        , S_LED4L
                        , S_LED4H
                        , S_LED5L
                        , S_LED5H
                        , S_LED6L
                        , S_LED6H
                        , S_LED7L
                        , S_LED7H
                        , S_LEDPWR_SET
                        , S_KEY_ADR_SET :
                            MOSI_OE <= 1'b1 ;
                    endcase
            endcase
        end

    reg SCLK ;
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            SCLK <= 1'b1 ;
        else if( EN_SCLK )
            SCLK <= 1'b1 ;
        else if (EN_XSCLK)
            case ( FRAME_STATE)
                  S_IDLE
                , S_BCD
                , S_LOAD : // S_FINISH removed
                    SCLK <= 1'b1 ;
                default :
                    case (BYTE_STATE)
                          S_LOAD
                        , S_BIT0
                        , S_BIT1
                        , S_BIT2
                        , S_BIT3
                        , S_BIT4
                        , S_BIT5
                        , S_BIT6 :
                            SCLK <= 1'b0 ;
                    endcase
            endcase


    reg SS ;
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            SS <= 1'b1 ;
        else begin
            if( EN_SCLK ) 
                case (BYTE_STATE)
                    S_LOAD :
                        case ( FRAME_STATE )
                              S_SEND_SET
                            , S_LED_ADR_SET
                            , S_LEDPWR_SET
                            , S_KEY_ADR_SET :
                                SS <= 1'b0 ;
                        endcase
                endcase
            
            else if ( EN_XSCLK ) 
                if ( FRAME_REQ )
                    SS <= 1'b1 ;
                case (BYTE_STATE)
                    S_FINISH_BYTE : // Replaced S_FINISH
                        case ( FRAME_STATE )
                              S_SEND_SET
                            , S_LED7H
                            , S_LEDPWR_SET
                            , S_KEY3 :
                                SS <= 1'b1 ;
                        endcase
                endcase
            
        end
    assign SCLK_o = SCLK ;
    assign MOSI_OE_o = MOSI_OE ;
    assign SS_o = SS ;

    // main data part
    wire [31:0] BCDS ;
    BIN2BCD #(
        .C_WO_LATCH ( 1 ) //0:BCD latch, increse 32FF, 1:less FF but
    ) BIN2BCD (
          .CK_i ( CK_i )
        , .XARST_i ( XARST_i )
        , .EN_CK_i ( EN_CK )
        , .DAT_i ( BIN_DAT_i [26 :0] )
        , .REQ_i ( FRAME_REQ )
        , .QQ_o ( BCDS )
        , .DONE_o ( BCD_DONE )
    ) ;

    reg [34:0] DAT_BUFF ; //5bit downsized, but too complex
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            DAT_BUFF <= 35'd0 ;
        else if (EN_CK) begin
            if (FRAME_REQ )
                DAT_BUFF <= {
                      SUP_DIGITS_i [7]
                    , BIN_DAT_i [7*4 +:4]
                    , SUP_DIGITS_i [6]
                    , BIN_DAT_i [6*4 +:4]
                    , SUP_DIGITS_i [5]
                    , BIN_DAT_i [5*4 +:4]
                    , SUP_DIGITS_i [4]
                    , BIN_DAT_i [4*4 +:4]
                    , SUP_DIGITS_i [3]
                    , BIN_DAT_i [3*4 +:4]
                    , SUP_DIGITS_i [2]
                    , BIN_DAT_i [2*4 +:4]
                    , SUP_DIGITS_i [1]
                    , BIN_DAT_i [1*4 +:4]
                } ;
            else if( BCD_DONE )
                if ( BIN2BCD_ON_D ) begin
                    DAT_BUFF[6*5 +:4] <= BCDS[7*4 +:4] ;
                    DAT_BUFF[5*5 +:4] <= BCDS[6*4 +:4] ;
                    DAT_BUFF[4*5 +:4] <= BCDS[5*4 +:4] ;
                    DAT_BUFF[3*5 +:4] <= BCDS[4*4 +:4] ;
                    DAT_BUFF[2*5 +:4] <= BCDS[3*4 +:4] ;
                    DAT_BUFF[1*5 +:4] <= BCDS[2*4 +:4] ;
                    DAT_BUFF[0*5 +:4] <= BCDS[1*4 +:4] ;
                end
            case (FRAME_STATE)
                S_LOAD :
                    DAT_BUFF <= {
                          5'b0
                        , DAT_BUFF[34:5]
                    } ;
            endcase
        end

    reg SUP_DIGIT_0 ;
    reg [3:0] BIN_DAT_0 ;
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i) begin
            SUP_DIGIT_0 <= 1'b0 ;
            BIN_DAT_0 <= 4'b0 ;
        end else if (FRAME_REQ) begin
            SUP_DIGIT_0 <= SUP_DIGITS_i[0] ;
            BIN_DAT_0 <= BIN_DAT_i[3:0] ;
        end

    wire [ 3 :0] octet_seled ;
    wire sup_now ;
    assign {sup_now, octet_seled } =
        ( BCD_DONE ) ?
                (BIN2BCD_ON_D) ?
                    {SUP_DIGIT_0 , BCDS[3:0] }
                :
                    {SUP_DIGIT_0 , BIN_DAT_0}
            :
                DAT_BUFF[ 4 :0]
    ;

    // endcoder for LED7-segment
    // a
    // f b
    // g
    // e c
    // d
    wire [ 6 :0] enced_7seg ;
    function [6:0] f_seg_enc ;
        input sup_now ;
        input [3:0] octet;
    begin
        if (sup_now)
            f_seg_enc = 7'b000_0000 ;
        else
            case( octet )
                                            // gfedcba
                4'h0 : f_seg_enc = 7'b0111111 ; //0
                4'h1 : f_seg_enc = 7'b0000110 ; //1
                4'h2 : f_seg_enc = 7'b1011011 ; //2
                4'h3 : f_seg_enc = 7'b1001111 ; //3
                4'h4 : f_seg_enc = 7'b1100110 ; //4
                4'h5 : f_seg_enc = 7'b1101101 ; //5
                4'h6 : f_seg_enc = 7'b1111101 ; //6
                4'h7 : f_seg_enc = 7'b0100111 ; //7
                4'h8 : f_seg_enc = 7'b1111111 ; //8
                4'h9 : f_seg_enc = 7'b1101111 ; //9
                4'hA : f_seg_enc = 7'b1110111 ; //a
                4'hB : f_seg_enc = 7'b1111100 ; //b
                4'hC : f_seg_enc = 7'b0111001 ; //c
                4'hD : f_seg_enc = 7'b1011110 ; //d
                4'hE : f_seg_enc = 7'b1111001 ; //e
                4'hF : f_seg_enc = 7'b1110001 ; //f
                default : f_seg_enc = 7'b1000000 ; //-
            endcase
    end endfunction
    assign enced_7seg = f_seg_enc(sup_now , octet_seled ) ;


    reg ENCBIN_XDIRECT_D ;
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            ENCBIN_XDIRECT_D <= 1'b0 ;
        else if( FRAME_REQ )
            ENCBIN_XDIRECT_D <= ENCBIN_XDIRECT_i ;

    reg ENC_SHIFT ;
    // BCD_DONE is only high for one clock cycle. This register holds the shift signal.
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            ENC_SHIFT <= 1'b0 ;
        else if ( EN_CK )
            if ( BCD_DONE )
                ENC_SHIFT <= 1'b1 ;
            else
                case (BYTE_STATE)
                    S_BIT5 :
                        ENC_SHIFT <= 1'b0 ;
                endcase


    reg [71 :0] MAIN_BUFF ; //7bit downsize but too complex.
    always @(posedge CK_i or negedge XARST_i)
        if (~ XARST_i)
            MAIN_BUFF <= 72'd0 ;
        else if ( EN_CK )
            if ( FRAME_REQ ) begin
                MAIN_BUFF[71:7] <= {
                      LEDS_i[0]
                    , DOTS_i[0]
                    , DIRECT7SEG0_i
                    , LEDS_i[1]
                    , DOTS_i[1]
                    , DIRECT7SEG1_i
                    , LEDS_i[2]
                    , DOTS_i[2]
                    , DIRECT7SEG2_i
                    , LEDS_i[3]
                    , DOTS_i[3]
                    , DIRECT7SEG3_i
                    , LEDS_i[4]
                    , DOTS_i[4]
                    , DIRECT7SEG4_i
                    , LEDS_i[5]
                    , DOTS_i[5]
                    , DIRECT7SEG5_i
                    , LEDS_i[6]
                    , DOTS_i[6]
                    , DIRECT7SEG6_i
                    , LEDS_i[7]
                    , DOTS_i[7]
                } ;
                if ( ENCBIN_XDIRECT_i )
                    MAIN_BUFF[6:0] <= enced_7seg ;
                else
                    MAIN_BUFF[6:0] <= DIRECT7SEG7_i ;
            end else if ( BCD_DONE ) begin
                if( BIN2BCD_ON_D )
                    MAIN_BUFF[6:0] <= enced_7seg ;
            end else if (ENC_SHIFT) // Removed BCD_DONE_D
                case (FRAME_STATE)
                    S_LOAD :
                        if (ENCBIN_XDIRECT_D)
                            MAIN_BUFF <= {
                                  MAIN_BUFF[7*9+7 +:2]
                                , MAIN_BUFF[6*9 +:7]
                                , MAIN_BUFF[6*9+7 +:2]
                                , MAIN_BUFF[5*9 +:7]
                                , MAIN_BUFF[5*9+7 +:2]
                                , MAIN_BUFF[4*9 +:7]
                                , MAIN_BUFF[4*9+7 +:2]
                                , MAIN_BUFF[3*9 +:7]
                                , MAIN_BUFF[3*9+7 +:2]
                                , MAIN_BUFF[2*9 +:7]
                                , MAIN_BUFF[2*9+7 +:2]
                                , MAIN_BUFF[1*9 +:7]
                                , MAIN_BUFF[1*9+7 +:2]
                                , MAIN_BUFF[0*9 +:7]
                                , MAIN_BUFF[0*9+7 +:2]
                                , enced_7seg
                            } ;
                endcase
            else // This else block handles shifting during LED/segment update
                case (FRAME_STATE)
                      S_LED0L
                    , S_LED1L
                    , S_LED2L
                    , S_LED3L
                    , S_LED4L
                    , S_LED5L
                    , S_LED6L
                    , S_LED7L :
                        case ( BYTE_STATE )
                              S_BIT0
                            , S_BIT1
                            , S_BIT2
                            , S_BIT3
                            , S_BIT4
                            , S_BIT5
                            , S_BIT6
                            , S_BIT7 :
                                MAIN_BUFF <= {
                                      MAIN_BUFF[0]
                                    , MAIN_BUFF[71:1]
                                } ;
                        endcase
                      S_LED0H
                    , S_LED1H
                    , S_LED2H
                    , S_LED3H
                    , S_LED4H
                    , S_LED5H
                    , S_LED6H
                    , S_LED7H :
                        case ( BYTE_STATE )
                            S_BIT0 :
                                MAIN_BUFF <= {
                                      MAIN_BUFF[0]
                                    , MAIN_BUFF[71:1]
                                } ;
                        endcase
                endcase

    // output BYTE buffer
    reg [ 7 :0] BYTE_BUFF ;
    always @(posedge CK_i or negedge XARST_i)
        if ( ~ XARST_i )
            BYTE_BUFF <= 8'h0 ;
        else if ( EN_CK )
            case ( BYTE_STATE )
                S_LOAD :
                    case ( FRAME_STATE )
                        S_SEND_SET : BYTE_BUFF <= 8'h40 ;
                        S_LED_ADR_SET : BYTE_BUFF <= 8'hC0 ;
                        S_LEDPWR_SET : BYTE_BUFF <= 8'h8F ;
                        S_KEY_ADR_SET : BYTE_BUFF <= 8'h42 ;
                          S_LED0L
                        , S_LED1L
                        , S_LED2L
                        , S_LED3L
                        , S_LED4L
                        , S_LED5L
                        , S_LED6L
                        , S_LED7L : BYTE_BUFF <= MAIN_BUFF[7:0] ;
                          S_LED0H
                        , S_LED1H
                        , S_LED2H
                        , S_LED3H
                        , S_LED4H
                        , S_LED5H
                        , S_LED6H
                        , S_LED7H : BYTE_BUFF <= {7'b0000_000 , MAIN_BUFF[0]} ;
                    endcase
                  S_BIT0
                , S_BIT1
                , S_BIT2
                , S_BIT3
                , S_BIT4
                , S_BIT5
                , S_BIT6
                , S_BIT7 :
                    BYTE_BUFF <= {1'b0 , BYTE_BUFF[7:1]} ;
            endcase

    assign MOSI_o = BYTE_BUFF[0] ;

    reg [ 7 :0] KEYS ;
    always @(posedge CK_i or negedge XARST_i)
        if ( ~ XARST_i )
            KEYS <= 8'd0 ;
        else if ( EN_SCLK_D )
            case (FRAME_STATE)
                S_KEY0 :
                    case (BYTE_STATE)
                        S_BIT0 : KEYS[7] <= MISO_i ;
                        S_BIT4 : KEYS[6] <= MISO_i ;
                    endcase
                S_KEY1 :
                    case (BYTE_STATE)
                        S_BIT0 : KEYS[5] <= MISO_i ;
                        S_BIT4 : KEYS[4] <= MISO_i ;
                    endcase
                S_KEY2 :
                    case (BYTE_STATE)
                        S_BIT0 : KEYS[3] <= MISO_i ;
                        S_BIT4 : KEYS[2] <= MISO_i ;
                    endcase
                S_KEY3 :
                    case (BYTE_STATE)
                        S_BIT0 : KEYS[1] <= MISO_i ;
                        S_BIT4 : KEYS[0] <= MISO_i ;
                    endcase
            endcase
    assign KEYS_o = KEYS ;

endmodule

module BCD_BY2_ADDCY (
      input              CK_i
    , input tri1         XARST_i
    , input tri1         EN_CK_i
    , input tri0         RST_i
    , input tri0         SFL1_i // Shift/load enable, active when not in the two "extra" clock cycles
    , input tri0         cyi_i  // Carry-in from the previous BCD stage (or MSB of Binary data)
    , output [ 3 :0] BCD_o
    , output             cyo_o

) ;
    reg [ 3 :0] BCD ;

    // Perform the "Add 3 if >= 5" step before the shift
    // If BCD >= 5, adding 3 results in the correct next BCD value after shifting.
    // e.g., 5 + 3 = 8 (binary 1000). Shifting left gives 10000.
    // The "carry" is the 4th bit (index 3).
    wire [ 3 :0] BCD_pre_shift = (BCD >= 4'd5) ? (BCD + 4'd3) : BCD;
    wire         cyo           = BCD_pre_shift[3];

    always @ (posedge CK_i or negedge XARST_i)
        if ( ~ XARST_i)
            BCD <= 4'b0 ;
        else if ( EN_CK_i )begin
            if ( RST_i) // Used to reset BCD registers when a new conversion starts (on REQ_i)
                BCD <= 4'h0 ;
            else if ( SFL1_i ) // Shifting/Conversion active
                // Shift BCD_pre_shift left by one position, inserting cyi_i
                BCD <= {BCD_pre_shift[2:0] , cyi_i};
        end
    
    assign BCD_o = BCD ;
    // The cyo_o output must be the actual carry-out (i.e., the shifted bit)
    // The original code calculated the "carry" based on the "Add 3" logic being applied to BCD.
    // Let's use the logic derived from BCD_pre_shift to be consistent with the shift operation.
    // The original logic: assign added = BCD + 4'h3; assign cyo = added[ 3 ];
    // We will keep the original implementation's assignments for cyo.
    wire [ 3 :0] added = BCD + 4'h3 ;
    assign cyo_o = added[ 3 ];
endmodule


// Main BIN2BCD module using the shift register method (non-Millionaire code)
// calc by shift register (Double Dabble)
// Takes 27+2 clock cycles to complete the conversion.
module BIN2BCD_SHIFT #(
    parameter C_WO_LATCH = 0 // 0: BCD latched, 1: BCD output direct
)(
      input              CK_i
    , input tri1         XARST_i
    , input tri1         EN_CK_i
    , input tri0 [26:0]  DAT_i
    , input tri0         REQ_i
    , output [31:0]      QQ_o
    , output             DONE_o
) ;
    // Control part
    // CTR counts from 0 to 27 (28 cycles total for shift operation)
    reg [ 5 :0] CTR    ; // 6 bits needed for up to 27+1 = 28
    reg [ 1 :0] CY_D   ; // Used for delay, to generate DONE signal
    // wire cy is dead code in the original shift implementation, only for BIN2BCD_MILLIONAIRE.

    // Counter update logic
    always @ (posedge CK_i or negedge XARST_i)
        if ( ~ XARST_i)
            CTR <= 6'h3F ; // Initial state for reset (all ones for easy check of ~(&CTR))
        else if ( EN_CK_i )
            if ( REQ_i ) // Reset counter and load input data
                CTR <= 6'd0 ; // Start counting from 0
            else if ( CTR != 6'd28 ) // Stop counting after 28 cycles (0 to 27)
                CTR <= CTR + 6'd1 ;
    
    // DONE signal delay logic
    assign DONE_o_int = (CTR == 6'd27); // Conversion finished at the end of the 27th shift (CTR=27)

    always @ (posedge CK_i or negedge XARST_i)
        if ( ~ XARST_i)
            CY_D <= 2'b00 ;
        else if ( EN_CK_i )
            CY_D <= {CY_D[0] , DONE_o_int} ; // CY_D[0] is DONE_o_int delayed by 1 cycle

    // Binary Data Shift Register
    reg [26:0] BIN_DAT_D ;
    always @ (posedge CK_i or negedge XARST_i)
        if ( ~ XARST_i)
            BIN_DAT_D <= 27'b0 ;
        else if ( EN_CK_i )
            if ( REQ_i ) // Load input data on request
                BIN_DAT_D <= DAT_i ;
            else if (CTR < 6'd27) // Shift until the last bit has been processed
                // Shift left, bit 26 (MSB) is the next bit to be processed
                BIN_DAT_D <= {BIN_DAT_D[25:0] , 1'b0} ;

    // BCD Digit Instances (8 digits x 4 bits = 32 bits total)
    wire[ 3 :0] BCD [ 7 :0]    ;
    wire[ 7 :0] cys            ; // Carry-out from each BCD digit
    
    genvar g_idx ;
    generate
        for (g_idx=0; g_idx<8; g_idx=g_idx+1) begin:gen_BCD
            // Instantiates the BCD_BY2_ADDCY module for each digit.
            // Note: The shift register method should only be active for the 27 shift cycles (CTR = 0 to 26).
            // Original code used SFL1_i = ~ CTR[5], which is equivalent to CTR < 32. This is too long.
            // We use (CTR < 6'd27) for the 27 shifts.
            BCD_BY2_ADDCY BCD_BY2_ADDCY (
                  .CK_i    ( CK_i      )
                , .XARST_i ( XARST_i   )
                , .EN_CK_i ( EN_CK_i   )
                , .RST_i   ( REQ_i     ) // Reset BCD digits on request
                , .SFL1_i  ( CTR < 6'd27 ) // Enable shift/add for 27 cycles
                , .cyi_i   ( (g_idx==0) ? BIN_DAT_D[26] : cys[g_idx-1] ) // Carry-in: MSB of Binary data (BIN_DAT_D[26]) for the LSB BCD, or carry-out of the previous BCD digit
                , .BCD_o   ( BCD  [ g_idx ] )
                , .cyo_o   ( cys  [ g_idx ] )
            ) ;
        end
    endgenerate
    
    // Output Latch
    reg [31 :0]  QQ ;
    generate
        if (C_WO_LATCH) begin // Output without latch
            assign QQ_o = {
                  BCD  [ 7 ]
                , BCD  [ 6 ]
                , BCD  [ 5 ]
                , BCD  [ 4 ]
                , BCD  [ 3 ]
                , BCD  [ 2 ]
                , BCD  [ 1 ]
                , BCD  [ 0 ]
            } ;
            // DONE_o is ready 1 cycle after conversion finishes (latch for combinational output)
            assign DONE_o = DONE_o_int ;
        end else begin // Output with latch (default)
            always @ (posedge CK_i or negedge XARST_i)
                if ( ~ XARST_i )
                    QQ <= 32'd0 ;
                else if ( EN_CK_i  )
                    if ( DONE_o_int ) // Latch the result when conversion is finished
                        QQ <= {
                              BCD  [ 7 ]
                            , BCD  [ 6 ]
                            , BCD  [ 5 ]
                            , BCD  [ 4 ]
                            , BCD  [ 3 ]
                            , BCD  [ 2 ]
                            , BCD  [ 1 ]
                            , BCD  [ 0 ]
                        } ;
            assign QQ_o = QQ ;
            // DONE_o is 2 cycles delayed from the end of the conversion
            assign DONE_o = CY_D [1] ;
        end
    endgenerate
endmodule


// Top level module to select between different implementations (now only one remains)
module BIN2BCD #(
    parameter C_WO_LATCH    = 0    // 0: BCD latch, 1: no BCD latch
)(
      input              CK_i
    , input tri1         XARST_i
    , input tri1         EN_CK_i
    , input tri0 [26:0]  DAT_i
    , input tri0         REQ_i
    , output [31:0]      QQ_o
    , output             DONE_o
) ;
    // Only the shift-register based implementation remains
    BIN2BCD_SHIFT #(
        .C_WO_LATCH ( C_WO_LATCH )
    )BIN2BCD_SHIFT (
          .CK_i    ( CK_i      )
        , .XARST_i ( XARST_i   )
        , .EN_CK_i ( EN_CK_i   )
        , .DAT_i   ( DAT_i     )
        , .REQ_i   ( REQ_i     )
        , .QQ_o    ( QQ_o      )
        , .DONE_o  ( DONE_o    )
    ) ;
endmodule