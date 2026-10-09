`timescale 1ns / 1ps

module dehaze_tb;


    parameter HEIGHT = 576;                  
    parameter WIDTH = 768;                   
    parameter TOTAL_PIXELS = HEIGHT * WIDTH; 
    parameter CLOCK_PERIOD  = 5;             
    parameter SIMULATION_TIMEOUT = 500000000;

 
    reg clk;                                
    reg reset;                               
    reg [7:0] pixel_R_in;                    
    reg [7:0] pixel_G_in;                    
    reg [7:0] pixel_B_in;                    
    reg pixel_valid;                         
    reg pass_start;                          
    wire [7:0] pixel_R_out;                  
    wire [7:0] pixel_G_out;                 
    wire [7:0] pixel_B_out;                  
    wire [3:0] pixel_out_valid;                   
    wire busy;                               


    dehaze dut (
        .clk(clk),
        .reset(reset),
        .pixel_R_in(pixel_R_in),
        .pixel_G_in(pixel_G_in),
        .pixel_B_in(pixel_B_in),
        .pixel_valid(pixel_valid),
        .pass_start(pass_start),
        .pixel_R_out(pixel_R_out),
        .pixel_G_out(pixel_G_out),
        .pixel_B_out(pixel_B_out),
        .pixel_out_valid(pixel_out_valid),
        .busy(busy)
    );

  
    initial begin
           clk = 0;
           forever #(CLOCK_PERIOD) clk = ~clk; 
       end

    initial begin
        reset = 1;
        #(CLOCK_PERIOD*5) reset = 0;         
    end

    reg [7:0] R [0:TOTAL_PIXELS-1];
    reg [7:0] G [0:TOTAL_PIXELS-1];
    reg [7:0] B [0:TOTAL_PIXELS-1];
    reg [7:0] R_out [0:TOTAL_PIXELS-1];
    reg [7:0] G_out [0:TOTAL_PIXELS-1];
    reg [7:0] B_out [0:TOTAL_PIXELS-1];

 
    integer in_file, out_file, i;
    integer pixel_count_in;
    integer output_count;
    integer timeout_counter;
    reg simulation_done;

 
    initial  begin
  
        pixel_count_in = 0;
        output_count = 0;
        timeout_counter = 0;
        simulation_done = 0;
        pixel_valid = 1;

        
        in_file = $fopen("S:\cabin.txt", "r");
        if (in_file == 0) begin
            $display("WARNING: Input file \'image_data.txt\' not found. Using synthetic data instead.");
           
            for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
                
                R[i] = (i * 255) / TOTAL_PIXELS;
                G[i] = (i * 255) / TOTAL_PIXELS;
                B[i] = (i * 255) / TOTAL_PIXELS;
            end
            $display("Synthetic test image generated successfully");
        end else begin
      
            for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
                if ($fscanf(in_file, "%d %d %d", R[i], G[i], B[i]) != 3) begin
                    $display("ERROR: Failed to read pixel data at index %0d", i);
                    R[i] = 128; G[i] = 128; B[i] = 128; // Default to gray
                end
            end
            $fclose(in_file);
            $display("Input image loaded successfully");
        end


        $display("Writing output image...");
        
        out_file = $fopen("S:/output_cabinimage.txt", "w");
        if (out_file == 0) begin
            $display("ERROR: Could not open output file.");
            $finish;
        end
        $display("Output file ready for writing");
    end


    always @(posedge clk) begin
        if (pixel_out_valid ) begin
           
            R_out[output_count] = pixel_R_out;
            G_out[output_count] = pixel_G_out;
            B_out[output_count] = pixel_B_out;
          
            $fwrite(out_file, "%d %d %d\n", pixel_R_out, pixel_G_out, pixel_B_out);
            
            output_count = output_count + 1;
         
            if (output_count % 100000 == 0) begin
                $display("Processed %0d output pixels", output_count);
            end
        end
    end

    initial begin
        
        pixel_valid = 1;
        pass_start = 0;
        pixel_R_in = 0;
        pixel_G_in = 0;
        pixel_B_in = 0;

        
        wait (!reset);
        #(CLOCK_PERIOD);

        $display("Starting first pass (Downsampling and Parameter Computation)");
        pass_start = 0; // First pass
        
        for (pixel_count_in = 0; pixel_count_in < TOTAL_PIXELS; pixel_count_in = pixel_count_in + 1) begin
            @(posedge clk);
            pixel_R_in = R[pixel_count_in];
            pixel_G_in = G[pixel_count_in];
            pixel_B_in = B[pixel_count_in];
            pixel_valid = 1;
            
        end
        
        
        @(posedge clk);
        pixel_valid = 0;
        
        // Wait for the module to finish processing
        $display("Waiting for first pass to complete...");
        wait (!busy);
        #(CLOCK_PERIOD*100); 
        

        $display("Starting second pass (Dehazing Process)");
        pass_start = 1; 
        
        for (pixel_count_in = 0; pixel_count_in < TOTAL_PIXELS; pixel_count_in = pixel_count_in + 1) begin
            @(posedge clk);
            pixel_R_in = R[pixel_count_in];
            pixel_G_in = G[pixel_count_in];
            pixel_B_in = B[pixel_count_in];
            pixel_valid = 1;
           
        end
        
   
        @(posedge clk);
        pixel_valid = 0;
        
        // Wait for the module to finish processing
        $display("Waiting for second pass to complete...");
        wait (!busy);
        #(CLOCK_PERIOD*100); 
        
    
        if (output_count != TOTAL_PIXELS) begin
            $display("ERROR: Not enough data: expected %0d pixels, but got %0d.", TOTAL_PIXELS, output_count);
        end

        $fclose(out_file);
        $display("Simulation completed successfully. Output file closed.");
        simulation_done = 1;
        $finish;
    end


    initial begin
        timeout_counter = 0;
        while (!simulation_done && timeout_counter < SIMULATION_TIMEOUT) begin
            @(posedge clk);
            timeout_counter = timeout_counter + 1;
        end
        
        if (!simulation_done) begin
            $display("ERROR: Simulation timeout after %0d clock cycles", timeout_counter);
            $fclose(out_file);
            $finish;
        end
    end


    always @(dut.state) begin
        case (dut.state)
            0: $display("Time %t: State transition to S_IDLE", $time);
            1: $display("Time %t: State transition to S_DOWNSAMPLE", $time);
            2: $display("Time %t: State transition to S_DARK_CHANNEL", $time);
            3: $display("Time %t: State transition to S_DARK_CHANNEL_INIT", $time);
            4: $display("Time %t: State transition to S_DARK_CHANNEL_PROCESS", $time);
            5: $display("Time %t: State transition to S_ATMOSPHERIC_LIGHT", $time);
            6: $display("Time %t: State transition to S_TRANSMISSION", $time);
            7: $display("Time %t: State transition to S_PROCESSING", $time);
            default: $display("Time %t: State transition to UNKNOWN (%0d)", $time, dut.state);
        endcase
    end
    initial begin
        $dumpfile("dehaze_tb.vcd");
        $dumpvars(0, dehaze_tb);
    end

endmodule
