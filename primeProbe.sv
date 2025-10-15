`timescale 1ns/1ps
`include "rtl/cache_fsm.sv"
import cache_pkg::*;

module primeProbe;

  bit clk, rst;
  cpu_req_type   cpu_req;
  cpu_result_type cpu_res;
  mem_req_type    mem_req;
  mem_data_type   mem_data;

  // Policy signals
  logic [3:0] config_domain_id;
  logic [3:0] config_fillmap;
  logic [3:0] config_hitmap;
  logic config_we;

  // Clock
  initial clk = 0;
  always #5 clk = ~clk;

  // Instantiate cache
  cache_fsm cache(
    .clk(clk), .rst(rst),
    .cpu_req(cpu_req),
    .cpu_res(cpu_res),
    .mem_req(mem_req),
    .mem_data(mem_data),
    .config_domain_id(config_domain_id),
    .config_fillmap(config_fillmap),
    .config_hitmap(config_hitmap),
    .config_we(config_we)
  );

  // data ring to ease testing, providing data that comes from main memory
  // use data of all x's, where x is 1 - F;
  // 0 not used to avoid confusion with initial state of 0's
  int data_ring;
  initial data_ring = 1;

  int wait_time, start_time, end_time;

  task mem_data_allocate;
    case (data_ring)
      1: begin
        mem_data = '{data:128'h11111111_11111111_11111111_11111111, ready:1};
        data_ring++;
      end

      2: begin
        mem_data = '{data:128'h22222222_22222222_22222222_22222222, ready:1};
        data_ring++;
      end

      3: begin
        mem_data = '{data:128'h33333333_33333333_33333333_33333333, ready:1};
        data_ring++;
      end

      4: begin
        mem_data = '{data:128'h44444444_44444444_44444444_44444444, ready:1};
        data_ring++;
      end

      5: begin
        mem_data = '{data:128'h55555555_55555555_55555555_55555555, ready:1};
        data_ring++;
      end

      6: begin
        mem_data = '{data:128'h66666666_66666666_66666666_66666666, ready:1};
        data_ring++;
      end

      7: begin
        mem_data = '{data:128'h77777777_77777777_77777777_77777777, ready:1};
        data_ring++;
      end

      8: begin
        mem_data = '{data:128'h88888888_88888888_88888888_88888888, ready:1};
        data_ring++;
      end

      9: begin
        mem_data = '{data:128'h99999999_99999999_99999999_99999999, ready:1};
        data_ring++;
      end

      10: begin
        mem_data = '{data:128'hAAAAAAAA_AAAAAAAA_AAAAAAAA_AAAAAAAA, ready:1};
        data_ring++;
      end

      11: begin
        mem_data = '{data:128'hBBBBBBBB_BBBBBBBB_BBBBBBBB_BBBBBBBB, ready:1};
        data_ring++;
      end

      12: begin
        mem_data = '{data:128'hCCCCCCCC_CCCCCCCC_CCCCCCCC_CCCCCCCC, ready:1};
        data_ring++;
      end

      13: begin
        mem_data = '{data:128'hDDDDDDDD_DDDDDDDD_DDDDDDDD_DDDDDDDD, ready:1};
        data_ring++;
      end

      14: begin
        mem_data = '{data:128'hEEEEEEEE_EEEEEEEE_EEEEEEEE_EEEEEEEE, ready:1};
        data_ring++;
      end

      15: begin
        mem_data = '{data:128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, ready:1};
        data_ring = 1;
      end
    endcase
  endtask


  // Task to set policies
  task set_domain_policy;
    input [1:0] domain_id;
    input [3:0] fillmap;
    input [3:0] hitmap;
    begin
        @(negedge clk);
        config_domain_id = domain_id;
        config_fillmap = fillmap;
        config_hitmap = hitmap;
        config_we = 1;
        @(negedge clk);
        config_we = 0;
        //$display("[%0t] Set policy for domain %0d: fillmap=0b%b, hitmap=0b%b", $time, domain, fillmap, hitmap);
    end
  endtask


  // Task for cpu requests
  task rw_request;
    input [31:0] addr;
    input [127:0] data;
    input rw;
    input flush;
    input [1:0] domain_id;
    //input valid;

    begin
      @(negedge clk);
      cpu_req.addr        = addr;
      cpu_req.data        = data;
      cpu_req.rw          = rw;
      cpu_req.valid       = 1;
      cpu_req.flush       = flush;
      cpu_req.domain_id   = domain_id;

      wait_time = 0;
      start_time = $time;
      @(negedge clk);
      cpu_req.valid = 0;
      while (!(mem_req.valid || cpu_res.ready)) begin
          @(negedge clk);
      end

      // miss
      if (mem_req.valid) begin
        if (mem_req.rw) begin
          // delay for simulating data transfer Cache -> MEM (WRITE BACK)
          wait_time = $urandom_range(5, 10);
          $display("[%0t] WRITE BACK wait_time = %0d", $time, wait_time);
          repeat(wait_time) @(negedge clk);

          mem_data.ready = 1;  // acknowledge write-back

          if (cpu_req.flush) begin
            end_time = $time - start_time;
            cpu_req.flush = 0;
            @(negedge clk);
            mem_data.ready = 0;
            return;
          end

          @(negedge clk);
          mem_data.ready = 0;
        end

        // delay for simulating data transfer MEM -> Cache (ALLOCATE)
        wait_time = $urandom_range(1, 3);
        $display("[%0t] ALLOCATE wait_time = %0d", $time, wait_time);
        repeat(wait_time)@(negedge clk);
        mem_data_allocate();
      end
      // hit
      else if (cpu_res.ready) begin
        //$display("[%0t] CPU read HIT. Data = 0x%08h", $time, cpu_res.data);
        //cpu_req.valid = 0;
        cpu_req.flush = 0;
      end

      end_time = $time - start_time;
      @(negedge clk);
      mem_data.ready = 0;

    end
  endtask

  initial begin
    // ------------------------------------------------------------
    // Initialize all inputs
    // ------------------------------------------------------------
    cpu_req = '{default:0};
    mem_data = '{default:0};
    rst = 1;

    // ------------------------------------------------------------
    // Apply reset for two cycles (0–20 ns)
    // ------------------------------------------------------------
    #20 rst = 0;
    // 20 ns

    // set_domain_policy(domain_id, fill_map, hit_map)
    set_domain_policy(2'b00, 4'b1111, 4'b1111); // Privileged process gets e.g. domain 0, and all ways
    set_domain_policy(2'b01, 4'b0011, 4'b0011); // Victim gets domain 1, and ways 0, 1
    set_domain_policy(2'b11, 4'b1100, 4'b1100); // Attacker gets domain 3, and ways 2, 3

    // ------------------------------------------------------------
    // Attacker primes
    // ------------------------------------------------------------
    // rw_request(addr, data, rw, flush, domain_id)
    @(posedge clk);
    rw_request(32'h1111_0010, 0, 1, 0, 3);  // write miss (ALLOCATE), way 2
    @(posedge clk);
    rw_request(32'h3333_0010, 0, 1, 0, 3);  // write miss (ALLOCATE), way 3

    // ------------------------------------------------------------
    // Victim access
    // ------------------------------------------------------------
    @(posedge clk);
    rw_request(32'hABCD_0010, 0, 0, 0, 1);  // read miss (ALLOCATE), way 0

    // ------------------------------------------------------------
    // Attacker probes
    // ------------------------------------------------------------
    @(posedge clk);
    rw_request(32'h3333_0010, 0, 0, 0, 3);  // read hit, way 3
    @(posedge clk);
    rw_request(32'h1111_0010, 0, 0, 0, 3);  // read hit, way 2

    #20 $finish;
  end
endmodule
