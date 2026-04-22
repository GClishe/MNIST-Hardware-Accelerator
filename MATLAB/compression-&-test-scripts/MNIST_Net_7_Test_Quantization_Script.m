%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Name: MNIST Net 7 Test Quantization Script    %
% Author: David Griessmann                      %
% Date: 4-08-26                                 %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear;close;clc;

parpool('Threads');
load('mnist.mat');

tic % Start counting ellapsed seconds
% Begin dithering the test set
tempTrainingImages = zeros(training.height, training.width, 1, training.count);
parfor i = 1:training.count
    tempTrainingImages(:, :, 1, i) = bayerDither(training.images(:, :, i), false);
end
trainingArray.images = tempTrainingImages;
trainingArray.labels = categorical(training.labels);

tempTestImages = zeros(test.height, test.width, 1, test.count);
parfor j = 1:test.count
   tempTestImages(:, :, 1, j) = bayerDither(test.images(:, :, j), false);
end
testArray.images = tempTestImages;
testArray.labels = categorical(test.labels);
% Finished dithering.

clearvars tempTrainingImages tempTestImages;
toc % Stop counting ellapsed seconds

load('quantizedNet7_9.mat'); % load the name of quantized network so it can be tested

accuracy = testnet(quantizedNet, testArray.images, testArray.labels, "accuracy")

scoresTest = minibatchpredict(quantizedNet, testArray.images);
YTest = scores2label(scoresTest, categories(testArray.labels));
confusionchart(testArray.labels, YTest);

val = quantizationDetails(quantizedNet);
layers = table2cell(val.QuantizedLearnables(:, 3));
layers2 = layers;
for i=1:3
    layers2{2*i} = fi(layers{2*i}, 1, 8);
end
allWeights = cellfun(@storedInteger, layers2, 'UniformOutput', false); % The int8 representations of the quantized network's weights without the rest of the structure.
                                                                        %  Useful for exporting the weights & biases. Pattern weight, bias, weight, bias, ...
for i=1:6
    hex{i} = arrayfun(@(x) string(dec2hex(x)), allWeights{i}); % new block to produce a hex representation of the allWeights data.
end

whos('allWeights');

delete(gcp("nocreate"));


function [result] = bayerDither(input28Square, select)
    % Classic Bayer Dithering with a 4x4 Bayer matrix
    if select
        bayer4 = [1, 9, 3, 11; 13, 5, 15, 7; 4, 12, 2, 10; 16, 8, 14, 6]; % Dark
    else
        bayer4 = [0, 8, 2, 10; 12, 4, 14, 6; 3, 11, 1, 9; 15, 7, 13, 5]; % Light
    end
    bayer4normed = bayer4./16;  % The dataset is not normalized around zero
    bayerUnfolded = repmat(bayer4normed, 7, 7); % Tile to 28x28 matrix
    result = double(input28Square > bayerUnfolded);
end
