module Accelerator#(
  parameter int unsigned W = 64 //64 bit Accelerator, change here if you want to increase or reduce the module size.
)(
  input  logic [W-1:0] a,
  input  logic [W-1:0] b,
  input  logic [W-1:0] result,
  input  logic         is_sub,
  output logic         overflow,
  output logic         carry
);

  //EDIT AS WE GO ON.
