`include "cache_pkg.sv"
import cache_pkg::*;

// cache: data memory, single port, 1024 blocks

module cache_data(
  input  logic              clk,
  input  logic              data_req_we,            // data request/command, e.g. RW, valid
  input  cache_data_type    data_write,             // write port (128-bit line)
  output cache_data_type    data_read[0:WAY_NUM-1], // read port
  input  logic              rst                     // Reset signal
);

  // cache lines
  cache_data_type data_mem[0:CACHE_LINES-1][0:WAY_NUM-1];

  // Use a reset condition to initialize memory
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      // Reset the memory on the first clock cycle
      for (int j = 0; j < WAY_NUM; j++) begin
        for (int i = 0; i < CACHE_LINES; i++) begin 
          data_mem[i][j] <= '0;
        end
      end
    end else begin
      // Write to memory if write enable is high
      if (data_req_we)
        data_mem[index][way_index] <= data_write;
    end
  end

  for (genvar i = 0; i < WAY_NUM; i++) begin
    assign data_read[i] = data_mem[index][i];
  end
endmodule
