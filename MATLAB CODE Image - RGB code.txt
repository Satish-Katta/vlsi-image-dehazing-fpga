
image_path = 'S:\DATASET\dataset sots 3.jpg'; 

xsim_output_dir = 'S:\DATASET\';  

text_file_path = fullfile(xsim_output_dir, 'bridge.txt');  
img = imread(image_path);
[height, width, ~] = size(img);

total_pixels = height * width;


fid = fopen(text_file_path, 'w');
if fid == -1
    error('Failed to open the output file for writing.');
end
for i = 1:height
    for j = 1:width
        r = img(i,j,1);
        g = img(i,j,2);
        b = img(i,j,3);
        fprintf(fid, '%d %d %d\n', r, g, b);
    end
end

fclose(fid);

disp(['Image Dimensions: ' num2str(height) ' x ' num2str(width)]);
disp(['Total Pixels: ' num2str(total_pixels)]);
disp('Image saved to text file successfully in R G B format.');


imshow(img);