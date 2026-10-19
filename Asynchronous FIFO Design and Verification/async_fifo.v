`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Asynchronous FIFO (first-word-fall-through / FWFT)
//   - Independent write and read clocks
//   - Power-of-two depth = 2**ADDR_WIDTH (ADDR_WIDTH >= 2)
//   - Gray-coded pointers passed through 2-FF CDC synchronizers
//   - Writes accepted on wr_clk posedge when wr_en && !full
//   - Reads consumed on rd_clk posedge when rd_en && !empty
//   - rd_data shows the current head when !empty (asynchronous RAM read)
//
// Reset limitation: Assert BOTH active-low resets together; do not independently
// reset one clock domain while the other is actively using the FIFO.
//
// FPGA note: asynchronous memory read normally infers distributed RAM/LUTs,
// not a synchronous-read BRAM. This design is for learning and small FIFOs.
// CDC note: Gray codes plus synchronizers are necessary but not complete
// physical CDC signoff. Implementation needs CDC / timing review.
//------------------------------------------------------------------------------
module async_fifo #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 3
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  full,

    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  empty
);
    localparam DEPTH = (1 << ADDR_WIDTH);

    (* ram_style = "distributed" *)
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    // ADDR_WIDTH address bits + 1 wrap bit distinguish full from empty.
    reg [ADDR_WIDTH:0] wr_ptr_bin;
    reg [ADDR_WIDTH:0] wr_ptr_gray;
    reg [ADDR_WIDTH:0] rd_ptr_bin;
    reg [ADDR_WIDTH:0] rd_ptr_gray;

    // Two stages for each Gray-coded pointer crossing the other clock domain.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [ADDR_WIDTH:0] rd_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [ADDR_WIDTH:0] rd_gray_sync2;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [ADDR_WIDTH:0] wr_gray_sync1;
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    reg [ADDR_WIDTH:0] wr_gray_sync2;

    reg full_reg;
    reg empty_reg;

    wire wr_accept = wr_en && !full_reg;
    wire rd_accept = rd_en && !empty_reg;

    wire [ADDR_WIDTH:0] wr_bin_next = wr_ptr_bin + wr_accept;
    wire [ADDR_WIDTH:0] rd_bin_next = rd_ptr_bin + rd_accept;

    wire [ADDR_WIDTH:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
    wire [ADDR_WIDTH:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    // FIFO is full after next write if pointer wraps past synchronized read.
    wire full_next =
        (wr_gray_next == {~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
                           rd_gray_sync2[ADDR_WIDTH-2:0]});

    // FIFO is empty after next read if pointers match.
    wire empty_next = (rd_gray_next == wr_gray_sync2);

    assign full  = full_reg;
    assign empty = empty_reg;
    assign rd_data = memory[rd_ptr_bin[ADDR_WIDTH-1:0]];

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
            full_reg    <= 1'b0;
        end else begin
            wr_ptr_bin  <= wr_bin_next;
            wr_ptr_gray <= wr_gray_next;
            full_reg    <= full_next;
            if (wr_accept)
                memory[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
            empty_reg   <= 1'b1;
        end else begin
            rd_ptr_bin  <= rd_bin_next;
            rd_ptr_gray <= rd_gray_next;
            empty_reg   <= empty_next;
        end
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= 0;
            rd_gray_sync2 <= 0;
        end else begin
            rd_gray_sync1 <= rd_ptr_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= 0;
            wr_gray_sync2 <= 0;
        end else begin
            wr_gray_sync1 <= wr_ptr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end
endmodule
