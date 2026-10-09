clc; clear; close all;

txt_file = "C:verilog\templeout5.txt";
height = 333;
width = 495;
numPixels = height * width;  
fileID = fopen(txt_file, 'r');
if fileID == -1
    error('Could not open file: %s', txt_file);
end


data = fscanf(fileID, '%d', [3, numPixels]);
fclose(fileID);


pixelsRead = size(data, 2);
fprintf('Expected pixels: %d, Pixels read: %d\n', numPixels, pixelsRead);


if pixelsRead < numPixels
    error('Not enough data: expected %d pixels, but got %d', numPixels, pixelsRead);
end

data = data';
img_reconstructed = reshape(data, [width, height, 3]);
img_reconstructed = permute(img_reconstructed, [2, 1, 3]);
img_reconstructed = uint8(img_reconstructed);  

output_image_file = 'S:/rgboutput_image.png';
imwrite(img_reconstructed, output_image_file);
imshow(img_reconstructed);

disp('Image reconstructed and saved as reconstructed_image.png');
