//
// I2S Audio DAC output example
// Author: james.hagerman@gmail.com
// Date: 2021-04-07
//
// Plug PCM5021 board into PMOD 1 pointing down into the table, VIN to the right corner.
// 
// For debugging, plug pmod-led on PMOD2 and pmod-switch on PMOD3
//
// Clock divider pattern taken from: https://excamera.com/sphinx/vhdl-clock.html
//

// module i2s_tick #(parameter DATA_VALUE = 1) ( input [DATA_VALUE-1:0] some_data, output some_output );
//   assign some_output = !some_data;
// 
//   always @(posedge clk)
//   begin
//     counter 
//   end
// endmodule


// Adjustable implementation of the arbitrary clock divider described here:
//  https://excamera.com/sphinx/vhdl-clock.html
//
// Remember: These clocks "tick" in pulses, not edges. You may need additional logic to convert to edges
//
// Usage: adjustableClock ticker(clk, hertz, lclk);
//  clk - the system clock input. This is assumed to be 6MHz
//  hertz - tick rate in hertz
//  lclk - The divided, lower frequency output
module adjustableClock ( input clk, input [7:0] hertz, output lclk );
  reg [24:0] d;
  wire [24:0] dInc = d[24] ? (hertz) : (hertz - 6000000);
  wire [24:0] dN = d + dInc;
  always @(posedge clk)
  begin
    d = dN;
  end
  assign lclk = ~d[24];  // clock tick whenever d[24] is zero
endmodule

// The top module in the design. The "entry point", as it were...
// TODO: This should probably be wrapped with a "stimulus" test harnass module of some kind. Or a dummy.
module top(  
                input clk,

                // PMOD Switches
                input P3_1, input P3_2,  input P3_3,  input P3_4,
                input P3_9, input P3_10, input P3_11, input P3_12,

                // PMOD LEDs
                output P2_1, output P2_2,  output P2_3,  output P2_4,
                output P2_9, output P2_10, output P2_11, output P2_12,

                // I2S "PMOD"
                output P1_4, output P1_3, output P1_2, // "Top" row of PMOD1 works, bottom has strange behavior on BCK output
                
                // PMOD1 remaining pins for debugging output
                output P1_9
                );

/* Original "switch to led bit" code:
  assign P2_1 = !P3_1;
  assign P2_2 = !P3_2;
  assign P2_3 = !P3_3;
  assign P2_4 = !P3_4;

  assign P2_9  = !P3_9;
  assign P2_10 = !P3_10;
  assign P2_11 = !P3_11;
  assign P2_12 = !P3_12;
*/

  // Some of my really early tests
  //
  // Turn on pin 9 on PMOD1 port
  // assign P1_9 = 1; // 1 is high, as expected

  // Try using a module 
  // i2s_tick ticker(.some_data(1), .some_output(P1_9));


  // Make it easier to spit a byte out to the LEDs for debugging
  reg [7:0] pmod_led_pins;
  assign {P2_4, P2_3, P2_2, P2_1, P2_9, P2_10, P2_11, P2_12} = ~pmod_led_pins; // ~ inverts the bits so a 1 is represented by a lit LED

  // Test code for debugging with the PMOD LEDs
  // // Create a test byte value to throw at our debug LEDs
  // wire [7:0] byteForLEDs;
  // //assign byteForLEDs = 12'h41; // Not needed since we're incrementing it using the adjustableClock

  // // Connect our LEDs to our test byte
  // assign pmod_led_pins = byteForLEDs; 

  // // Configure a counter register for the `adjustableClock` module to use
  // reg [25:0] counter;
  // wire lclk = counter[22];
  // adjustableClock ticker(clk, 2, lclk); // Instantiate an instance of the adjustableClock module to tick at 2Hz

  // // Use adjustableClock module output counter to increment the value in the register controlling to the debug LEDs
  // always @(posedge lclk)
  // begin
  //   byteForLEDs <= byteForLEDs + 1;
  // end


  // // Prep some test data for the i2sOutput module:
  // // TODO: This will have to be 2's complement signed, MSB data at some point...
  // integer mockAudio; // `integer` is a signed general purpose register data type (while `reg` stores unsigned values)
  // assign mockAudio = 0;

  // // Init the i2sOutput module with mock data:
  // i2sOutput audio(clk, mockAudio, P1_4, P1_3, P1_2, pmod_led_pins);

  // Generate an audio waveform:
  // integer monoAudioData; // `integer` is a signed general purpose register data type (while `reg` stores unsigned values)
  reg signed [15:0] monoAudioData;
  assign monoAudioData = 13; // 0b1101 = 13

  // We want a 440Hz square wave. System `clk` is 6MHz. 
  // TODO: This should probably be pinned to the sample rate so jitter there aligns with jitter here...
  reg [24:0] audioCounter;
  wire [24:0] audioInc = audioCounter[24] ? (440) : (440 - 6000000);
  wire [24:0] audioN = audioCounter + audioInc;
  always @(posedge clk)
  begin
    audioCounter = audioN;
  end
  wire audio_waveform_clock = ~audioCounter[24];  // clock B tick whenever audioCounter[24] is zero

  // Generate a simple square wave from the audio clock:
  reg i2s_audio_state;
  initial begin
    i2s_audio_state = 0;
  end
  always @(posedge audio_waveform_clock)
  begin
    i2s_audio_state = !i2s_audio_state;
    // P1_9 = i2s_audio_state; // debug output
    // monoAudioData = i2s_audio_state ? 1 : 0;
    P1_9 = monoAudioData[15]; // this is stupid
  end

  // Send 440Hz square wave to i2sOutput module instance:
  i2sOutput audio(clk, monoAudioData, P1_4, P1_3, P1_2, pmod_led_pins);

endmodule


//
// I2S Output module
//
// This Verilog module was designed to work with the PCM5100 series audio DACs that can be found on cheap
// breakout booards. By chance or design, the board I found happened to be compatible with the PMOD pin
// layout.
//
// This module has not been tested with other I2S DACs but the Adafruit I2S Stereo Decoder (UDA1334A) has
// a high chance of working. Note that the Adafruit board closely followed the datasheet reference design
// and thus the filter values have been found to reduce the quality of the audio output.
//
// Here are the PCM5100 pins:
//
// VIN - 3.3v MAX!
// GND - Analog and Digital grounds are tied together
// LCK - Audio data left-right clock/frame/word select; Frequency should be the sample rate (e.g. 44.1kHz)
// DIN - Audio data input; binary 2s complement, MSB-first, signed
// BCK - Audio data bit clock; Frequnecy should be: Sample Rate * Bit Depth * 2 (e.g. 44.1kHz * 16 * 2)
// SCK - System clock input; UNUSED!; tied low, the PCM5021 tries using BCK and a PLL to generate SCK
//
module i2sOutput(
  input clk, // System clock at 6MHz
  input [15:0] audioData, // binary 2s complement, MSB-first, signed, audio data
  output P1_4, output P1_3, output P1_2, // I2C output pins; LCK, DIN, BCK respectively
  output [7:0] debugLEDs // A register where we can drop some debugging output from the I2C module
);

  /////////////////
  // START: - I2S attempts

  // Try to build a sily sawtooth generator
  reg [15:0] audioBuffer; // Actual audio data per sample
  initial begin
    audioBuffer = 0;
  end

  reg [7:0] currentBit; // Current bit in the audioBuffer
  initial begin
    currentBit = 0;
  end


  reg [7:0] sampleNumber; // Current sample number (max of 255 for bitbyte attempt)
  initial begin
    sampleNumber = 0;
  end

  // Bind something to the debug leds:
  assign debugLEDs = ~currentBit; 



  // Generate BCK from system clock
  // Our system `clk` is 6MHz
  //
  // At first, we think we'd want a bit clock of something like: Sample Rate * Bit Depth * # of channels
  //  e.g. 44.1kHz * 16 * 2 = 1411200
  //
  // However, that means exactly 16 bits (bit depth) of data would be clocked in per channel, per frame.
  //
  // This isn't great for two reasons:
  //  1. Our clock dividers are prone to jitter and tight timing is probably something we should avoid
  //  2. The I2S audio data format pushes the LSB of each sample over into the next channel if the bit clock is 
  //     exactly 1/(bit depth) of the sample rate (LCK). That's a pain in the butt.
  //
  // Therefore, it would be easier if our bit clock was at least 2 times faster so we don't have to worry as much about that
  // channel boundary...
  // 
  // We still have to treat that boundary as special though! I2S data is NOT left justified (MSB at the exact beginning of the
  // channel boundary). The first bit of each channel has to be delayed by one tick of the bit clock (BCK).
  //
  // This could be avoided by re-configuring the board for the left justified data format, but I don't want to do that.
  //
  // Another issue is ensuring the data is set BEFORE the rising edge of BCK! This is part of the I2S spec and requires
  // us to make sure things happen in sequence.
  //
  // This means we have another item in our list of reasons to speed up our BCK:
  //  3. Timing of Data and BCK edges matter. Any delays in timing likely means we'll also be pushing past a channel boundary.
  //
  // Maybe this detail is exactly why I2S doesn't use left-justified data? Moving on...
  //
  reg [24:0] bckCounter;
  wire [24:0] bckInc = bckCounter[24] ? (1411200) : (1411200 - 6000000);
  wire [24:0] bckN = bckCounter + bckInc;
  always @(posedge clk)
  begin
    bckCounter = bckN;
  end
  wire bck_clk = ~bckCounter[24];  // clock B tick whenever d[24] is zero

  // Convert bck_clk pulse chain into a toggling clock value for BCK output
  reg i2s_bck_state;
  initial begin
    i2s_bck_state = 0;
  end
  always @(posedge bck_clk)
  begin
    // This is NOT the right place to increment the currentBit
    i2s_bck_state <= !i2s_bck_state;
  end

  // The i2s_bck_state rises 16 times every frame
  always @(negedge i2s_bck_state)
  begin
    currentBit <= currentBit + 1;
  end

  // Output the current bit value for this frame's sample on DIN pin:
  // Because we need the data as MSB first, we subtract the current bit index from one less than the Bit Rate (15 in this case)
  assign P1_3 = audioData[30-currentBit]; // DIN

  // Output BCK
  assign P1_2 = i2s_bck_state; // BCK


  // Generate an arbitrary LCK/sample rate clock from BCK
  // Remember: These clocks "tick" in pulses, not edges.
  //
  // We want a 44100Hz sample rate (LRCK/word select clock). And our BCK is 1411200 Hz.
  // When LCK is low, we're outputing the sample for the left channel. So falling edge represents moving to a new "frame"
  reg [24:0] d;
  wire [24:0] dInc = d[24] ? (44100) : (44100 - 1411200);
  wire [24:0] dN = d + dInc;
  always @(posedge bck_clk)
  begin
    d = dN;
  end
  wire sample_rate_clk = ~d[24];  // clock B tick whenever d[24] is zero

  // Convert pulse train to the expected LCK clock at the sample rate of 44.1 kHz
  // Rising edge means we should start outputting the bits for the Right channel.
  reg i2s_lrck_state;
  initial begin
    i2s_lrck_state = 0;
  end
  always @(posedge sample_rate_clk)
  begin
    i2s_lrck_state <= !i2s_lrck_state;
    //currentBit <= 1;
    //audioBuffer <= audioBuffer + 1;
  end

  // Connect the clean 44.1kHz LCK to the correct output pin:
  assign P1_4 = ~i2s_lrck_state; // LCK

  // On falling edge, we're starting to process a new frame
  always @(negedge i2s_lrck_state)
  begin
    sampleNumber <= sampleNumber + 1; // Increment the sampleNumber
  end


endmodule // i2s





// simple uart from: https://excamera.com/sphinx/fpga-uart.html#uart
/*
module uart(
   // Outputs
   uart_busy,   // High means UART is transmitting
   uart_tx,     // UART transmit wire
   // Inputs
   uart_wr_i,   // Raise to transmit byte
   uart_dat_i,  // 8-bit data
   clk,   // System clock, 6 MHz
   sys_rst_i    // System reset
);

  input uart_wr_i;
  input [7:0] uart_dat_i;
  input clk;
  input sys_rst_i;

  output uart_busy;
  output uart_tx;

  reg [3:0] bitcount;
  reg [8:0] shifter;
  reg uart_tx;

  wire uart_busy = |bitcount[3:1];
  wire sending = |bitcount;

  // clk is 6MHz.  We want a 115200Hz clock

  reg [28:0] d;
  wire [28:0] dInc = d[28] ? (115200) : (115200 - 6000000);
  wire [28:0] dNxt = d + dInc;
  always @(posedge clk)
  begin
    d = dNxt;
  end
  wire ser_clk = ~d[28]; // this is the 115200 Hz clock

  always @(posedge clk)
  begin
    if (sys_rst_i) begin
      uart_tx <= 1;
      bitcount <= 0;
      shifter <= 0;
    end else begin
      // just got a new byte
      if (uart_wr_i & ~uart_busy) begin
        shifter <= { uart_dat_i[7:0], 1'h0 };
        bitcount <= (1 + 8 + 2);
      end

      if (sending & ser_clk) begin
        { shifter, uart_tx } <= { 1'h1, shifter };
        bitcount <= bitcount - 1;
      end
    end
  end

endmodule
*/