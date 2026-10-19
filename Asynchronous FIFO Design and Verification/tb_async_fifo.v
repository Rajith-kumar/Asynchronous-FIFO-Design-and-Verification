`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// Verilog-2001 self-checking testbench for Xilinx Vivado / XSIM.
// DUT settings: DATA_WIDTH=16, ADDR_WIDTH=3 -> 8-word FIFO.
//  - Two different, free-running clocks
//  - Initial fill to FULL, attempts writes while full
//  - Randomized overlapping producer/consumer traffic
//  - Draining to EMPTY and attempted reads while empty
//  - Wraparound checked using an ordered, independent data scoreboard
//  - Timeout on hangs; prints PASS or FAIL in Vivado Tcl Console
// No external file, test vector, UVM, or SystemVerilog feature is required.
//------------------------------------------------------------------------------
module tb_async_fifo;
    parameter DW = 16;
    parameter AW = 3;
    localparam DEPTH = (1 << AW);
    localparam MAX_WORDS = 4096;
    localparam WR_ATTEMPTS = 600;

    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;
    reg wr_rst_n = 1'b0;
    reg rd_rst_n = 1'b0;
    reg wr_en = 1'b0;
    reg rd_en = 1'b0;
    reg [DW-1:0] wr_data = {DW{1'b0}};

    wire [DW-1:0] rd_data;
    wire full, empty;

    integer sent = 0;
    integer received = 0;
    integer errors = 0;
    integer blocked_writes = 0;
    integer blocked_reads = 0;
    integer i;
    integer attempts_seen = 0;
    reg producer_done = 1'b0;
    reg [DW-1:0] expected [0:MAX_WORDS-1];
    reg [31:0] wr_rng = 32'h1234abcd;
    reg [31:0] rd_rng = 32'hbabe9841;

    async_fifo #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW)) dut (
        .wr_clk(wr_clk),
        .wr_rst_n(wr_rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .full(full),
        .rd_clk(rd_clk),
        .rd_rst_n(rd_rst_n),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .empty(empty)
    );

    // Write period=10ns, read period=14ns; their edges sometimes coincide.
    always #5 wr_clk = ~wr_clk;
    always #7 rd_clk = ~rd_clk;

    // Deterministic pseudo-random traffic, reproducible from fixed seeds.
    function [31:0] next_rng;
        input [31:0] x;
        reg [31:0] t;
        begin
            t = x ^ (x << 13);
            t = t ^ (t >> 17);
            next_rng = t ^ (t << 5);
        end
    endfunction

    // Assert resets together; release away from active clock edges.
    initial begin
        #52;
        wr_rst_n = 1'b1;
        rd_rst_n = 1'b1;
    end

    // Producer: first 25 attempts run with read disabled, forcing FIFO FULL.
    initial begin
        wait (wr_rst_n && rd_rst_n);
        for (i = 0; i < WR_ATTEMPTS; i = i + 1) begin
            @(negedge wr_clk);
            wr_rng = next_rng(wr_rng);
            wr_en = (i < 25) || (wr_rng[3:0] < 12);
            wr_data = (i ^ (i << 5) ^ 16'hA53C);
        end
        @(negedge wr_clk);
        wr_en = 1'b0;
        producer_done = 1'b1;
    end

    // Consumer: start late so full condition is genuinely exercised.
    initial begin
        wait (wr_rst_n && rd_rst_n);
        repeat (30) @(negedge rd_clk);
        forever begin
            @(negedge rd_clk);
            rd_rng = next_rng(rd_rng);
            rd_en = producer_done || (rd_rng[7:4] < 11);
        end
    end

    // Independent scoreboard: record ONLY accepted write transactions.
    always @(posedge wr_clk) begin
        if (wr_rst_n) begin
            if (wr_en && full)
                blocked_writes = blocked_writes + 1;
            if (wr_en && !full) begin
                if (sent >= MAX_WORDS) begin
                    $display("FAIL: scoreboard capacity exceeded");
                    $finish;
                end
                expected[sent] = wr_data;
                sent = sent + 1;
            end
        end
    end

    // Compare FIFO-head data at the clock edge BEFORE read-pointer update.
    always @(posedge rd_clk) begin
        if (rd_rst_n) begin
            if (rd_en && empty)
                blocked_reads = blocked_reads + 1;
            if (rd_en && !empty) begin
                if (received >= sent) begin
                    $display("ERROR: unexpected read at index=%0d, data=%h", received, rd_data);
                    errors = errors + 1;
                end else if (rd_data !== expected[received]) begin
                    $display("ERROR: index=%0d, actual=%h, expected=%h",
                             received, rd_data, expected[received]);
                    errors = errors + 1;
                end
                received = received + 1;
            end
        end
    end

    // Check the initial full state well before the first read attempt.
    initial begin
        wait (wr_rst_n && rd_rst_n);
        repeat (23) @(negedge wr_clk);
        #1;
        if (full !== 1'b1 || sent != DEPTH) begin
            $display("FAIL: fill phase expected full=1 and sent=%0d; got full=%b sent=%0d",
                     DEPTH, full, sent);
            errors = errors + 1;
        end else
            $display("CHECK: full flag asserted after %0d accepted writes", sent);
    end

    // Drain every accepted word, allow read-domain empty flag to settle.
    initial begin
        wait (producer_done);
        wait ((received == sent) && empty);
        repeat (5) @(negedge rd_clk);
        if (errors == 0 && sent > DEPTH && sent == received &&
            blocked_writes > 0 && empty === 1'b1) begin
            $display("PASS: %0d FIFO words verified in order", received);
            $display("PASS: blocked writes=%0d; blocked reads=%0d",
                     blocked_writes, blocked_reads);
            $display("PASS: different clock domains, full/empty, wraparound and drain exercised");
        end else begin
            $display("FAIL: errors=%0d sent=%0d received=%0d blocked_writes=%0d empty=%b",
                     errors, sent, received, blocked_writes, empty);
        end
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: simulation timed out: sent=%0d received=%0d", sent, received);
        $finish;
    end
endmodule
