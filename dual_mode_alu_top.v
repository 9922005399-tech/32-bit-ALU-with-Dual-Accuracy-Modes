`timescale 1ns/1ps

// =======================================================
// Accurate ALU
// =======================================================
module accurate_alu #(
    parameter WIDTH = 32
)(
    input  wire              en,
    input  wire [3:0]        ALU_Sel,
    input  wire [WIDTH-1:0]  A,
    input  wire [WIDTH-1:0]  B,
    output reg  [WIDTH-1:0]  Result
);

    // ----------------- Internal signals -----------------
    wire [WIDTH-1:0] cla_sum;
    wire             cla_cout;
    wire [WIDTH-1:0] sub_result;
    wire             sub_cout;
    wire [WIDTH-1:0] shl_result;
    wire [WIDTH-1:0] shr_result;

    // Instantiate CLA for addition
    cla32 u_cla_add (
        .A   (A),
        .B   (B),
        .Cin (1'b0),
        .Sum (cla_sum),
        .Cout(cla_cout)
    );

    // Subtraction using two's complement
    cla32 u_cla_sub (
        .A   (A),
        .B   (~B),
        .Cin (1'b1),
        .Sum (sub_result),
        .Cout(sub_cout)
    );

    // Barrel shifters
    barrel_shifter #(.WIDTH(WIDTH)) u_shl (
        .data_in (A),
        .shamt   (B[4:0]),
        .dir     (1'b0),
        .data_out(shl_result)
    );

    barrel_shifter #(.WIDTH(WIDTH)) u_shr (
        .data_in (A),
        .shamt   (B[4:0]),
        .dir     (1'b1),
        .data_out(shr_result)
    );

    // ----------------- Main ALU -----------------
    always @(*) begin
        if (en) begin
            case (ALU_Sel)
                4'b0000: Result = cla_sum;          // ADD
                4'b0001: Result = sub_result;       // SUB
                4'b0010: Result = A & B;            // AND
                4'b0011: Result = A | B;            // OR
                4'b0100: Result = ~A;               // NOT
                4'b0101: Result = A ^ B;            // XOR
                4'b0110: Result = shl_result;       // Shift Left
                4'b0111: Result = shr_result;       // Shift Right
                4'b1000: begin                      // COMPARE
                    if (A > B)
                        Result = 32'd1;
                    else if (A < B)
                        Result = 32'd2;
                    else
                        Result = 32'd0;
                end
                default: Result = 0;
            endcase
        end else begin
            Result = 0;
        end
    end
endmodule


// =======================================================
// 32-bit Carry Lookahead Adder (CLA)
// =======================================================
module cla32 (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire        Cin,
    output wire [31:0] Sum,
    output wire        Cout
);
    wire [31:0] G, P;
    wire [32:0] C;

    assign G = A & B;
    assign P = A ^ B;
    assign C[0] = Cin;

    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) begin : CLA_LOOP
            assign C[i+1] = G[i] | (P[i] & C[i]);
            assign Sum[i] = P[i] ^ C[i];
        end
    endgenerate

    assign Cout = C[32];
endmodule


// =======================================================
// Barrel Shifter (32-bit)
// =======================================================
module barrel_shifter #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] data_in,
    input  wire [4:0]       shamt,
    input  wire             dir,
    output reg  [WIDTH-1:0] data_out
);
    always @(*) begin
        if (dir == 1'b0)
            data_out = data_in << shamt;
        else
            data_out = data_in >> shamt;
    end
endmodule


// =======================================================
// Approximate ALU
// =======================================================
module approximate_alu #(
    parameter WIDTH = 32
)(
    input  wire              clk,
    input  wire              en,
    input  wire [3:0]        ALU_Sel,
    input  wire [WIDTH-1:0]  A,
    input  wire [WIDTH-1:0]  B,
    output reg  [WIDTH-1:0]  Result
);

    wire [8:0] low8_sum   = {1'b0, A[7:0]} + {1'b0, B[7:0]};
    wire       carry8     = low8_sum[8];
    wire [8:0] low8_sub   = {1'b0, A[7:0]} - {1'b0, B[7:0]};
    wire       borrow8    = (A[7:0] < B[7:0]);

    always @(posedge clk) begin
        if (!en)
            Result <= 0;
        else begin
            case (ALU_Sel)
                4'b0000: begin // ADD
                    if ((A[31:16]==0)&&(B[31:16]==0))
                        Result <= {8'd0, A[23:0]+B[23:0]};
                    else
                        Result <= {(A[31:8]+B[31:8]+carry8),8'd0};
                end
                4'b0001: begin // SUB
                    if ((A[31:16]==0)&&(B[31:16]==0))
                        Result <= {8'd0, A[23:0]-B[23:0]};
                    else
                        Result <= {(A[31:8]-B[31:8]-borrow8),8'd0};
                end
                4'b0010: Result <= A & B;   // AND
                4'b0011: Result <= A | B;   // OR
                4'b0100: Result <= ~A;      // NOT
                4'b0101: begin              // XOR hybrid
                    if ((A[31:16]==0)&&(B[31:16]==0))
                        Result <= {16'd0, A[15:0]^B[15:0]};
                    else
                        Result <= {(A[31:16]^B[31:16]), A[15:8], (A[7:0]^B[7:0])};
                end
                4'b0110: Result <= A << B[4:0]; // Shift left
                4'b0111: Result <= A >> B[4:0]; // Shift right
                4'b1000: begin // Compare
                    if ((A[31:16]!=0)||(B[31:16]!=0)) begin
                        if (A[31:16]>B[31:16]) Result <= 32'd1;
                        else if (A[31:16]<B[31:16]) Result <= 32'd2;
                        else if (A[15:0]>B[15:0]) Result <= 32'd1;
                        else if (A[15:0]<B[15:0]) Result <= 32'd2;
                        else Result <= 32'd0;
                    end else begin
                        if (A[15:0]>B[15:0]) Result <= 32'd1;
                        else if (A[15:0]<B[15:0]) Result <= 32'd2;
                        else Result <= 32'd0;
                    end
                end
                default: Result <= 0;
            endcase
        end
    end
endmodule


// =======================================================
// Dual Mode ALU Top - Clock Auto-Select Based on Mode
// =======================================================
module dual_mode_alu_top #(
    parameter WIDTH = 32
)(
    input  wire              clk_acc,   // 100 Hz or 100 MHz (accurate)
    input  wire              clk_app,   // 10 Hz or 10 MHz (approx)
    input  wire              rst,
    input  wire              mode_sel,  // 1 = Accurate, 0 = Approximate
    input  wire [3:0]        ALU_Sel,
    input  wire [WIDTH-1:0]  A,
    input  wire [WIDTH-1:0]  B,
    output reg  [WIDTH-1:0]  Result
);

    wire active_clk = mode_sel ? clk_acc : clk_app;

    wire [WIDTH-1:0] result_acc;
    wire [WIDTH-1:0] result_approx;

    accurate_alu #(.WIDTH(WIDTH)) u_acc (
        .en(mode_sel),
        .ALU_Sel(ALU_Sel),
        .A(A),
        .B(B),
        .Result(result_acc)
    );

    approximate_alu #(.WIDTH(WIDTH)) u_approx (
        .clk(active_clk),
        .en(~mode_sel),
        .ALU_Sel(ALU_Sel),
        .A(A),
        .B(B),
        .Result(result_approx)
    );

    always @(posedge active_clk or posedge rst) begin
        if (rst)
            Result <= 0;
        else
            Result <= mode_sel ? result_acc : result_approx;
    end
endmodule