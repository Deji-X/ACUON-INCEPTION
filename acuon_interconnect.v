`timescale 1ns/1ps
// Acuon Phase-1 teaching baseline.
// Deliberate limits: one outstanding transaction globally; single-beat only.
// Address map and arbitration policy marked P in the source specification.
module acuon_interconnect #(
    parameter [63:0] ROM_BASE  = 64'h0000_0000,
    parameter [63:0] ROM_SIZE  = 64'h0001_0000,
    parameter [63:0] SRAM_BASE = 64'h1000_0000,
    parameter [63:0] SRAM_SIZE = 64'h0004_0000,
    parameter [63:0] MMIO_BASE = 64'h2000_0000,
    parameter [63:0] MMIO_SIZE = 64'h0000_8000,
    parameter [63:0] MEM_BASE  = 64'h8000_0000,
    parameter [63:0] MEM_SIZE  = 64'h0100_0000,
    parameter integer TIMEOUT_CYCLES = 32
)(
    input clk, input rst_n,

    input [2:0] m_valid, output reg [2:0] m_ready,
    input [191:0] m_addr, input [191:0] m_wdata,
    input [2:0] m_write, input [23:0] m_byte_en,
    input [11:0] m_id, input [2:0] m_last,

    output reg [2:0] m_rsp_valid, input [2:0] m_rsp_ready,
    output reg [191:0] m_rdata, output reg [11:0] m_rsp_id,
    output reg [2:0] m_rsp_last, output reg [2:0] m_error,

    // Slave 0: main memory
    output reg s0_valid, input s0_ready, output reg [63:0] s0_addr,
    output reg [63:0] s0_wdata, output reg s0_write, output reg [7:0] s0_byte_en,
    output reg [3:0] s0_id, output reg s0_last,
    input s0_rsp_valid, output s0_rsp_ready, input [63:0] s0_rdata,
    input [3:0] s0_rsp_id, input s0_rsp_last, input s0_error,

    // Slave 1: ROM (read-only)
    output reg s1_valid, input s1_ready, output reg [63:0] s1_addr,
    output reg [63:0] s1_wdata, output reg s1_write, output reg [7:0] s1_byte_en,
    output reg [3:0] s1_id, output reg s1_last,
    input s1_rsp_valid, output s1_rsp_ready, input [63:0] s1_rdata,
    input [3:0] s1_rsp_id, input s1_rsp_last, input s1_error,

    // Slave 2: CPU-local SRAM
    output reg s2_valid, input s2_ready, output reg [63:0] s2_addr,
    output reg [63:0] s2_wdata, output reg s2_write, output reg [7:0] s2_byte_en,
    output reg [3:0] s2_id, output reg s2_last,
    input s2_rsp_valid, output s2_rsp_ready, input [63:0] s2_rdata,
    input [3:0] s2_rsp_id, input s2_rsp_last, input s2_error,

    // Slave 3: MMIO fabric
    output reg s3_valid, input s3_ready, output reg [63:0] s3_addr,
    output reg [63:0] s3_wdata, output reg s3_write, output reg [7:0] s3_byte_en,
    output reg [3:0] s3_id, output reg s3_last,
    input s3_rsp_valid, output s3_rsp_ready, input [63:0] s3_rdata,
    input [3:0] s3_rsp_id, input s3_rsp_last, input s3_error
);
    localparam [1:0] T_ROM=0, T_SRAM=1, T_MMIO=2, T_MEM=3;
    reg busy;
    reg [1:0] owner, target, rr;
    reg [31:0] timer;
    reg local_rsp;
    reg [1:0] local_owner;
    reg local_error;
    reg [3:0] saved_id;
    reg saved_last;

    reg [1:0] chosen;
    reg found;
    reg [63:0] a, wd;
    reg wr, last;
    reg [7:0] be;
    reg [3:0] id;
    reg [1:0] dec;
    integer n, ix;

    function in_range;
        input [63:0] address, base, size;
        begin in_range = (address >= base) && (address < base + size); end
    endfunction

    function [1:0] decode;
        input [63:0] address;
        begin
            if (in_range(address, ROM_BASE, ROM_SIZE)) decode=T_ROM;
            else if (in_range(address, SRAM_BASE, SRAM_SIZE)) decode=T_SRAM;
            else if (in_range(address, MMIO_BASE, MMIO_SIZE)) decode=T_MMIO;
            else decode=T_MEM; // range-checked separately below
        end
    endfunction

    always @* begin
        found=0; chosen=rr;
        for (n=0; n<3; n=n+1) begin
            ix=rr+n; if (ix>=3) ix=ix-3;
            if (!found && m_valid[ix]) begin found=1; chosen=ix[1:0]; end
        end
        a=m_addr[chosen*64 +: 64];
        wd=m_wdata[chosen*64 +: 64];
        wr=m_write[chosen];
        be=m_byte_en[chosen*8 +: 8];
        id=m_id[chosen*4 +: 4];
        last=m_last[chosen];
        dec=decode(a);

        m_ready=0;
        s0_valid=0; s1_valid=0; s2_valid=0; s3_valid=0;
        s0_addr=a; s1_addr=a; s2_addr=a; s3_addr=a;
        s0_wdata=wd; s1_wdata=wd; s2_wdata=wd; s3_wdata=wd;
        s0_write=wr; s1_write=wr; s2_write=wr; s3_write=wr;
        s0_byte_en=be; s1_byte_en=be; s2_byte_en=be; s3_byte_en=be;
        s0_id=id; s1_id=id; s2_id=id; s3_id=id;
        s0_last=last; s1_last=last; s2_last=last; s3_last=last;

        if (!busy && !local_rsp && found) begin
            if (!in_range(a, ROM_BASE, ROM_SIZE) &&
                !in_range(a, SRAM_BASE, SRAM_SIZE) &&
                !in_range(a, MMIO_BASE, MMIO_SIZE) &&
                !in_range(a, MEM_BASE, MEM_SIZE)) begin
                m_ready[chosen]=1; // invalid address -> local error response
            end else case (dec)
                T_ROM: if (chosen==0 && !wr) begin s1_valid=m_valid[chosen]; if(s1_ready)m_ready[chosen]=1; end
                       else m_ready[chosen]=1;
                T_SRAM: if (chosen==0) begin s2_valid=m_valid[chosen]; if(s2_ready)m_ready[chosen]=1; end
                        else m_ready[chosen]=1;
                T_MMIO: if (chosen==0) begin s3_valid=m_valid[chosen]; if(s3_ready)m_ready[chosen]=1; end
                        else m_ready[chosen]=1;
                T_MEM: begin s0_valid=m_valid[chosen]; if(s0_ready)m_ready[chosen]=1; end
            endcase
        end
    end

    reg [63:0] rd_mux;
    reg [3:0] rid_mux;
    reg rlast_mux, rerr_mux, rv_mux;
    always @* begin
        rd_mux=0; rid_mux=0; rlast_mux=1; rerr_mux=0; rv_mux=0;
        case(target)
            T_MEM:  begin rd_mux=s0_rdata; rid_mux=s0_rsp_id; rlast_mux=s0_rsp_last; rerr_mux=s0_error; rv_mux=s0_rsp_valid; end
            T_ROM:  begin rd_mux=s1_rdata; rid_mux=s1_rsp_id; rlast_mux=s1_rsp_last; rerr_mux=s1_error; rv_mux=s1_rsp_valid; end
            T_SRAM: begin rd_mux=s2_rdata; rid_mux=s2_rsp_id; rlast_mux=s2_rsp_last; rerr_mux=s2_error; rv_mux=s2_rsp_valid; end
            T_MMIO: begin rd_mux=s3_rdata; rid_mux=s3_rsp_id; rlast_mux=s3_rsp_last; rerr_mux=s3_error; rv_mux=s3_rsp_valid; end
        endcase
        m_rsp_valid=0; m_rdata=0; m_rsp_id=0; m_rsp_last=0; m_error=0;
        if (busy && rv_mux) begin
            m_rsp_valid[owner]=1;
            m_rdata[owner*64 +: 64]=rd_mux;
            m_rsp_id[owner*4 +: 4]=rid_mux;
            m_rsp_last[owner]=rlast_mux;
            m_error[owner]=rerr_mux;
        end
        if (local_rsp) begin
            m_rsp_valid[local_owner]=1;
            m_rsp_id[local_owner*4 +: 4]=saved_id;
            m_rsp_last[local_owner]=saved_last;
            m_error[local_owner]=local_error;
        end
    end

    assign s0_rsp_ready = busy && target==T_MEM && m_rsp_ready[owner];
    assign s1_rsp_ready = busy && target==T_ROM && m_rsp_ready[owner];
    assign s2_rsp_ready = busy && target==T_SRAM && m_rsp_ready[owner];
    assign s3_rsp_ready = busy && target==T_MMIO && m_rsp_ready[owner];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy<=0; owner<=0; target<=T_MEM; rr<=0; timer<=0;
            local_rsp<=0; local_owner<=0; local_error<=0; saved_id<=0; saved_last<=1;
        end else begin
            if (local_rsp && m_rsp_ready[local_owner]) local_rsp<=0;
            if (!busy && !local_rsp && found && m_ready[chosen]) begin
                saved_id<=id; saved_last<=last;
                if ((!in_range(a,ROM_BASE,ROM_SIZE) &&
                     !in_range(a,SRAM_BASE,SRAM_SIZE) &&
                     !in_range(a,MMIO_BASE,MMIO_SIZE) &&
                     !in_range(a,MEM_BASE,MEM_SIZE)) ||
                    (in_range(a,ROM_BASE,ROM_SIZE) && (chosen!=0 || wr)) ||
                    (in_range(a,SRAM_BASE,SRAM_SIZE) && chosen!=0) ||
                    (in_range(a,MMIO_BASE,MMIO_SIZE) && chosen!=0)) begin
                    local_rsp<=1; local_owner<=chosen; local_error<=1;
                end else begin
                    busy<=1; owner<=chosen; target<=decode(a); timer<=0;
                end
                rr <= (chosen==2) ? 0 : chosen+1'b1;
            end else if (busy) begin
                if (rv_mux && m_rsp_ready[owner]) begin busy<=0; timer<=0; end
                else if (TIMEOUT_CYCLES>0) begin
                    if (timer>=TIMEOUT_CYCLES-1) begin
                        busy<=0; timer<=0;
                        local_rsp<=1; local_owner<=owner; local_error<=1;
                        saved_id<=m_id[owner*4 +: 4];
                        saved_last<=1;
                    end else timer<=timer+1;
                end
            end
        end
    end
endmodule
