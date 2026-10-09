`timescale 1ns / 1ps
module dehaze;

    parameter HEIGHT = 1024;
    parameter WIDTH = 768;
    parameter TOTAL_PIXELS = HEIGHT * WIDTH;
    parameter DS_FACTOR = 2;
    parameter DS_HEIGHT = HEIGHT / DS_FACTOR;
    parameter DS_WIDTH = WIDTH / DS_FACTOR;
    parameter DS_TOTAL_PIXELS = DS_HEIGHT * DS_WIDTH;
    parameter PATCH_SIZE = 5;  
    parameter PATCH_RADIUS = (PATCH_SIZE-1)/2;

    integer in_file, out_file, i, j, m, n;
    integer row, col, ds_row, ds_col, patch_row, patch_col;
    
    reg [7:0] R [0:TOTAL_PIXELS-1];
    reg [7:0] G [0:TOTAL_PIXELS-1];
    reg [7:0] B [0:TOTAL_PIXELS-1];
    reg [7:0] DS_R [0:DS_TOTAL_PIXELS-1];
    reg [7:0] DS_G [0:DS_TOTAL_PIXELS-1];
    reg [7:0] DS_B [0:DS_TOTAL_PIXELS-1];
    reg [7:0] dark_channel [0:DS_TOTAL_PIXELS-1];
    reg [7:0] gamma_R [0:TOTAL_PIXELS-1];
    reg [7:0] gamma_G [0:TOTAL_PIXELS-1];
    reg [7:0] gamma_B [0:TOTAL_PIXELS-1];
    
    real norm_R [0:DS_TOTAL_PIXELS-1];
    real norm_G [0:DS_TOTAL_PIXELS-1];
    real norm_B [0:DS_TOTAL_PIXELS-1];
    real transmission [0:DS_TOTAL_PIXELS-1];
    real transmission_full [0:TOTAL_PIXELS-1];
    real A_R = 0, A_G = 0, A_B = 0;
    real psi = 1;   
    real t0 = 0.1;       
    real gamma_val = 0.7; 
    real dx, dy, w00, w01, w10, w11;
    real t00, t01, t10, t11;
    
    
    integer r_temp, g_temp, b_temp;
    real t, r_f, g_f, b_f;
    real min_norm, min_pixel, min_channel;
    integer pixel_index, ds_pixel_index;
    integer sum_r, sum_g, sum_b, avg_count;
    integer top_bright_pixels [0:99]; 
    integer brightness, max_brightness, bright_idx;
    integer min_brightness , min_idx ;

    function automatic real clamp;
        input real val;
        input real min_val;
        input real max_val;
        begin
            if (val < min_val) clamp = min_val;
            else if (val > max_val) clamp = max_val;
            else clamp = val;
        end
    endfunction
    
    function automatic integer to1D;
        input integer r, c, w;
        begin
            to1D = r * w + c;
        end
    endfunction
    
    initial begin
        $display("=== Starting Enhanced Dehazing Simulation ===");
        $display("Image size: %d x %d", WIDTH, HEIGHT);
        $display("Downsampling factor: %d (resulting size: %d x %d)", DS_FACTOR, DS_WIDTH, DS_HEIGHT);
        $display("Dark channel patch size: %d x %d", PATCH_SIZE, PATCH_SIZE);
        
        in_file = $fopen("S:\Tower.txt", "r");
        if (in_file == 0) begin
            $display("ERROR: Could not open input file.");
            $finish;
        end

        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            if ($fscanf(in_file, "%d %d %d", r_temp, g_temp, b_temp) == 3) begin
                R[i] = r_temp;
                G[i] = g_temp;
                B[i] = b_temp;
            end else begin
                $display("ERROR: Not enough pixel data at index %d", i);
                $finish;
            end
        end
        $fclose(in_file);
        $display("Successfully loaded %d pixels", TOTAL_PIXELS);
        
        $display("Performing downsampling...");
        for (i = 0; i < DS_HEIGHT; i = i + 1) begin
            for (j = 0; j < DS_WIDTH; j = j + 1) begin
                ds_pixel_index = to1D(i, j, DS_WIDTH);
                
                // Average of DS_FACTOR x DS_FACTOR pixels
                sum_r = 0;
                sum_g = 0;
                sum_b = 0;
                avg_count = 0;
                
                for (m = 0; m < DS_FACTOR; m = m + 1) begin
                    for (n = 0; n < DS_FACTOR; n = n + 1) begin
                        row = i * DS_FACTOR + m;
                        col = j * DS_FACTOR + n;
                        
                        if (row < HEIGHT && col < WIDTH) begin
                            pixel_index = to1D(row, col, WIDTH);
                            sum_r = sum_r + R[pixel_index];
                            sum_g = sum_g + G[pixel_index];
                            sum_b = sum_b + B[pixel_index];
                            avg_count = avg_count + 1;
                        end
                    end
                end
                
                DS_R[ds_pixel_index] = (avg_count > 0) ? (sum_r / avg_count) : 0;
                DS_G[ds_pixel_index] = (avg_count > 0) ? (sum_g / avg_count) : 0;
                DS_B[ds_pixel_index] = (avg_count > 0) ? (sum_b / avg_count) : 0;
            end
        end
        
        $display("Computing dark channel prior...");
        for (i = 0; i < DS_HEIGHT; i = i + 1) begin
            for (j = 0; j < DS_WIDTH; j = j + 1) begin
                ds_pixel_index = to1D(i, j, DS_WIDTH);
                min_channel = 255;
               
                for (m = -PATCH_RADIUS; m <= PATCH_RADIUS; m = m + 1) begin
                    for (n = -PATCH_RADIUS; n <= PATCH_RADIUS; n = n + 1) begin
                        patch_row = i + m;
                        patch_col = j + n;
                        
                        if (patch_row >= 0 && patch_row < DS_HEIGHT && 
                            patch_col >= 0 && patch_col < DS_WIDTH) begin
                            pixel_index = to1D(patch_row, patch_col, DS_WIDTH);
                            

                            min_pixel = DS_R[pixel_index];
                            if (DS_G[pixel_index] < min_pixel) min_pixel = DS_G[pixel_index];
                            if (DS_B[pixel_index] < min_pixel) min_pixel = DS_B[pixel_index];
                            
                            if (min_pixel < min_channel) min_channel = min_pixel;
                        end
                    end
                end
                
                dark_channel[ds_pixel_index] = min_channel;
            end
        end
        

        $display("Estimating atmospheric light...");
        
        for (i = 0; i < 100; i = i + 1) begin
            top_bright_pixels[i] = i;
        end
        

        for (i = 100; i < DS_TOTAL_PIXELS; i = i + 1) begin
            min_brightness = dark_channel[top_bright_pixels[0]];
            min_idx = 0;
            
            // Find minimum brightness in current top list
            for (j = 1; j < 100; j = j + 1) begin
                if (dark_channel[top_bright_pixels[j]] < min_brightness) begin
                    min_brightness = dark_channel[top_bright_pixels[j]];
                    min_idx = j;
                end
            end
            

            if (dark_channel[i] > min_brightness) begin
                top_bright_pixels[min_idx] = i;
            end
        end

        max_brightness = 0;
        bright_idx = 0;
        
        for (i = 0; i < 100; i = i + 1) begin
            pixel_index = top_bright_pixels[i];
            brightness = DS_R[pixel_index] + DS_G[pixel_index] + DS_B[pixel_index];
            
            if (brightness > max_brightness) begin
                max_brightness = brightness;
                bright_idx = pixel_index;
            end
        end
        
        // Set atmospheric light as the brightest pixel
        A_R = DS_R[bright_idx] / 255.0;
        A_G = DS_G[bright_idx] / 255.0;
        A_B = DS_B[bright_idx] / 255.0;
        
        $display("Atmospheric light: R=%.3f, G=%.3f, B=%.3f", A_R, A_G, A_B);
        
        $display("Computing transmission map...");
        for (i = 0; i < DS_TOTAL_PIXELS; i = i + 1) begin
     
            norm_R[i] = (DS_R[i] / 255.0) / ((A_R > 0) ? A_R : 0.001);
            norm_G[i] = (DS_G[i] / 255.0) / ((A_G > 0) ? A_G : 0.001);
            norm_B[i] = (DS_B[i] / 255.0) / ((A_B > 0) ? A_B : 0.001);
            
  
            min_norm = norm_R[i];
            if (norm_G[i] < min_norm) min_norm = norm_G[i];
            if (norm_B[i] < min_norm) min_norm = norm_B[i];
            
            // Calculate transmission based on dark channel prior
            transmission[i] = 1.0 - psi * (dark_channel[i] / 255.0);
            
            // Ensure minimum transmission
            if (transmission[i] < t0) transmission[i] = t0;
        end
        
        $display("Upsampling transmission map...");
        for (i = 0; i < HEIGHT; i = i + 1) begin
            for (j = 0; j < WIDTH; j = j + 1) begin
                ds_row = i / DS_FACTOR;
                ds_col = j / DS_FACTOR;
                
                if (ds_row >= DS_HEIGHT-1 || ds_col >= DS_WIDTH-1) begin
                    // Edge case - use nearest neighbor
                    ds_row = (ds_row >= DS_HEIGHT) ? DS_HEIGHT-1 : ds_row;
                    ds_col = (ds_col >= DS_WIDTH) ? DS_WIDTH-1 : ds_col;
                    ds_pixel_index = to1D(ds_row, ds_col, DS_WIDTH);
                    transmission_full[to1D(i, j, WIDTH)] = transmission[ds_pixel_index];
                end else 
                 

                    dx = (j % DS_FACTOR) * 1.0 / DS_FACTOR;
                    dy = (i % DS_FACTOR) * 1.0 / DS_FACTOR;
                    
                    w00 = (1-dx) * (1-dy);
                    w01 = dx * (1-dy);
                    w10 = (1-dx) * dy;
                    w11 = dx * dy;
                    
                    t00 = transmission[to1D(ds_row, ds_col, DS_WIDTH)];
                    t01 = transmission[to1D(ds_row, ds_col+1, DS_WIDTH)];
                    t10 = transmission[to1D(ds_row+1, ds_col, DS_WIDTH)];
                    t11 = transmission[to1D(ds_row+1, ds_col+1, DS_WIDTH)];
                    
                    transmission_full[to1D(i, j, WIDTH)] = w00*t00 + w01*t01 + w10*t10 + w11*t11;
              
            end
        end

        $display("Recovering scene radiance...");
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            t = transmission_full[i];
            
            // Scene recovery equation: J = (I - A)/t + A
            r_f = ((R[i] / 255.0 - A_R) / t) + A_R;
            g_f = ((G[i] / 255.0 - A_G) / t) + A_G;
            b_f = ((B[i] / 255.0 - A_B) / t) + A_B;
            
            r_f = clamp(r_f, 0.0, 1.0);
            g_f = clamp(g_f, 0.0, 1.0);
            b_f = clamp(b_f, 0.0, 1.0);
            
            r_f = $pow(r_f, gamma_val);
            g_f = $pow(g_f, gamma_val);
            b_f = $pow(b_f, gamma_val);
            
          
            gamma_R[i] = r_f * 255.0;
            gamma_G[i] = g_f * 255.0;
            gamma_B[i] = b_f * 255.0;
        end
        
        $display("Writing output image...");
        out_file = $fopen("S:\Tower_output123.txt", "w");
        if (out_file == 0) begin
            $display("ERROR: Could not open output file.");
            $finish;
        end
        
        for (i = 0; i < TOTAL_PIXELS; i = i + 1) begin
            $fwrite(out_file, "%d %d %d\n", gamma_R[i], gamma_G[i], gamma_B[i]);
        end
        
        $fclose(out_file);
        $display("=== Dehazing Complete. Output written to 'enhanced_output.txt' ===");
        $finish;
    end

endmodule
