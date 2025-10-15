package cache_pkg;
    // Tag and index parameters
    parameter TAG_MSB = 31;
    parameter TAG_LSB = 14;
    parameter INDEX_MSB = 13;
    parameter INDEX_LSB = 4;

    parameter CACHE_LINES = 1024;
    parameter WAY_NUM = 4;
    parameter WAY_NUM_BITS = $clog2(WAY_NUM);
    parameter TAG_WIDTH = TAG_MSB - TAG_LSB + 1;

    // data structure for cache tag
    typedef struct packed {
        logic [1:0] domain_id;          // protection domain ID for the cache line
                                        // four distinct security domains (e.g. OS kernel, trusted application, untrusted application, hypervisor)
        logic valid;                    // valid bit
        logic dirty;                    // dirty bit
        logic [TAG_MSB:TAG_LSB] tag;      // tag bits
    } cache_tag_type;


    typedef logic [127:0] cache_data_type;



    // data structures for CPU <-> Cache controller interface

    // CPU request (CPU -> cache controller)
    typedef struct {
        logic [31:0]addr;               // 32-bit request addr
        logic [31:0]data;               // 32-bit request data (used when write)
        logic rw;                       // request type : 0 = read, 1 = write
        logic valid;                    // request is valid
        logic flush;                    // flush bit for Flush+Reload
        logic [1:0] domain_id;          // protection domain ID (e.g., 2 bits for 4 domains)
                                        // domain_id coming from the CPU, typically held in a special CPU register that only trusted software can modify
    } cpu_req_type;

    // Cache result (cache controller -> cpu)
    typedef struct {
        logic [31:0]data;               // 32-bit data
        logic ready;                    // result is ready
    } cpu_result_type;



    // data structures for cache controller <-> memory interface

    // memory request (cache controller -> memory)
    typedef struct {
        logic [31:0]addr;               // request byte addr
        logic [127:0]data;              // 128-bit request data (used when write)
        logic rw;                       // request type : 0 = read, 1 = write
        logic valid;                    // request is valid
    } mem_req_type;

    // memory controller response (memory -> cache controller)
    typedef struct {
        cache_data_type data;           // 128-bit read back data
        logic ready;                    // data is ready
    } mem_data_type;

    logic [9:0] index;
    logic [WAY_NUM_BITS-1:0] way_index;
    
    // order array
    logic [WAY_NUM_BITS-1:0] order[0:WAY_NUM-1];

endpackage
