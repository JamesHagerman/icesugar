// plug pmod-led on PMOD2 and pmod-switch on PMOD3
// Plug PCM5021 board into PMOD 1 pointing down into the table, VIN to the right corner, 


module i2s_tick #(parameter DATA_VALUE = 1) ( input [DATA_VALUE-1:0] some_data, output some_output );
  assign some_output = !some_data;
endmodule


module switch(  input P3_1, input P3_2,  input P3_3,  input P3_4,
                input P3_9, input P3_10, input P3_11, input P3_12,

                output P2_1, output P2_2,  output P2_3,  output P2_4,
                output P2_9, output P2_10, output P2_11, output P2_12,

                output P1_9
                );
      
  assign P2_1 = !P3_1;
  assign P2_2 = !P3_2;
  assign P2_3 = !P3_3;
  assign P2_4 = !P3_4;

  assign P2_9  = !P3_9;
  assign P2_10 = !P3_10;
  assign P2_11 = !P3_11;
  assign P2_12 = !P3_12;

  // Turn on pin 9 on PMOD1 port
  //assign P1_9 = 1;

  i2s_tick ticker(.some_data(1), .some_output(P1_9));

endmodule

