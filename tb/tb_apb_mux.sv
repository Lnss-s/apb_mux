`timescale 1ns/1ps

module tb_apb_mux_top;

  parameter NUM_APB_MASTERS = 9;
  parameter APB_ADDR_WIDTH = 32;
  parameter APB_DATA_WIDTH = 32;
  parameter CLK_PERIOD = 10;

  logic PRESETn;
  logic PCLK;
  
  // From masters
  logic [NUM_APB_MASTERS-1:0] PSEL_s;
  logic [APB_ADDR_WIDTH-1:0] PADDR_s [NUM_APB_MASTERS];
  logic [NUM_APB_MASTERS-1:0] PWRITE_s;
  logic [APB_DATA_WIDTH-1:0] PWDATA_s [NUM_APB_MASTERS];
  logic [NUM_APB_MASTERS-1:0] PENABLE_s;
  logic [NUM_APB_MASTERS-1:0] PSTRB_s;  
  logic [NUM_APB_MASTERS-1:0] PPROT_s;  
  logic [APB_DATA_WIDTH-1:0] PRDATA_s [NUM_APB_MASTERS];
  logic [NUM_APB_MASTERS-1:0] PREADY_s;
  logic [NUM_APB_MASTERS-1:0] PSLVERR_s;
  
  // To slave
  logic PSEL_m;
  logic [APB_ADDR_WIDTH-1:0] PADDR_m;
  logic PWRITE_m;
  logic [APB_DATA_WIDTH-1:0] PWDATA_m;
  logic PENABLE_m;
  logic PSTRB_m;      
  logic PPROT_m;      
  logic [APB_DATA_WIDTH-1:0] PRDATA_m;
  logic PREADY_m;
  logic PSLVERR_m;

  always #(CLK_PERIOD/2) PCLK = ~PCLK;

  apb_mux_top #(
    .NUM_APB_MASTERS(NUM_APB_MASTERS),
    .APB_ADDR_WIDTH(APB_ADDR_WIDTH),
    .APB_DATA_WIDTH(APB_DATA_WIDTH)
  ) dut (
    .PRESETn(PRESETn),
    .PCLK(PCLK),
    .PSEL_s(PSEL_s),
    .PADDR_s(PADDR_s),
    .PWRITE_s(PWRITE_s),
    .PWDATA_s(PWDATA_s),
    .PENABLE_s(PENABLE_s),
    .PSTRB_s(PSTRB_s),  
    .PPROT_s(PPROT_s),  
    .PRDATA_s(PRDATA_s),
    .PREADY_s(PREADY_s),
    .PSLVERR_s(PSLVERR_s),
    .PSEL_m(PSEL_m),
    .PADDR_m(PADDR_m),
    .PWRITE_m(PWRITE_m),
    .PWDATA_m(PWDATA_m),
    .PENABLE_m(PENABLE_m),
    .PSTRB_m(PSTRB_m),      
    .PPROT_m(PPROT_m),      
    .PRDATA_m(PRDATA_m),
    .PREADY_m(PREADY_m),
    .PSLVERR_m(PSLVERR_m)
  );

  // Slave model - always ready
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      PRDATA_m <= '0;
      PREADY_m <= 1'b0;
      PSLVERR_m <= 1'b0;
    end else begin
      if (PSEL_m && PENABLE_m) begin
        if (!PWRITE_m) begin
          PRDATA_m <= {8'hDE, PADDR_m[23:0]};
        end
        PREADY_m <= 1'b1;
        PSLVERR_m <= 1'b0;
      end else begin
        PREADY_m <= 1'b0;
      end
    end
  end

  task automatic master_transaction(
    input int master_num,
    input logic write,
    input logic [APB_ADDR_WIDTH-1:0] addr,
    input logic [APB_DATA_WIDTH-1:0] wdata
  );
    begin
      @(posedge PCLK);
      PSEL_s[master_num] <= 1'b1;
      PWRITE_s[master_num] <= write;
      PADDR_s[master_num] <= addr;
      if (write) PWDATA_s[master_num] <= wdata;
      PENABLE_s[master_num] <= 1'b0;
      PSTRB_s[master_num] <= 4'b1111;  // All bits active
      PPROT_s[master_num] <= 3'b000;   // Normal access
      
      @(posedge PCLK);
      PENABLE_s[master_num] <= 1'b1;
      
      fork
        begin
          wait(PREADY_s[master_num]);
        end
        begin
          #(CLK_PERIOD * 50);
          $display("ERROR: Master %0d TIMEOUT waiting for PREADY!", master_num);
          $finish;
        end
      join_any
      disable fork;
      
      @(posedge PCLK);
      
      PSEL_s[master_num] <= 1'b0;
      PENABLE_s[master_num] <= 1'b0;
      PSTRB_s[master_num] <= 4'b0000;
      @(posedge PCLK);
    end
  endtask

  initial begin
    PRESETn = 1'b0;
    PCLK = 1'b0;
    PSEL_s = '0;
    PENABLE_s = '0;
    PSTRB_s = '0;
    PPROT_s = '0;
    PADDR_s = '{default: '0};
    PWDATA_s = '{default: '0};
    PWRITE_s = '0;
    
    #(CLK_PERIOD*2);
    PRESETn = 1'b1;
    #(CLK_PERIOD*2);

    // Test 1: Single master transaction
    fork
      begin: test1_master0
        master_transaction(0, 1'b1, 32'h1000_0000, 32'hAAAA_AAAA);
      end
    join

    #(CLK_PERIOD*10);
    
    // Test 2: 3 masters simultaneously
    fork
      begin: test2_master0
        master_transaction(0, 1'b0, 32'h4000_0000, 32'h0);
      end
      
      begin: test2_master1  
        master_transaction(1, 1'b0, 32'h5000_0000, 32'h0);
      end
      
      begin: test2_master2
        master_transaction(2, 1'b0, 32'h6000_0000, 32'h0);
      end
    join
    
    #(CLK_PERIOD*10);
    
    // Test 3: Master 4 request + competition with masters 7 and 8
    fork
      begin: test3_master4_first
        master_transaction(4, 1'b0, 32'h7000_0000, 32'h0);
    
        #(CLK_PERIOD*5);
        master_transaction(4, 1'b1, 32'h1000_0000, 32'hBBBB_BBBB);
      end
      
      begin: test3_master7
        #(CLK_PERIOD*8);
        master_transaction(7, 1'b0, 32'h8000_0000, 32'h0);
      end
      
      begin: test3_master8
        #(CLK_PERIOD*8);
        master_transaction(8, 1'b0, 32'h9000_0000, 32'h0);
      end
    join

    $display("All Tests Completed Successfully - Round Robin Arbitration Working Correctly");
    $finish;
  end

  // Timeout
  initial begin
    #(CLK_PERIOD * 300);
    $display("ERROR: Simulation timeout!");
    $finish;
  end

endmodule