module apb_mux_top #(
  parameter NUM_APB_MASTERS = 16,
  parameter APB_ADDR_WIDTH = 32,
  parameter APB_DATA_WIDTH = 32
)(
  input                       PRESETn,
  input                       PCLK,
  
  // From masters
  input      [NUM_APB_MASTERS-1:0]    PSEL_s,
  input      [APB_ADDR_WIDTH-1:0]     PADDR_s [NUM_APB_MASTERS],
  input      [NUM_APB_MASTERS-1:0]    PWRITE_s,
  input      [APB_DATA_WIDTH-1:0]     PWDATA_s [NUM_APB_MASTERS],
  input      [NUM_APB_MASTERS-1:0]    PENABLE_s,
  input      [NUM_APB_MASTERS-1:0]    PSTRB_s,  
  input      [NUM_APB_MASTERS-1:0]    PPROT_s,  
  output reg [APB_DATA_WIDTH-1:0]     PRDATA_s [NUM_APB_MASTERS],
  output reg [NUM_APB_MASTERS-1:0]    PREADY_s,
  output reg [NUM_APB_MASTERS-1:0]    PSLVERR_s,
  
  // To slave
  output reg                      PSEL_m,
  output reg [APB_ADDR_WIDTH-1:0] PADDR_m,
  output reg                      PWRITE_m,
  output reg [APB_DATA_WIDTH-1:0] PWDATA_m,
  output reg                      PENABLE_m,
  output reg                      PSTRB_m,      
  output reg                      PPROT_m,      
  input      [APB_DATA_WIDTH-1:0] PRDATA_m,
  input                           PREADY_m,
  input                           PSLVERR_m
);

    localparam PTR_WIDTH = $clog2(NUM_APB_MASTERS);
    
    logic [PTR_WIDTH-1:0] ptr;
    logic [NUM_APB_MASTERS-1:0] current_master;
    logic [NUM_APB_MASTERS-1:0] shift_req;
    logic [NUM_APB_MASTERS-1:0] shift_gnt;
    logic [NUM_APB_MASTERS-1:0] gnt;

    // Round-robin arbiter
    always_comb begin
        // Right circular shift
        shift_req = {NUM_APB_MASTERS{1'b0}};
        for (int i = 0; i < NUM_APB_MASTERS; i++) begin
            shift_req[i] = PSEL_s[(i + ptr) % NUM_APB_MASTERS];
        end

        // Priority arbiter - find first set bit
        shift_gnt = {NUM_APB_MASTERS{1'b0}};
        for (int i = 0; i < NUM_APB_MASTERS; i++) begin
            if (shift_req[i]) begin
                shift_gnt[i] = 1'b1;
                break;
            end
        end

        // Left circular shift (reverse)
        gnt = {NUM_APB_MASTERS{1'b0}};
        for (int i = 0; i < NUM_APB_MASTERS; i++) begin
            gnt[i] = shift_gnt[(i + NUM_APB_MASTERS - ptr) % NUM_APB_MASTERS];
        end
    end

    // Pointer update
    always_ff @(posedge PCLK)
        if (!PRESETn)
            ptr <= {PTR_WIDTH{1'b0}};
        else if (|gnt) begin
            // Find granted master and set pointer to next
            for (int i = 0; i < NUM_APB_MASTERS; i++) begin
                if (gnt[i]) begin
                    ptr <= (i + 1) % NUM_APB_MASTERS;
                    break;
                end
            end
        end

    // Transaction FSM
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        SETUP = 2'b01, 
        ACCESS = 2'b10
    } state_t;

    state_t current_state, next_state;

    // FSM next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (|gnt) 
                    next_state = SETUP;
            end
            SETUP: begin
                next_state = ACCESS;
            end
            ACCESS: begin
                if (PREADY_m)
                    next_state = IDLE;
            end
        endcase
    end

    // FSM state register
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            current_state <= IDLE;
            current_master <= {NUM_APB_MASTERS{1'b0}};
        end else begin
            current_state <= next_state;
            
            // Start new transaction
            if (current_state == IDLE && next_state == SETUP) begin
                current_master <= gnt;
            end 
            // Complete transaction
            else if (current_state == ACCESS && PREADY_m) begin
                current_master <= {NUM_APB_MASTERS{1'b0}};
            end
        end
    end

    // Slave interface routing
    always_comb begin
        PSEL_m    = 1'b0;
        PADDR_m   = {APB_ADDR_WIDTH{1'b0}};
        PWRITE_m  = 1'b0;
        PWDATA_m  = {APB_DATA_WIDTH{1'b0}};
        PENABLE_m = 1'b0;
        PSTRB_m   = 1'b0;
        PPROT_m   = 1'b0;

        if (current_state != IDLE) begin
            for (int i = 0; i < NUM_APB_MASTERS; i++) begin
                if (current_master[i]) begin
                    PSEL_m    = PSEL_s[i];
                    PADDR_m   = PADDR_s[i];
                    PWRITE_m  = PWRITE_s[i];
                    PWDATA_m  = PWDATA_s[i];
                    PENABLE_m = (current_state == ACCESS) ? PENABLE_s[i] : 1'b0;
                    PSTRB_m   = PSTRB_s[i];
                    PPROT_m   = PPROT_s[i];
                end
            end
        end
    end

    // Master response routing 
    generate
        for (genvar i = 0; i < NUM_APB_MASTERS; i++) begin : master_resp_gen
            always_comb begin
                PRDATA_s[i]  = {APB_DATA_WIDTH{1'b0}};
                PREADY_s[i]  = 1'b0;
                PSLVERR_s[i] = 1'b0;

                if (current_master[i] && current_state == ACCESS) begin
                    PRDATA_s[i]  = PRDATA_m;
                    PREADY_s[i]  = PREADY_m;
                    PSLVERR_s[i] = PSLVERR_m;
                end
            end
        end
    endgenerate

endmodule