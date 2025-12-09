module u_tm1638(
    input wire CLK_50MHZ,
    input wire RST_N,
    output wire TM1638_STB,
    output wire TM1638_CLK,
    inout wire TM1638_DIO
);

// Internal signals
wire [7:0] keys_read;
reg [3:0] digit_values [0:7];  // Keep as [3:0] since we're storing decimal digits 0-9

// --- 100ms Timer Implementation ---
localparam TIMER_MAX = 5000000 - 1; // Count up to 4,999,999 (5,000,000 cycles total)
// 23 bits required: 2^22 = 4,194,304, 2^23 = 8,388,608
reg [22:0] timer_count;
reg        timer_enable; // Pulse high for one clock cycle every 100ms

always @(posedge CLK_50MHZ or negedge RST_N) begin
    if (!RST_N) begin
        timer_count <= 23'd0;
        timer_enable <= 1'b0;
    end else begin
        timer_enable <= 1'b0; // Default to low
        if (timer_count == TIMER_MAX) begin
            timer_count <= 23'd0;
            timer_enable <= 1'b1; // Pulse high when counter wraps
        end else begin
            timer_count <= timer_count + 1;
        end
    end
end
// ------------------------------------

// For debugging: decimal counter to display on 7-seg
// We'll create a BCD (Binary Coded Decimal) counter
reg [3:0] decimal_digits [0:7];  // 8 decimal digits (0-9 each)

always @(posedge CLK_50MHZ or negedge RST_N) begin
    integer i;
    if (!RST_N) begin
        // Initialize all digits to 0
        for (i = 0; i < 8; i = i + 1) begin
            decimal_digits[i] <= 4'd0;
        end
    end else begin
        // Only increment when the 100ms timer_enable pulse is high
        if (timer_enable) begin
            // Start with the least significant digit
            if (decimal_digits[0] == 4'd9) begin
                decimal_digits[0] <= 4'd0;
                // Carry to next digit
                if (decimal_digits[1] == 4'd9) begin
                    decimal_digits[1] <= 4'd0;
                    if (decimal_digits[2] == 4'd9) begin
                        decimal_digits[2] <= 4'd0;
                        if (decimal_digits[3] == 4'd9) begin
                            decimal_digits[3] <= 4'd0;
                            if (decimal_digits[4] == 4'd9) begin
                                decimal_digits[4] <= 4'd0;
                                if (decimal_digits[5] == 4'd9) begin
                                    decimal_digits[5] <= 4'd0;
                                    if (decimal_digits[6] == 4'd9) begin
                                        decimal_digits[6] <= 4'd0;
                                        if (decimal_digits[7] == 4'd9) begin
                                            decimal_digits[7] <= 4'd0;
                                        end else begin
                                            decimal_digits[7] <= decimal_digits[7] + 1;
                                        end
                                    end else begin
                                        decimal_digits[6] <= decimal_digits[6] + 1;
                                    end
                                end else begin
                                    decimal_digits[5] <= decimal_digits[5] + 1;
                                end
                            end else begin
                                decimal_digits[4] <= decimal_digits[4] + 1;
                            end
                        end else begin
                            decimal_digits[3] <= decimal_digits[3] + 1;
                        end
                    end else begin
                        decimal_digits[2] <= decimal_digits[2] + 1;
                    end
                end else begin
                    decimal_digits[1] <= decimal_digits[1] + 1;
                end
            end else begin
                decimal_digits[0] <= decimal_digits[0] + 1;
            end
        end
        
        // Assign decimal digits to display values
        digit_values[7] <= decimal_digits[0];
        digit_values[6] <= decimal_digits[1];
        digit_values[5] <= decimal_digits[2];
        digit_values[4] <= decimal_digits[3];
        digit_values[3] <= decimal_digits[4];
        digit_values[2] <= decimal_digits[5];
        digit_values[1] <= decimal_digits[6];
        digit_values[0] <= decimal_digits[7];
    end
end

// For the DOTS pattern, we can use one of the decimal digits
wire [7:0] onehot = decimal_digits[1][0:0] == 1'b1 ? 8'b1 << decimal_digits[0][3:0] : 8'b1000000 >> decimal_digits[0][3:0];

// Instantiate controller
tm1638_controller tm1638_ctrl (
    .CLK_IN(CLK_50MHZ),
    .RST_IN(RST_N),
    .DIGIT_0(digit_values[0]),
    .DIGIT_1(digit_values[1]),
    .DIGIT_2(digit_values[2]),
    .DIGIT_3(digit_values[3]),
    .DIGIT_4(digit_values[4]),
    .DIGIT_5(digit_values[5]),
    .DIGIT_6(digit_values[6]),
    .DIGIT_7(digit_values[7]),
    .DOTS(onehot),
    // LEDs show binary count
    .LEDS(keys_read),
    .KEYS(keys_read),
    .TM1638_STB(TM1638_STB),
    .TM1638_CLK(TM1638_CLK),
    .TM1638_DIO(TM1638_DIO)
);

endmodule