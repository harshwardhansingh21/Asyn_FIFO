class transaction;
    rand bit [7:0] din;
    rand bit        wr_en;
    rand bit        rd_en;
         bit        wr_rst_n;
         bit        rd_rst_n;
    bit  [7:0]      dout;
    bit             full;
    bit             empty;

    constraint en_dist {
        wr_en dist {1 := 70, 0 := 30};
        rd_en dist {1 := 70, 0 := 30};
    }

    
endclass


interface async_fifo_if (input wr_clk, input rd_clk);
    logic [7:0] din;
    logic        wr_en;
    logic        rd_en;
    logic        wr_rst_n;
    logic        rd_rst_n;
    logic [7:0]  dout;
    logic        full;
    logic        empty;

clocking cb_wr @(posedge wr_clk);
    output din, wr_en, wr_rst_n;
    input  full;
endclocking

clocking cb_wr_mon @(posedge wr_clk);
    input  din, wr_en, wr_rst_n, full;   
endclocking

clocking cb_rd @(posedge rd_clk);
    output rd_en, rd_rst_n;
    input  dout, empty;
endclocking

clocking cb_rd_mon @(posedge rd_clk);
    input  rd_en, rd_rst_n, dout, empty; 
endclocking
endinterface


class generator;
    transaction    tx;
    mailbox #(transaction) gen_to_drv;
    int            loop_count;

    function new(mailbox #(transaction) gen_to_drv, int loop_count);
        this.gen_to_drv  = gen_to_drv;
        this.loop_count  = loop_count;
    endfunction

    task run();
        repeat (loop_count) begin
            tx = new();
            if (!tx.randomize())
                $error("RANDOMIZATION FAILED");
            else begin
                $display("RANDOMIZATION SUCCESSFUL");
                gen_to_drv.put(tx);
            end
        end
    endtask
endclass


class driver;
    transaction    tx;
    mailbox #(transaction) gen_to_drv;
    virtual async_fifo_if  vif;

    function new(mailbox #(transaction) gen_to_drv, virtual async_fifo_if vif);
        this.gen_to_drv = gen_to_drv;
        this.vif        = vif;
    endfunction

   task run();
    fork
        forever begin
            transaction wr_tx;
            gen_to_drv.get(wr_tx);         
            @(vif.cb_wr);
            vif.cb_wr.din      <= wr_tx.din;
            vif.cb_wr.wr_en    <= wr_tx.wr_en;
            vif.cb_wr.wr_rst_n <= wr_tx.wr_rst_n;
            vif.cb_rd.rd_en    <= wr_tx.rd_en;
            vif.cb_rd.rd_rst_n <= wr_tx.rd_rst_n;
        end
    join
endtask
endclass


class monitor;
    transaction    tx;
    mailbox #(transaction) mon_to_scb_wr;
    mailbox #(transaction) mon_to_scb_rd;
    virtual async_fifo_if  vif;

    function new(mailbox #(transaction) mon_to_scb_wr,
                 mailbox #(transaction) mon_to_scb_rd,
                 virtual async_fifo_if  vif);
        this.mon_to_scb_wr = mon_to_scb_wr;
        this.mon_to_scb_rd = mon_to_scb_rd;
        this.vif           = vif;
    endfunction

   task run();
    fork
        forever begin
            @(vif.cb_wr_mon);          
            tx          = new();
            tx.din      = vif.cb_wr_mon.din;
            tx.wr_en    = vif.cb_wr_mon.wr_en;
            tx.wr_rst_n = vif.cb_wr_mon.wr_rst_n;
            tx.full     = vif.cb_wr_mon.full;
            mon_to_scb_wr.put(tx);
        end

        forever begin
            @(vif.cb_rd_mon);           
            tx          = new();
            tx.dout     = vif.cb_rd_mon.dout;
            tx.rd_en    = vif.cb_rd_mon.rd_en;
            tx.rd_rst_n = vif.cb_rd_mon.rd_rst_n;
            tx.empty    = vif.cb_rd_mon.empty;
            mon_to_scb_rd.put(tx);
        end
    join
endtask
endclass


class scoreboard;
    mailbox #(transaction) mon_to_scb_wr;
    mailbox #(transaction) mon_to_scb_rd;

    bit [7:0] expected_q[$];

    int total_writes;
    int total_reads;
    int pass_count;
    int fail_count;

    static const int SKEW_TIMEOUT = 50;

    function new(mailbox #(transaction) mon_to_scb_wr,
                 mailbox #(transaction) mon_to_scb_rd);
        this.mon_to_scb_wr = mon_to_scb_wr;
        this.mon_to_scb_rd = mon_to_scb_rd;
        total_writes       = 0;
        total_reads        = 0;
        pass_count         = 0;
        fail_count         = 0;
    endfunction

    task run();
        fork
            forever begin
                transaction wr_tx;
                mon_to_scb_wr.get(wr_tx);
                if (wr_tx.wr_rst_n && wr_tx.wr_en && !wr_tx.full) begin
                    expected_q.push_back(wr_tx.din);
                    total_writes++;
                end
            end

            forever begin
                transaction rd_tx;
                bit [7:0]   expected_data;
                int         timeout;

                mon_to_scb_rd.get(rd_tx);

                if (!rd_tx.rd_rst_n) begin
                    expected_q.delete();
                    continue;
                end

                if (!rd_tx.rd_en || rd_tx.empty)
                    continue;

                timeout = 0;
                while (expected_q.size() == 0 && timeout < SKEW_TIMEOUT) begin
                    #1;
                    timeout++;
                end

                if (expected_q.size() == 0) begin
                    $error("[SCB] TIMEOUT: read valid but expected_q empty after %0d units — possible CDC skew overrun", SKEW_TIMEOUT);
                    fail_count++;
                    continue;
                end

                expected_data = expected_q.pop_front();
                total_reads++;

                if (rd_tx.dout === expected_data) begin
                    $display("[SCB] PASS: expected = 0x%0h | got = 0x%0h", expected_data, rd_tx.dout);
                    pass_count++;
                end else begin
                    $error("[SCB] FAIL: expected = 0x%0h | got = 0x%0h", expected_data, rd_tx.dout);
                    fail_count++;
                end
            end
        join
    endtask

    function void report();
        $display("--------------------------------------------");
        $display("           SCOREBOARD FINAL REPORT          ");
        $display("--------------------------------------------");
        $display("  Total Writes   : %0d", total_writes);
        $display("  Total Reads    : %0d", total_reads);
        $display("  PASS           : %0d", pass_count);
        $display("  FAIL           : %0d", fail_count);
        if (expected_q.size() != 0)
            $error("[SCB] DRAIN FAIL: %0d entries still in expected_q at end of test", expected_q.size());
        else
            $display("  Drain Check    : PASS");
        $display("--------------------------------------------");
    endfunction
endclass


class environment;
    generator                  gen;
    driver                     drv;
    monitor                    mon;
    scoreboard                 scb;

    mailbox #(transaction)     gen_to_drv;
    mailbox #(transaction)     mon_to_scb_wr;
    mailbox #(transaction)     mon_to_scb_rd;

    virtual async_fifo_if      vif;
    int                        loop_count;

    function new(virtual async_fifo_if vif, int loop_count);
        this.vif        = vif;
        this.loop_count = loop_count;

        gen_to_drv      = new();
        mon_to_scb_wr   = new();
        mon_to_scb_rd   = new();

        gen = new(gen_to_drv,    loop_count);
        drv = new(gen_to_drv,    vif);
        mon = new(mon_to_scb_wr, mon_to_scb_rd, vif);
        scb = new(mon_to_scb_wr, mon_to_scb_rd);
    endfunction

    task pre_test();
        $display("[ENV] Starting simulation — %0d transactions", loop_count);
    endtask

    task test();
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_any
    endtask

    task post_test();
        scb.report();
        $display("[ENV] Simulation complete");
    endtask

    task run();
        pre_test();
        test();
        post_test();
    endtask
endclass


module tb_top;

    parameter WR_CLK_PERIOD = 10;
    parameter RD_CLK_PERIOD = 17;
    parameter LOOP_COUNT    = 200;

    logic wr_clk;
    logic rd_clk;

    async_fifo_if dut_if (.wr_clk(wr_clk), .rd_clk(rd_clk));

    async_fifo #(
        .DATA_WIDTH (8),
        .ADDR_WIDTH (4)
    ) dut (
        .wr_clk   (wr_clk),
        .rd_clk   (rd_clk),
        .wr_rst_n (dut_if.wr_rst_n),
        .rd_rst_n (dut_if.rd_rst_n),
        .wr_en    (dut_if.wr_en),
        .rd_en    (dut_if.rd_en),
        .din      (dut_if.din),
        .dout     (dut_if.dout),
        .full     (dut_if.full),
        .empty    (dut_if.empty)
    );

    initial wr_clk = 0;
    always #(WR_CLK_PERIOD/2) wr_clk = ~wr_clk;

    initial rd_clk = 0;
    always #(RD_CLK_PERIOD/2) rd_clk = ~rd_clk;

    environment env;

   initial begin
    dut_if.wr_rst_n = 0;
    dut_if.rd_rst_n = 0;
    repeat (5) @(posedge wr_clk);
    dut_if.wr_rst_n = 1;   
    repeat (5) @(posedge rd_clk);
    dut_if.rd_rst_n = 1;
end

    initial begin
        $dumpfile("async_fifo_tb.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
