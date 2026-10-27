`timescale 1ns/1ps
// Proposed DMA control register block. Confirm offsets against the full §4.1.
module acuon_mmio_regs (
    input clk, input rst_n,
    input valid, output ready, input [63:0] addr, input [63:0] wdata,
    input write, input [7:0] byte_en, input [3:0] id, input last,
    output rsp_valid, input rsp_ready, output [63:0] rdata,
    output [3:0] rsp_id, output rsp_last, output error,
    output reg [63:0] dma_src, output reg [63:0] dma_dst,
    output reg [31:0] dma_len_bytes, output reg dma_start_pulse,
    input dma_busy, input dma_done, input dma_error
);
    localparam [11:0] REG_SRC=12'h000, REG_DST=12'h008,
                      REG_LEN=12'h010, REG_CTRL=12'h018,
                      REG_STATUS=12'h020;
    reg pending;
    reg [63:0] data_q;
    reg [3:0] id_q;
    reg last_q, error_q, done_sticky, err_sticky;
    integer i;
    assign ready=!pending;
    assign rsp_valid=pending;
    assign rdata=data_q;
    assign rsp_id=id_q;
    assign rsp_last=last_q;
    assign error=error_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_src<=0; dma_dst<=0; dma_len_bytes<=0; dma_start_pulse<=0;
            pending<=0; data_q<=0; id_q<=0; last_q<=1; error_q<=0;
            done_sticky<=0; err_sticky<=0;
        end else begin
            dma_start_pulse<=0;
            if (dma_done) done_sticky<=1;
            if (dma_error) err_sticky<=1;
            if (pending && rsp_ready) pending<=0;
            if (valid && ready) begin
                pending<=1; id_q<=id; last_q<=last; error_q<=0; data_q<=0;
                if (write) begin
                    case (addr[11:0])
                        REG_SRC: for(i=0;i<8;i=i+1) if(byte_en[i]) dma_src[i*8 +: 8]<=wdata[i*8 +: 8];
                        REG_DST: for(i=0;i<8;i=i+1) if(byte_en[i]) dma_dst[i*8 +: 8]<=wdata[i*8 +: 8];
                        REG_LEN: for(i=0;i<4;i=i+1) if(byte_en[i]) dma_len_bytes[i*8 +: 8]<=wdata[i*8 +: 8];
                        REG_CTRL: if(byte_en[0] && wdata[0]) begin dma_start_pulse<=1; done_sticky<=0; err_sticky<=0; end
                        REG_STATUS: begin
                            if(byte_en[0] && wdata[1]) done_sticky<=0;
                            if(byte_en[0] && wdata[2]) err_sticky<=0;
                        end
                        default: error_q<=1;
                    endcase
                end else begin
                    case(addr[11:0])
                        REG_SRC: data_q<=dma_src;
                        REG_DST: data_q<=dma_dst;
                        REG_LEN: data_q<={32'd0,dma_len_bytes};
                        REG_CTRL: data_q<=0;
                        REG_STATUS: data_q<={61'd0,err_sticky,done_sticky,dma_busy};
                        default: error_q<=1;
                    endcase
                end
            end
        end
    end
endmodule
