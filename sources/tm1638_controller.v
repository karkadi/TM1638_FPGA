module tm1638_controller(
    input wire CLK_IN,
    input wire RST_IN,
    // Display digit inputs (8 digits, 4 bits each for hex value)
    // DIGIT_0 = leftmost digit, DIGIT_7 = rightmost digit (standard order)
    input wire [3:0] DIGIT_0,
    input wire [3:0] DIGIT_1,
    input wire [3:0] DIGIT_2,
    input wire [3:0] DIGIT_3,
    input wire [3:0] DIGIT_4,
    input wire [3:0] DIGIT_5,
    input wire [3:0] DIGIT_6,
    input wire [3:0] DIGIT_7,
    input wire [7:0] DOTS,
    input wire [7:0] LEDS,
    output reg [7:0] KEYS,
    output wire TM1638_STB,
    output wire TM1638_CLK,
    inout wire TM1638_DIO
);

// Configuration parameters
parameter USE_BIN_MODE = 0;          // 0 = direct 7-seg mode, 1 = bin mode
parameter DISPLAY_MODE = 0;          // 0 = hex, 1 = decimal (only in bin mode)
parameter DISPLAY_BRIGHTNESS = 7;    // 0-7 (7 = brightest)

// Internal signals
wire [7:0] keys_raw;
wire ss_out;
wire sclk_out;
wire mosi_out;
wire mosi_oe_out;
wire [6:0] seg0, seg1, seg2, seg3, seg4, seg5, seg6, seg7;

// Bidirectional DIO handling
reg dio_in_reg;
assign TM1638_DIO = mosi_oe_out ? mosi_out : 1'bz;

// Register DIO input
always @(posedge CLK_IN) begin
    dio_in_reg <= TM1638_DIO;
end

// Update KEYS output - INVERTED ORDER
always @(posedge CLK_IN or negedge RST_IN) begin
    if (!RST_IN) begin
        KEYS <= 8'b0;
    end else begin
        // The TM1638 reads keys in multiplexed pairs
        KEYS[0] <= keys_raw[0];  // S1 -> bit 0 (K1)
        KEYS[1] <= keys_raw[2];  // S2 -> bit 4 (K2) 
        KEYS[2] <= keys_raw[4];  // S3 -> bit 1 (K3)
        KEYS[3] <= keys_raw[6];  // S4 -> bit 5 (K4)
        KEYS[4] <= keys_raw[1];  // S5 -> bit 2 (K5)
        KEYS[5] <= keys_raw[3];  // S6 -> bit 6 (K6)
        KEYS[6] <= keys_raw[5];  // S7 -> bit 3 (K7)
        KEYS[7] <= keys_raw[7];  // S8 -> bit 7 (K8)
    end
end

// Hex to 7-segment decoder
function [6:0] hex_to_7seg;
    input [3:0] hex;
    begin
        case(hex)
            4'h0: hex_to_7seg = 7'b0111111; // 0
            4'h1: hex_to_7seg = 7'b0000110; // 1
            4'h2: hex_to_7seg = 7'b1011011; // 2
            4'h3: hex_to_7seg = 7'b1001111; // 3
            4'h4: hex_to_7seg = 7'b1100110; // 4
            4'h5: hex_to_7seg = 7'b1101101; // 5
            4'h6: hex_to_7seg = 7'b1111101; // 6
            4'h7: hex_to_7seg = 7'b0100111; // 7
            4'h8: hex_to_7seg = 7'b1111111; // 8
            4'h9: hex_to_7seg = 7'b1101111; // 9
            4'hA: hex_to_7seg = 7'b1110111; // A
            4'hB: hex_to_7seg = 7'b1111100; // b
            4'hC: hex_to_7seg = 7'b0111001; // C
            4'hD: hex_to_7seg = 7'b1011110; // d
            4'hE: hex_to_7seg = 7'b1111001; // E
            4'hF: hex_to_7seg = 7'b1110001; // F
            default: hex_to_7seg = 7'b0000000;
        endcase
    end
endfunction

// Convert hex digits to 7-segment - INVERTED ORDER
// Original: seg0 = DIGIT_0 (leftmost), seg7 = DIGIT_7 (rightmost)
// Inverted: seg0 = DIGIT_7 (rightmost), seg7 = DIGIT_0 (leftmost)
assign seg0 = hex_to_7seg(DIGIT_7);  // Rightmost digit
assign seg1 = hex_to_7seg(DIGIT_6);
assign seg2 = hex_to_7seg(DIGIT_5);
assign seg3 = hex_to_7seg(DIGIT_4);
assign seg4 = hex_to_7seg(DIGIT_3);
assign seg5 = hex_to_7seg(DIGIT_2);
assign seg6 = hex_to_7seg(DIGIT_1);
assign seg7 = hex_to_7seg(DIGIT_0);  // Leftmost digit

// Combine digits for BIN mode - INVERTED ORDER
wire [31:0] combined_bin_data = {DIGIT_0, DIGIT_1, DIGIT_2, DIGIT_3, 
                                 DIGIT_4, DIGIT_5, DIGIT_6, DIGIT_7};

// Determine which digits to suppress based on leading zeros
// Now with inverted order: digit 0 is rightmost, digit 7 is leftmost
function [7:0] get_suppress_digits;
    input [3:0] d0, d1, d2, d3, d4, d5, d6, d7;
    reg [7:0] result;
    begin
        result = 8'b00000000;
        
        // Check from left (digit 7) to right (digit 0) - BUT NOW INVERTED!
        // In inverted mode: d7 is actually the leftmost (DIGIT_0)
        //                  d0 is actually the rightmost (DIGIT_7)
        
        // Since we inverted the display, we need to think about it differently
        // For inverted display, we suppress leading zeros on the LEFT side
        // But now left side is DIGIT_0 (which maps to seg7)
        
        if (d7 == 4'h0) result[7] = 1'b1;  // Leftmost digit (DIGIT_0)
        if (d6 == 4'h0 && result[7]) result[6] = 1'b1;
        if (d5 == 4'h0 && result[6]) result[5] = 1'b1;
        if (d4 == 4'h0 && result[5]) result[4] = 1'b1;
        if (d3 == 4'h0 && result[4]) result[3] = 1'b1;
        if (d2 == 4'h0 && result[3]) result[2] = 1'b1;
        if (d1 == 4'h0 && result[2]) result[1] = 1'b1;
        if (d0 == 4'h0 && result[1]) result[0] = 1'b1;
        
        // Don't suppress the rightmost digit even if it's 0
        // Rightmost is now seg0 (DIGIT_7)
        result[0] = 1'b0;
        
        get_suppress_digits = result;
    end
endfunction

wire [7:0] suppress_digits = get_suppress_digits(DIGIT_7, DIGIT_6, DIGIT_5, DIGIT_4,
                                                 DIGIT_3, DIGIT_2, DIGIT_1, DIGIT_0);

tm1638_drv #(
    .C_FCK(50_000_000),
    .C_FSCLK(1_000_000),
    .C_FPS(250)
) tm1638_driver (
    .CK_i(CLK_IN),
    .XARST_i(RST_IN),
    
    // 7-segment data - INVERTED ORDER
    // seg0 = rightmost digit (was DIGIT_7), seg7 = leftmost digit (was DIGIT_0)
    .DIRECT7SEG0_i(seg0),  // Rightmost digit (DIGIT_7)
    .DIRECT7SEG1_i(seg1),  // (DIGIT_6)
    .DIRECT7SEG2_i(seg2),  // (DIGIT_5)
    .DIRECT7SEG3_i(seg3),  // (DIGIT_4)
    .DIRECT7SEG4_i(seg4),  // (DIGIT_3)
    .DIRECT7SEG5_i(seg5),  // (DIGIT_2)
    .DIRECT7SEG6_i(seg6),  // (DIGIT_1)
    .DIRECT7SEG7_i(seg7),  // Leftmost digit (DIGIT_0)
    
    // Decimal points - also need to invert if matching display
    .DOTS_i(DOTS),
    
    // LEDs (no inversion needed for LEDs)
    .LEDS_i(LEDS),
    
    // Binary data - INVERTED ORDER
    .BIN_DAT_i(combined_bin_data),
    
    // Digit suppression - might need adjustment for inverted order
    .SUP_DIGITS_i(USE_BIN_MODE ? suppress_digits : 8'b00000000),
    
    // Control
    .ENCBIN_XDIRECT_i(USE_BIN_MODE),
    .BIN2BCD_ON_i(DISPLAY_MODE),
    
    // Status
    .FRAME_REQ_o(),
    .EN_CK_o(),
    
    // SPI
    .MISO_i(dio_in_reg),
    .MOSI_o(mosi_out),
    .MOSI_OE_o(mosi_oe_out),
    .SCLK_o(sclk_out),
    .SS_o(ss_out),
    
    // Keys
    .KEYS_o(keys_raw)
);

// Assign outputs
assign TM1638_STB = ss_out;
assign TM1638_CLK = sclk_out;

endmodule