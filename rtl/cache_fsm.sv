`include "cache_pkg.sv"
import cache_pkg::*;

module cache_fsm(
  input  logic                clk,
  input  logic                rst,
  input  var cpu_req_type     cpu_req,     // CPU request input (CPU -> cache)
  input  var mem_data_type    mem_data,    // memory response (memory -> cache)
  output mem_req_type         mem_req,     // memory request (cache -> memory)
  output cpu_result_type      cpu_res,     // cache result (cache -> CPU)

  // New input ports for policy management
  input logic [3:0] config_domain_id,     // 
  input logic [3:0] config_fillmap,       // bit masking vector for missses
  input logic [3:0] config_hitmap,        // bit masking vector for hits
  input logic config_we                   // we for configuration of policies
);

  
  // write clock
  typedef enum { idle, compare_tag, allocate, write_back, flush } cache_state_type;
  // FSM state register
  cache_state_type vstate, rstate;

  // interface signals to tag memory
  cache_tag_type    tag_read[0:WAY_NUM-1];
  cache_tag_type    tag_write;
  logic             tag_req_we;
  
  // interface signals to cache data memory
  cache_data_type   data_read[0:WAY_NUM-1]; // cache line read data
  cache_data_type   data_write;             // cache line write data
  logic             data_req_we;            // data req

  // interface signals to cache data memory
  logic [WAY_NUM_BITS-1:0]      lru_read[0:WAY_NUM-1];
  logic [WAY_NUM_BITS-1:0]      lru_write[0:WAY_NUM-1];
  logic                         lru_req_we;

  // temporary variable for cache controller result
  cpu_result_type v_cpu_res;

  // temporary variable for memory controller result
  mem_req_type     v_mem_req;

  assign cpu_res = v_cpu_res;
  assign mem_req = v_mem_req;       // connect to output ports

  

  logic [TAG_WIDTH-1:0] tag;
  assign tag = cpu_req.addr[TAG_MSB:TAG_LSB];

  logic hit;
  logic [WAY_NUM-1:0] hit_way;

  logic found_allocation_candidate;
  logic [WAY_NUM_BITS-1:0] lru_way;
  logic [WAY_NUM_BITS-1:0] temp_lru;
  logic [WAY_NUM_BITS-1:0] max_lru_value; // oldest LRU value found so far (assuming 0=MRU, 3=LRU)


  // DAWG's policy_fillmap: a bit vector for each domain_id, indicating allowed ways for allocating and evicting
  // DAWG's policy_hitmap: a bit vector for each domain_id, indicating allowed ways for hits
  // assuming 4 possible domain_ids (from 2 bit domain_id)
  // each entry is 4 bits (one bit per way for a 4-way cache).
  logic [WAY_NUM-1:0] policy_fillmap[3:0];    //[way][domain_id]
  logic [WAY_NUM-1:0] policy_hitmap[3:0];     //[way][domain_id]

  // get the current protection domain's fill- and hitmap
  logic [WAY_NUM-1:0] current_domain_fillmap;
  logic [WAY_NUM-1:0] current_domain_hitmap;
  assign current_domain_fillmap = policy_fillmap[cpu_req.domain_id];
  assign current_domain_hitmap  = policy_hitmap[cpu_req.domain_id];

  logic domain_ways_assigned;



  integer i, found_element;

  // synchronous flush signals to avoid races
  logic wb_from_flush_r, wb_from_flush_n;
  logic flush_found;
  logic [WAY_NUM_BITS-1:0] flush_way_r, flush_way_n;

  always_comb begin
    // Default values for all signals

    // no state change by default
    vstate       = rstate;
    
    v_cpu_res    = '{0, 0};
    tag_write    = '{0, 0, 0, 0};
    // ideally set tag_write.domain_id to some default value that does not leak information
    // => have a fallback domain

    index = cpu_req.addr[INDEX_MSB:INDEX_LSB];


    // read tag by default
    tag_req_we   = '0;

    // read current cache line by default
    data_req_we  = '0;

    // read lru by default
    lru_req_we = '0;

    // modify correct word (32-bit) based on address
    data_write = data_read[way_index];
    case (cpu_req.addr[3:2])
      2'b00: data_write[31:0]   = cpu_req.data;
      2'b01: data_write[63:32]  = cpu_req.data;
      2'b10: data_write[95:64]  = cpu_req.data;
      2'b11: data_write[127:96] = cpu_req.data;
    endcase

    // read out correct word (32-bit) from cache (to CPU)
    case (cpu_req.addr[3:2])
      2'b00: v_cpu_res.data = data_read[way_index][31:0];
      2'b01: v_cpu_res.data = data_read[way_index][63:32];
      2'b10: v_cpu_res.data = data_read[way_index][95:64];
      2'b11: v_cpu_res.data = data_read[way_index][127:96];
    endcase


    // memory request address (sampled from CPU request)
    v_mem_req.addr = cpu_req.addr;
    // memory request data (used in write)
    v_mem_req.data = data_read[way_index];
    v_mem_req.rw = '0;

    // hit logic
    hit = 1'b0;
    hit_way = 4'b0;

    // default flush signals for next state
    // hold current
    wb_from_flush_n = wb_from_flush_r;
    flush_way_n = flush_way_r;


    // Cache FSM
    case (rstate)
      idle: begin
        // signal to flush a cache line, to simulate Intel's CLFLUSH
        if (cpu_req.flush) begin
          vstate = flush;
        end
        // if there is a CPU request, then compare cache tag
        else if (cpu_req.valid) begin
          vstate = compare_tag;
        end
      end


      compare_tag: begin
        // cache hit (tag match and cache entry is valid, and the domain is allowed to hit)
        for (int i = 0; i < WAY_NUM; i++) begin
          if ((tag_read[i].tag == tag) && tag_read[i].valid && current_domain_hitmap[i]) begin
            hit = 1'b1;
            hit_way[i] = 1'b1;
            way_index = i; // way index found
            break;
          end
        end

        // if the current policy hitmap for the domain does not allow hits, ignore and do not update data, tag, lru memories
        // this was meant to transition a request from COMPARE -> IDLE
        // it would however introduce a new side channel revealing that another domain recently accessed that address
        //if (!current_domain_hitmap[way_index]) begin
        //  $display("[%0t] Not allowed to access way", $time);
        //  vstate = idle;
        //end

        // cache hit (tag match and cache entry is valid, and the domain is allowed to hit)
        if (hit) begin
          v_cpu_res.ready = '1;
          
          // write hit
          if (cpu_req.rw) begin
            // read/modify cache line
            tag_req_we    = '1;
            data_req_we   = '1;

            // no change in tag
            //tag_write.tag   = tag_read[way_index].tag;
            tag_write   = tag_read[way_index];
            tag_write.valid = '1;
            // cache line is dirty
            tag_write.dirty = '1;
          end

          // action is finished
          vstate = idle;
          // update lru
          lru_req_we = '1;
        end
        
        // cache miss
        else begin
          // generate new tag
          tag_req_we    = '1;
          tag_write.valid = '1;
          lru_req_we = '1;

          // new tag
          //tag_write.tag   = cpu_req.addr[TAG_MSB:TAG_LSB];
          tag_write.tag   = tag;

          // cache line is dirty if write
          tag_write.dirty = cpu_req.rw;

          // generate memory request on miss
          v_mem_req.valid = '1;


          // allocation logic
          found_allocation_candidate = 1'b0;

          // find invalid (empty) way within the domain's allocated ways; invalid is equivalent to compulsory miss;
          for (i = 0; i < WAY_NUM; i++) begin
            if (current_domain_fillmap[i] && !tag_read[i].valid) begin // if way 'i' is allowed AND  invalid
              way_index = i;
              found_allocation_candidate = 1'b1;
              break; // found empty way
            end
          end


          if (found_allocation_candidate) begin
            vstate = allocate;
          end else begin
            // all ways have been already accessed
            // determine LRU way
            lru_way = 2'b00;              // default or error value
            max_lru_value = 2'b00;        // oldest LRU value found so far (assuming 0=MRU, 3=LRU)
            domain_ways_assigned = 1'b0;  // default value

            for (i = 0; i < WAY_NUM; i++) begin
              if (current_domain_fillmap[i]) begin // only consider ways allocated to this domain
                if (!domain_ways_assigned) begin
                  // in case there is only one way allocated to a domain;
                  // this ensures correct eviction of a single line, within the set associative structure
                  domain_ways_assigned = 1'b1;
                  max_lru_value = lru_read[i];
                  lru_way = i;
                end else if (lru_read[i] > max_lru_value) begin
                  // strictly older LRU found
                  max_lru_value = lru_read[i];
                  lru_way = i;
                end
              end
            end



            // LRU way is clean => allocate; LRU way is dirty => write back;
            // allowed way for eviction found
            if (domain_ways_assigned) begin
              if (!tag_read[lru_way].dirty) begin
                way_index = lru_way;  // update way index for next cycle
                vstate = allocate;
              end else begin
                v_mem_req.addr = {tag_read[lru_way].tag, cpu_req.addr[TAG_LSB-1:0]};
                v_mem_req.rw = '1;    // indicate write-back to memory
                vstate = write_back;
                way_index = lru_way;  // update way index for next cycle
              end
            end else begin
              // this should not happen
              $display("[%0t] Not allowed to evict way", $time);
              vstate = idle;
            end
          end
          
          if (!tag_read[way_index].valid) begin
            tag_write.domain_id = cpu_req.domain_id;
          end
        end
      end

      // wait for allocating a new cache line
      allocate: begin
        // memory controller has responded
        if (mem_data.ready) begin
          // re-compare tag for write miss (need modify correct word)
          vstate        = compare_tag;
          data_write    = mem_data.data;  
          
          // update cache line data
          data_req_we   = '1;
          // request to memory done
          v_mem_req.valid = '0;
        end
      end

      // wait for writing back dirty cache line
      write_back: begin
        // write back is completed
        if (mem_data.ready) begin
          // if it is a write back from the flush state
          if (wb_from_flush_r) begin    // read from the registered _r wb_from_flush to avoid races
            // invalidate tag
            tag_req_we = '1;
            tag_write = tag_read[flush_way_r];  // get the current tag line (valid, dirty, tag, domain_id)
            tag_write.valid = '0;
            tag_write.dirty = '0;
            lru_req_we = '1;
            way_index = flush_way_r;
            v_mem_req.valid = '0;
            wb_from_flush_n = '0;
            v_cpu_res.ready = '1; // ACK completion of flush
            $display("[%0t] Flush after WB success: line %0h", $time, cpu_req.addr);

            // tag_write.domain_id could also be set to a default fallback domain, in order to prevent leakage
            // the paper does not mention resetting the owner

            vstate = idle;
          end else begin
            // issue new memory request (allocating a new line)
            v_mem_req.valid = '1;
            v_mem_req.rw    = '0;

            vstate = allocate;
          end
        end
      end

      // flush a cache line
      flush: begin
        // find way to flush
        wb_from_flush_n = '0;
        flush_found = '0;
        // only the domain that owns the way may invalidate it
        for (i = 0; i < WAY_NUM; i++) begin
          if (tag_read[i].valid && tag_read[i].tag == tag && tag_read[i].domain_id == cpu_req.domain_id) begin
            // set flush_way as next state _n, then for reading in wb state use the registered _r to avoid races
            flush_way_n = i[WAY_NUM_BITS-1:0];
            flush_found = '1;
            break;
          end
        end

        if (!flush_found) begin
          // way to flush not found
          v_cpu_res.ready = '1; // ACK failure of flush
          $display("[%0t] Flush fail: line %0h", $time, cpu_req.addr);
          vstate = idle;
        end else begin
          if (tag_read[flush_way_n].dirty) begin
            // dirty line -> write back first
            v_mem_req.addr = {tag_read[flush_way_n].tag, cpu_req.addr[TAG_LSB-1:0]};
            v_mem_req.data = data_read[flush_way_n];
            v_mem_req.rw = '1;
            v_mem_req.valid = '1;
            // set wb_from_flush as next state _n, then for reading in wb state use the registered _r to avoid races
            wb_from_flush_n = '1;

            vstate = write_back;
          end else begin
            // invalidate tag
            tag_req_we = '1;
            tag_write = tag_read[flush_way_n];  // get the current tag line (valid, dirty, tag, domain_id)
            tag_write.valid = '0;
            tag_write.dirty = '0;
            lru_req_we = '1;
            way_index = flush_way_n;
            v_cpu_res.ready = '1; // ACK completion of flush
            $display("[%0t] Flush success: line %0h", $time, cpu_req.addr);

            // tag_write.domain_id could also be set to a default fallback domain, in order to prevent leakage
            // the paper does not mention resetting the owner

            vstate = idle;
          end
        end
      end
    endcase
    // -----------------------------------------------------------
    // Replacement policy (LRU)
    // -----------------------------------------------------------
    if (lru_req_we) begin

      // update if the accessed way is allowed for this domain
      if (current_domain_fillmap[way_index]) begin

        // LRU stack
        found_element = -1;
        for (i = 0; i < WAY_NUM; i++) if (order[i] == way_index) found_element = i;

        if (found_element == -1) begin
          // way not currently in order[] (should not happen) => treat as MRU:
          // shift right and insert at 0
          for (i = WAY_NUM-1; i >= 1; i--) begin
            order[i] = order[i-1];
          end
          order[0] = way_index;
        end else begin
          // move element at found_element to position 0, shift others right up to found_element-1
          for (i = found_element; i >= 1; i--) begin
            order[i] = order[i-1];
          end
          order[0] = way_index;
        end

        // convert order[] to lru_write[] values: lru_write[way] = position in order (0..3)
        for (i = 0; i < WAY_NUM; i++) begin
          temp_lru = order[i];
          lru_write[temp_lru] = i[WAY_NUM_BITS-1:0]; // i==0 => 0 (MRU), i==3 => 3 (LRU)
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      rstate <= idle;   // reset to idle state
      wb_from_flush_r <= 1'b0;
      flush_way_r <= '0;
      // reset policies
      for (int i = 0; i < 4; i++) begin
          policy_fillmap[i] <= 4'b0000;
          policy_hitmap[i]  <= 4'b0000;
      end
    end else begin
      rstate <= vstate;
      wb_from_flush_r <= wb_from_flush_n;
      flush_way_r <= flush_way_n;
      if (config_we) begin
        policy_fillmap[config_domain_id] <= config_fillmap;
        policy_hitmap[config_domain_id]  <= config_hitmap;
      end
    end
  end

  // connect cache tag/data memory
  cache_tag ctag(.*);
  cache_data cdata(.*);
  cache_lru clru(.*);
endmodule
