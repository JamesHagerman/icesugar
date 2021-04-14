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
//  sourceClock - The source clock input
//  sourceFreqHz - The expected frequency of the source clock
//  dividedFreqHz - Desired frqeuency of the divided clock
//  dividedClock - The divided, lower frequency output
module adjustableClock ( input sourceClock, input [24:0] sourceFreqHz, input [24:0] dividedFreqHz, output dividedClock );
  reg [24:0] d;
  wire [24:0] dInc = d[24] ? (dividedFreqHz) : (dividedFreqHz - sourceFreqHz);
  wire [24:0] dN = d + dInc;
  always @(posedge sourceClock)
  begin
    d = dN;
  end
  assign dividedClock = ~d[24];  // clock tick whenever d[24] is zero
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
  // integer squareWave; // `integer` is signed, but unsized. We need a 16 bit 2s complement signed value for samples.
  reg signed [15:0] squareWave;
  reg signed [15:0] squareWaveRight;
  // assign squareWave = 13; // Test value to help with MSB in the logic analyzer output: 0b1101 = 13
  // assign squareWave = -2; // Test value

  // We want a 440Hz square wave. System `clk` is 6MHz.
  wire audioRatePulses;
  adjustableClock audioRateClock(clk, 6000000, 60, audioRatePulses);

    // We want a 440Hz square wave. System `clk` is 6MHz.
  wire audioRatePulsesRight;
  adjustableClock audioRateClockRight(clk, 6000000, 61, audioRatePulsesRight);

  // Generate a simple square wave from the audio clock:
  reg sqaureWaveState;
  initial begin
    sqaureWaveState = 0;
  end
  always @(posedge audioRatePulses)
  begin
    sqaureWaveState = !sqaureWaveState;
    // TODO: Someday, actually manage volume of these samples:
    // squareWave = sqaureWaveState ? 13 : -2;
    squareWave = sqaureWaveState ? 5000 : -5000;
  end


  // Generate a simple square wave from the audio clock:
  reg sqaureWaveStateRight;
  initial begin
    sqaureWaveStateRight = 0;
  end
  always @(posedge audioRatePulsesRight)
  begin
    sqaureWaveStateRight = !sqaureWaveStateRight;
    squareWaveRight = sqaureWaveStateRight ? 5000 : -5000;
  end

  // assign P1_9 = sqaureWaveState; // debug output


  // Once we have some clocks set up, we will sample the audio waveform into these buffers, at the sample rate (44.1kHz).
  // This will avoid glitches caused by changing the value of a sample right in the middle of pushing samples to I2S.
  reg signed [15:0] leftAudioBuffer;
  reg signed [15:0] rightAudioBuffer; // TODO: Make our i2sOutput module handle stereo audio data












  // Main audio clock generation - BCK and Primary Sampling clock
  //
  // We would like to use the same clock for generating waveform samples and for I2S audio output. The sample rate clock will be
  // slower than the bit clock, so we should start with the bit clock and go from there.
  
  // Bit clock:
  // Picking a useful BCK has some considerations. Tl;dr: It's frequency should be at least `Sample Rate * Bit Depth * Channels`:
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
  wire bitClockPulses;
  adjustableClock bitClockTimer(clk, 6000000, 1411200, bitClockPulses);
  // adjustableClock bitClockTimer(clk, 6000000, 2000000, bitClockPulses); // Speed up bit clock to fix alignment issues

  // Convert bitClockPulses into a correctly toggling BCK clock signal
  reg bitClock;
  initial begin
    bitClock = 0;
  end
  always @(posedge bitClockPulses)
  begin
    bitClock <= !bitClock;
  end

  // Primary Sampling clock:
  // 
  // Derive the sample clock from the BCK to keep them aligned and attempt to reduce jitter:
  // Note: Because pulses need to be converted to 50/50 duty cycle for I2S LCK to be valid, we need to double
  // the sample rate here so we can then divide it cleanly into 44100 Hz 
  wire sampleClockPulses;
  adjustableClock sampleClockTimer(bitClock, 1411200, 88200, sampleClockPulses);
  // adjustableClock sampleClockTimer(bitClock, 2000000, 88200, sampleClockPulses);  // Speed up bit clock to fix alignment issues

  // Convert sampleClockPulses into a correctly toggling sample rate clock signal
  reg sampleClock;
  initial begin
    sampleClock = 0;
  end
  always @(posedge sampleClockPulses)
  begin
    sampleClock <= !sampleClock;
  end

  // Now that we have clocks, we can sample the audio waveform into the left and right audio buffers!:
  always @(posedge sampleClock)
  begin
    leftAudioBuffer = squareWave;
    rightAudioBuffer = squareWaveRight;
  end

  // Send sampled square wave audio values to i2sOutput module instance:
  i2sOutput audio(bitClock, sampleClock, leftAudioBuffer, rightAudioBuffer, P1_4, P1_3, P1_2, pmod_led_pins);

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
  input bitClock, // Primary bit clock input; used for logic and output to BCK I2S pin
  input sampleClock, // primary sample rate clock; used for logic and output to LCK I2S pin

  // Sampled audio data as signed, 2s complement, MSB-first values
  input [15:0] leftAudioData,
  input [15:0] rightAudioData,

  output P1_4, output P1_3, output P1_2, // I2S output pins; LCK, DIN, BCK respectively
  output [7:0] debugLEDs // A register where we can drop some debugging output from the I2S module
);

  reg [7:0] currentBit; // Index for the next bit in the current sample
  initial begin
    currentBit = 12'hff;
  end

  reg [7:0] frameCounter; // Current frame number (max of 255 for maybe bitbyte?)
  initial begin
    frameCounter = 0;
  end

  // Bind something to the debug leds:
  assign debugLEDs = ~leftAudioData; 
  // assign debugLEDs = ~currentBit; 

  // The bitClock rises 16 times every frame (assuming 16 bits per sample)
  always @(posedge bitClock)
  begin
    currentBit <= currentBit + 1; // Increment the bit selection index 
  end

  // Output a bit for the current sample to DIN:
  // Because we need the data as MSB first, we subtract the current bit index from one less than the Bit Rate (15 in this case)
  assign P1_3 = currentChannel == 0 ? leftAudioData[15-currentBit] : rightAudioData[15-currentBit]; // DIN

  // Output bit clock to the correct PMOD1 pin for BCK:
  assign P1_2 = ~bitClock;

  // Output sampleClock to the correct PMOD1 pin for LCK:
  assign P1_4 = ~sampleClock;

  // When LCK is low, I2S is expecting the sample data for the left channel. High means right channel.
  // Therefore, a rising edge means we should start outputting the bits for the right channel...
  reg currentChannel;
  always @(sampleClock)
  begin
    currentChannel = sampleClock; // 0 is Left, 1 is Right
  end
  
  // ... And a falling edge represents the start of a new "frame" where we'll start outputting bits for the left channel
  always @(negedge sampleClock)
  begin
    frameCounter <= frameCounter + 1; // Keep track of the current frame (up to 255 frames)
  end


endmodule // i2sOutput






















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