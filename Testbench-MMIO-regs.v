`timescale 1ns/1ps
module tb_acuon_mmio_regs;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg valid, write, last, rsp_ready;
    reg [63:0] addr, wdata;
    reg [7:0] byte_en;
    reg [3:0] id;
    wire ready, rsp_valid, rsp_last, error;
    wire [63:0] rdata;
    wire [3:0] rsp_id;
    wire [63:0] dma_src, dma_dst;
    wire [31:0] dma_len_bytes;
    wire dma_start_pulse;
    reg dma_busy=0, dma_done=0, dma_error=0;

    acuon_mmio_regs dut(
      .clk(clk),.rst_n(rst_n),.valid(valid),.ready(ready),.addr(addr),
      .wdata(wdata),.write(write),.byte_en(byte_en),.id(id),.last(last),
      .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rdata(rdata),.rsp_id(rsp_id),
      .rsp_last(rsp_last),.error(error),.dma_src(dma_src),.dma_dst(dma_dst),
      .dma_len_bytes(dma_len_bytes),.dma_start_pulse(dma_start_pulse),
      .dma_busy(dma_busy),.dma_done(dma_done),.dma_error(dma_error)
    );

    task mmio_write(input [63:0] a, input [63:0] d);
      begin
        @(negedge clk); addr=a; wdata=d; write=1; byte_en=8'hff; id=3; last=1; valid=1;
        @(posedge clk); while(!ready) @(posedge clk);
        @(negedge clk); valid=0;
        wait(rsp_valid); @(negedge clk); rsp_ready=1;
        @(posedge clk); @(negedge clk); rsp_ready=0;
      end
    endtask

    task mmio_read(input [63:0] a, output [63:0] d);
      begin
        @(negedge clk); addr=a; wdata=0; write=0; byte_en=8'hff; id=4; last=1; valid=1;
        @(posedge clk); while(!ready) @(posedge clk);
        @(negedge clk); valid=0;
        wait(rsp_valid); d=rdata;
        @(negedge clk); rsp_ready=1;
        @(posedge clk); @(negedge clk); rsp_ready=0;
      end
    endtask

    reg [63:0] tmp;
    initial begin
      valid=0; write=0; last=1; rsp_ready=0; addr=0; wdata=0; byte_en=0; id=0;
      repeat(3) @(posedge clk); rst_n=1;
      mmio_write(64'h000,64'h8000_0100);
      mmio_write(64'h008,64'h8000_0200);
      mmio_write(64'h010,128);
      mmio_read(64'h000,tmp); if(tmp!==64'h8000_0100) $fatal(1,"SRC readback failed");
      mmio_read(64'h008,tmp); if(tmp!==64'h8000_0200) $fatal(1,"DST readback failed");
      mmio_read(64'h010,tmp); if(tmp!==128) $fatal(1,"LEN readback failed");
      mmio_write(64'h018,1);
      @(negedge clk); if(!dma_start_pulse) $fatal(1,"start pulse missing");
      $display("PASS: Acuon MMIO register test"); $finish;
    end
endmodule
