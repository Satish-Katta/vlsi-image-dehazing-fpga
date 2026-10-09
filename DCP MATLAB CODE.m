
clear; clc; close all;
hazyimage = 'C:\Users\SATISH\Desktop\PPT\TEST-IMAGES\datasets';
cd(hazyimage)
[filename, pathname] = uigetfile('*.jpg');
hazyImage = imread([pathname, filename]);
figure, imshow(hazyImage);

dehazedImage = dehazeImage(hazyImage);

figure, imshow(dehazedImage);

function dehazed = dehazeImage(hazy)
    
    hazyDouble = im2double(hazy);
    
   
    hazyDS = imresize(hazyDouble, 0.1);
    
  
    A = estimateAtmosphericLight(hazyDS);
    
   
    normH = normalizeImage(hazyDouble, A);
    [saturation, ~] = estimateSaturation(normH);
    
   
    t = estimateTransmission(saturation, 1.2);
    
   
    dehazedFloat = restoreScene(hazyDouble, A, t);
    
   
    dehazed = finalOutput(dehazedFloat);
end

function A = estimateAtmosphericLight(I)
  
    darkChannel = min(I, [], 3);
    
  
    se = strel('square', 5);
    darkChannel = imerode(darkChannel, se);
    
   
    numPixels = numel(darkChannel);
    nPixels = max(floor(numPixels * 0.001), 1);
    
  
    [~, indices] = sort(darkChannel(:), 'descend');
    brightestIndices = indices(1:nPixels);
    
    
    pixels = reshape(I, [], 3);
    
   
    A = max(pixels(brightestIndices, :), [], 1);
end

function normH = normalizeImage(H, A)
    
    normH = zeros(size(H));
    for c = 1:3
        normH(:,:,c) = H(:,:,c) ./ (A(c) + eps);
    end
end

function [sat, satHazeFree] = estimateSaturation(I)
   
    maxVal = max(I, [], 3);
    minVal = min(I, [], 3);
    sat = (maxVal - minVal) ./ (maxVal + eps);
    
   
    satHazeFree = imadjust(sat);
end

function t = estimateTransmission(sat, psi)
    
    t = 1 - psi * sat;
    
  
    t = max(t, 0.1);
    t = min(t, 1);
end

function dehazed = restoreScene(H, A, t)
   
    lutX = linspace(0.1, 1, 1000);
    lutY = 1 ./ lutX;
    
   
    tInv = interp1(lutX, lutY, t, 'linear', 'extrap');
    
   
    dehazed = zeros(size(H));
    for c = 1:3
        dehazed(:,:,c) = (H(:,:,c) - A(c)) .* tInv + A(c);
    end
    
    
    dehazed = max(min(dehazed, 1), 0);
end

function finalImage = finalOutput(I)
    
    I12 = I * 4095;
    
   
    I8 = uint8((I12 / 4095) * 255);
    finalImage = I8;
end
