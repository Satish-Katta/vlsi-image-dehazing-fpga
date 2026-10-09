`timescale 1ns / 1ps


module dehaze (
    input wire clk,                      
    input wire reset,                   
    input wire [7:0] pixel_R_in,         
    input wire [7:0] pixel_G_in,         
    input wire [7:0] pixel_B_in,         
    input wire pixel_valid,              
    input wire pass_start,               
    output reg [7:0] pixel_R_out,        
    output reg [7:0] pixel_G_out,        
    output reg [7:0] pixel_B_out,        
    output reg pixel_out_valid,          
    output reg busy                      
);

parameter HEIGHT = 256;                  
parameter WIDTH = 256;                   
parameter TOTAL_PIXELS = HEIGHT * WIDTH; 
parameter DS_FACTOR = 4;                 
parameter DS_HEIGHT = HEIGHT / DS_FACTOR;
parameter DS_WIDTH = WIDTH / DS_FACTOR;  
parameter DS_TOTAL_PIXELS = DS_HEIGHT * DS_WIDTH; 
parameter PATCH_SIZE = 5;                
parameter PATCH_RADIUS = (PATCH_SIZE - 1) / 2; 
parameter FP_WIDTH = 16;                 
parameter FP_FRAC = 8;                   
parameter FP_ONE = 1 << FP_FRAC;        
parameter PSI = 256;                     
parameter T0 = 26;                       
parameter INV_255 = FP_ONE / 255;        

localparam [3:0]
    S_IDLE = 0,                          
    S_DOWNSAMPLE = 1,                    
    S_DARK_CHANNEL = 2,                  
    S_DARK_CHANNEL_INIT = 3,             
    S_DARK_CHANNEL_PROCESS = 4,          
    S_ATMOSPHERIC_LIGHT = 5,             
    S_TRANSMISSION = 6,                  
    S_PROCESSING = 7;                  

reg [3:0] state;                         
reg [9:0] row, col;                      
reg [7:0] ds_row, ds_col;               
reg [19:0] pixel_count;                  
reg [7:0] DS_R [0:DS_TOTAL_PIXELS-1];    
reg [7:0] DS_G [0:DS_TOTAL_PIXELS-1];    
reg [7:0] DS_B [0:DS_TOTAL_PIXELS-1];    
reg [7:0] dark_channel [0:DS_TOTAL_PIXELS-1];
reg [FP_WIDTH-1:0] transmission [0:DS_TOTAL_PIXELS-1]; 
reg [FP_WIDTH-1:0] A_R, A_G, A_B;        
reg [11:0] sum_r, sum_g, sum_b;         
reg [3:0] ds_count;                      
reg [7:0] min_pixel;                     
reg [7:0] min_channel;                   
reg [1:0] patch_row, patch_col;          
reg [7:0] patch_row_abs, patch_col_abs;  
reg [FP_WIDTH-1:0] r_f, g_f, b_f;      
reg [FP_WIDTH-1:0] t;                   
reg [FP_WIDTH-1:0] temp_calc;            
reg [15:0] ds_pixel_idx;                  
reg [7:0] max_dark;                      
reg [15:0] max_dark_idx;                 
reg dark_channel_done;                   
reg [7:0] temp_R, temp_G, temp_B;        
reg [7:0] curr_dark;                    
reg [FP_WIDTH-1:0] temp_trans;           
reg [7:0] curr_ds_row, curr_ds_col;      
reg [7:0] gamma_lut [0:255];
integer i;
initial begin
    for (i = 0; i < 256; i = i + 1) begin
        gamma_lut[i] = i;
    end
end

wire [15:0] ds_idx = ds_row * DS_WIDTH + ds_col;
wire [7:0] current_ds_row = row / DS_FACTOR;
wire [7:0] current_ds_col = col / DS_FACTOR;
wire [15:0] current_ds_idx = current_ds_row * DS_WIDTH + current_ds_col;

always @(posedge clk) begin
    if (reset) begin
        state <= S_IDLE;
        row <= 0;
        col <= 0;
        pixel_count <= 0;
        busy <= 0;
        pixel_out_valid <= 0;
        sum_r <= 0;
        sum_g <= 0;
        sum_b <= 0;
        ds_count <= 0;
        ds_row <= 0;
        ds_col <= 0;
        patch_row <= 0;
        patch_col <= 0;
        min_channel <= 0;
        dark_channel_done <= 0;
        max_dark <= 0;
        max_dark_idx <= 0;

        A_R <= 128 << FP_FRAC;
        A_G <= 128 << FP_FRAC;
        A_B <= 128 << FP_FRAC;
    end else begin
        case (state)
            S_IDLE: begin

                pixel_out_valid <= 0;
                
                if (pixel_valid) begin
                    if (pass_start ==  1) begin

                        state <= S_DOWNSAMPLE;
                        busy <= 1;
                        row <= 0;
                        col <= 0;
                        pixel_count <= 0;
                        sum_r <= 0;
                        sum_g <= 0;
                        sum_b <= 0;
                        ds_count <= 0;
                    end else begin
                        state <= S_PROCESSING;
                        busy <= 1;
                        row <= 0;
                        col <= 0;
                        pixel_count <= 0;
                    end
                end
            end
            
            S_DOWNSAMPLE: begin
                if (pixel_valid) begin
                    sum_r <= sum_r + pixel_R_in;
                    sum_g <= sum_g + pixel_G_in;
                    sum_b <= sum_b + pixel_B_in;
                    ds_count <= ds_count + 1;
                    
                    if (ds_count == DS_FACTOR*DS_FACTOR - 1) begin
                        DS_R[(row/DS_FACTOR) * DS_WIDTH + (col/DS_FACTOR)] <= (sum_r + pixel_R_in) / (DS_FACTOR*DS_FACTOR);
                        DS_G[(row/DS_FACTOR) * DS_WIDTH + (col/DS_FACTOR)] <= (sum_g + pixel_G_in) / (DS_FACTOR*DS_FACTOR);
                        DS_B[(row/DS_FACTOR) * DS_WIDTH + (col/DS_FACTOR)] <= (sum_b + pixel_B_in) / (DS_FACTOR*DS_FACTOR);

                        sum_r <= 0;
                        sum_g <= 0;
                        sum_b <= 0;
                        ds_count <= 0;
                    end

                    col <= col + 1;
                    if (col == WIDTH - 1) begin
                        col <= 0;
                        row <= row + 1;
                    end
                    pixel_count <= pixel_count + 1;
        
                    if (pixel_count == TOTAL_PIXELS - 1) begin
                        state <= S_DARK_CHANNEL_INIT;
                        ds_row <= 0;
                        ds_col <= 0;
                    end
                end
            end
            
            S_DARK_CHANNEL_INIT: begin
                min_channel <= 0;
                patch_row <= 0;
                patch_col <= 0;
                state <= S_DARK_CHANNEL_PROCESS;
            end
            
            S_DARK_CHANNEL_PROCESS: begin
        
                patch_row_abs = ds_row + patch_row - PATCH_RADIUS;
                patch_col_abs = ds_col + patch_col - PATCH_RADIUS;
                

                if (patch_row_abs < DS_HEIGHT && patch_col_abs < DS_WIDTH && 
                    patch_row_abs >= 0 && patch_col_abs >= 0) begin
                    
                    ds_pixel_idx = patch_row_abs * DS_WIDTH + patch_col_abs;
                    
 
                    temp_R = DS_R[ds_pixel_idx];
                    temp_G = DS_G[ds_pixel_idx];
                    temp_B = DS_B[ds_pixel_idx];
                    
               
                    if (temp_R <= temp_G && temp_R <= temp_B)
                        min_pixel = temp_R;
                    else if (temp_G <= temp_R && temp_G <= temp_B)
                        min_pixel = temp_G;
                    else
                        min_pixel = temp_B;
                    

                    if (min_pixel < min_channel)
                        min_channel = min_pixel;
                end
                
             
                patch_col <= patch_col + 1;
                if (patch_col == PATCH_SIZE - 1) begin
                    patch_col <= 0;
                    patch_row <= patch_row + 1;
                    if (patch_row == PATCH_SIZE - 1) begin
                       dark_channel[ds_row * DS_WIDTH + ds_col] <= min_channel;
                 
                        ds_col <= ds_col + 1;
                        if (ds_col == DS_WIDTH - 1) begin
                            ds_col <= 0;
                            ds_row <= ds_row + 1;
                            if (ds_row == DS_HEIGHT - 1) begin
                                state <= S_ATMOSPHERIC_LIGHT;
                                ds_row <= 0;
                                ds_col <= 0;
                                max_dark <= 0;
                                max_dark_idx <= 0;
                            end else begin
                                state <= S_DARK_CHANNEL_INIT;
                            end
                        end else begin
                            state <= S_DARK_CHANNEL_INIT;
                        end
                    end
                end
            end
            
            S_ATMOSPHERIC_LIGHT: begin
                curr_dark = dark_channel[ds_row * DS_WIDTH + ds_col];
                if (curr_dark > max_dark) begin
                    max_dark <= curr_dark;
                    max_dark_idx <= ds_row * DS_WIDTH + ds_col;
                    A_R <= DS_R[ds_row * DS_WIDTH + ds_col] << FP_FRAC;
                    A_G <= DS_G[ds_row * DS_WIDTH + ds_col] << FP_FRAC;
                    A_B <= DS_B[ds_row * DS_WIDTH + ds_col] << FP_FRAC;
                end
             
                ds_col <= ds_col + 1;
                if (ds_col == DS_WIDTH - 1) begin
                    ds_col <= 0;
                    ds_row <= ds_row + 1;
                    if (ds_row == DS_HEIGHT - 1) begin
                       
                        state <= S_TRANSMISSION;
                        ds_row <= 0;
                        ds_col <= 0;
                    end
                end
            end
            
            S_TRANSMISSION: begin
               
                curr_dark = dark_channel[ds_row * DS_WIDTH + ds_col];
                
     
                temp_calc = (PSI * curr_dark * INV_255) >> FP_FRAC;
                temp_trans = FP_ONE - temp_calc;
                

                if (temp_trans < T0)
                    temp_trans = T0;
                

                transmission[ds_row * DS_WIDTH + ds_col] <= temp_trans;
                

                ds_col <= ds_col + 1;
                if (ds_col == DS_WIDTH - 1) begin
                    ds_col <= 0;
                    ds_row <= ds_row + 1;
                    if (ds_row == DS_HEIGHT - 1) begin
       
                        state <= S_IDLE;
                        busy <= 0;
                    end
                end
            end
            
            S_PROCESSING: begin
                if (pixel_valid) begin
                
                    curr_ds_row = row / DS_FACTOR;
                    curr_ds_col = col / DS_FACTOR;
                    
                    t = transmission[curr_ds_row * DS_WIDTH + curr_ds_col];
                    
                                        
                    r_f = (pixel_R_in << FP_FRAC) - A_R;
                    g_f = (pixel_G_in << FP_FRAC) - A_G;
                    b_f = (pixel_B_in << FP_FRAC) - A_B;
                    
                    
                    if (r_f != 0) begin
                        if (t >= 1) begin
                            r_f = ((r_f << FP_FRAC) / t);
                        end else begin
                            r_f = r_f << 1; 
                        end
                    end
                    if (g_f != 0) begin
                        if (t >= 1) begin
                            g_f = ((g_f << FP_FRAC) / t);
                        end else begin
                            g_f = g_f << 1;
                        end
                    end
                    if (b_f != 0) begin
                        if (t >= 1) begin
                            b_f = ((b_f << FP_FRAC) / t);
                        end else begin
                            b_f = b_f << 1;
                        end
                    end

                    r_f = r_f + A_R;
                    g_f = g_f + A_G;
                    b_f = b_f + A_B;

    
                    pixel_R_out <= (r_f >> FP_FRAC) > 255 ? 255 : (r_f >> FP_FRAC);
                    pixel_G_out <= (g_f >> FP_FRAC) > 255 ? 255 : (g_f >> FP_FRAC);
                    pixel_B_out <= (b_f >> FP_FRAC) > 255 ? 255 : (b_f >> FP_FRAC);
                    pixel_out_valid <= 1; // Assert output valid

                   
                    col <= col + 1;
                    if (col == WIDTH - 1) begin
                        col <= 0;
                        row <= row + 1;
                    end

                    pixel_count <= pixel_count + 1;
                    if (pixel_count == TOTAL_PIXELS - 1) begin
                        state <= S_IDLE;
                        busy <= 0;
                    end
                end else begin
                    pixel_out_valid <= 0; 
                end
            end
        endcase
    end
end

endmodule