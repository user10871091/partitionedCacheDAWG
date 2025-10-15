`include "cache_pkg.sv"
import cache_pkg::*;

// cache: tag memory, single port, 1024 blocks

module cache_tag(
  input  logic                clk,
  input  logic                tag_req_we,             // tag request/command, e.g. RW, valid  
  input  var cache_tag_type   tag_write,              // write port
  output cache_tag_type       tag_read[0:WAY_NUM-1],  // read port
  input  logic                rst                     // Reset signal
);

  // cache lines
  cache_tag_type tag_mem[0:CACHE_LINES-1][0:WAY_NUM-1];

  // Use a reset condition to initialize tag_mem
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      // Reset the memory on the first clock cycle
      for (int j = 0; j < WAY_NUM; j++) begin
        for (int i = 0; i < CACHE_LINES; i++) begin 
          tag_mem[i][j] <= '0;
        end
      end
    end else begin
      // Write to tag memory if write enable is high
      if (tag_req_we)
        tag_mem[index][way_index] <= tag_write;
    end
  end

  for (genvar i = 0; i < WAY_NUM; i++) begin
    assign tag_read[i] = tag_mem[index][i];
  end
endmodule
