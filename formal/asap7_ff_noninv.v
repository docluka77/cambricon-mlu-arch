module DFFHQNx1_ASAP7_75t_R (input CLK, input D, output QN);
  reg Q;
  always @(posedge CLK) Q <= D;
  assign QN = ~Q;
endmodule

module DFFASRHQNx1_ASAP7_75t_R (input CLK, input D, output QN, input RESETN, input SETN);
  reg Q;
  always @(posedge CLK or negedge RESETN or negedge SETN) begin
    if (!RESETN) Q <= 1'b0;
    else if (!SETN) Q <= 1'b1;
    else Q <= D;
  end
  assign QN = ~Q;
endmodule
