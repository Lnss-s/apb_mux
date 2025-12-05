Alina, [05.12.2025 9:52]
module apb_mux_top #(
    parameter NUM_APB_MASTERS = 16,
    parameter APB_ADDR_WIDTH  = 32,
    parameter APB_DATA_WIDTH  = 32
)(
    input                       PRESETn,
    input                       PCLK,

    // From masters
    input  [NUM_APB_MASTERS-1:0]           PSEL_s,
    input  [APB_ADDR_WIDTH-1:0]            PADDR_s [NUM_APB_MASTERS],
    input  [NUM_APB_MASTERS-1:0]           PWRITE_s,
    input  [APB_DATA_WIDTH-1:0]            PWDATA_s [NUM_APB_MASTERS],
    input  [NUM_APB_MASTERS-1:0]           PENABLE_s,
    input  [NUM_APB_MASTERS-1:0]           PSTRB_s,  
    input  [NUM_APB_MASTERS-1:0]           PPROT_s,  
    output reg [APB_DATA_WIDTH-1:0]        PRDATA_s [NUM_APB_MASTERS],
    output reg [NUM_APB_MASTERS-1:0]       PREADY_s,
    output reg [NUM_APB_MASTERS-1:0]       PSLVERR_s,

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

    // Pointer width ??? round-robin
    localparam PTR_WIDTH = $clog2(NUM_APB_MASTERS);

    // ----------------------
    // Internal signals
    // ----------------------
    logic [PTR_WIDTH-1:0]              ptr;            // round-robin pointer
    logic [NUM_APB_MASTERS-1:0]        current_master; // ??????? ?????? ? ACCESS
    logic [NUM_APB_MASTERS-1:0]        gnt;            // ??????? grant
    logic [NUM_APB_MASTERS-1:0]        shift_req;
    logic [NUM_APB_MASTERS-1:0]        shift_gnt;
    logic [2*NUM_APB_MASTERS-1:0]      double_req, double_gnt;

    logic found;
    // ----------------------
    // Round-robin arbiter ??? break
    // ----------------------
    always_comb begin
        double_req = {PSEL_s, PSEL_s} >> ptr;
        shift_req  = double_req[NUM_APB_MASTERS-1:0];

        shift_gnt = '0;
        found = 1'b0;

        for (int i = 0; i < NUM_APB_MASTERS; i++) begin
            if (shift_req[i] && !found) begin
                shift_gnt[i] = 1'b1;
                found = 1'b1;
            end else begin
                shift_gnt[i] = 1'b0;
            end
        end

        double_gnt = {shift_gnt, shift_gnt} << ptr;
        gnt        = double_gnt[2*NUM_APB_MASTERS-1:NUM_APB_MASTERS];
    end

    // ----------------------
    // Pointer update
    // ----------------------
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            ptr <= '0;
        else if (|gnt) begin
            for (int i = 0; i < NUM_APB_MASTERS; i++) begin
                if (gnt[i]) begin
                    ptr <= (i == NUM_APB_MASTERS-1) ? '0 : i + 1;
                end
            end
        end
    end

    // ----------------------
    // Transaction FSM
    // ----------------------
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        SETUP  = 2'b01,
        ACCESS = 2'b10
    } state_t;

    state_t current_state, next_state;

    // Next state logic
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

Alina, [05.12.2025 9:52]
// State register + current_master update
    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            current_state  <= IDLE;
            current_master <= '0;
        end else begin
            current_state <= next_state;
            
            // Start new transaction
            if (current_state == IDLE && next_state == SETUP)
                current_master <= gnt;
            // Transaction complete
            else if (current_state == ACCESS && PREADY_m)
                current_master <= '0;
        end
    end

    // ----------------------
    // Slave interface routing
    // ----------------------
    always_comb begin
        PSEL_m    = 1'b0;
        PADDR_m   = '0;
        PWRITE_m  = 1'b0;
        PWDATA_m  = '0;
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

    // ----------------------
    // Master response routing
    // ----------------------
    generate
        for (genvar i = 0; i < NUM_APB_MASTERS; i++) begin : master_resp_gen
            always_comb begin
                PRDATA_s[i]  = '0;
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
