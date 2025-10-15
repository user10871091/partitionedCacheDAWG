`include "cache_pkg.sv"
import cache_pkg::*;

// cache: LRU memory, single port, 1024 blocks

module cache_lru(
  input  logic                      clk,
  input  logic                      lru_req_we,
  input  var [WAY_NUM_BITS-1:0]     lru_write[0:WAY_NUM-1],   // write port
  output logic [WAY_NUM_BITS-1:0]   lru_read[0:WAY_NUM-1],    // read port
  input  logic                      rst                       // Reset signal
);

  // cache lines
  logic [1:0] lru_mem[0:CACHE_LINES-1][0:WAY_NUM-1];

  // Use a reset condition to initialize memory
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      // Reset the memory on the first clock cycle
      for (int j = 0; j < WAY_NUM; j++) begin
        for (int i = 0; i < CACHE_LINES; i++) begin 
          lru_mem[i][j] <= '0;
        end
      end
      order = '{2'b00,2'b01,2'b10,2'b11};
    end else begin
      // Write to memory if write enable is high
      if (lru_req_we) begin
        for (int i = 0; i < WAY_NUM; i++) begin
          lru_mem[index][i] <= lru_write[i];
        end
      end
    end
  end

  for (genvar i = 0; i < WAY_NUM; i++) begin
    assign lru_read[i] = lru_mem[index][i];
  end
endmodule
