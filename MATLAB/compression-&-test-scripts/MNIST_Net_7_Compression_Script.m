%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Name: MNIST Net 7 Compression Script  %
% Author: David Griessmann              %
% Date: 4-08-26                         %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear;close;clc;

parpool('Threads');
load('mnist.mat');
tic % Start counting ellapsed seconds

% Dither dataset, assumes 28x28 numeric input
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

% Used to make the ditheredMNIST.mat file, no need to repeat the process.
    % Saved for propriety.
% ditheredStruct.trainingImages = trainingArray.images;
% ditheredStruct.trainingLables = trainingArray.labels;
% ditheredStruct.testImages = testArray.images;
% ditheredStruct.testLabels = testArray.labels;
% save('ditheredMNIST.mat', "ditheredStruct", '-mat');

clearvars tempTrainingImages tempTestImages;
toc % Stop counting ellapsed seconds

% Make into datastore for the quantization application compatability.
imgDatastore = arrayDatastore(trainingArray.images, 'IterationDimension', 4);
labelDatastore = arrayDatastore(trainingArray.labels, 'IterationDimension', 1);
combinedTrainingDS = combine(imgDatastore, labelDatastore); % Combine into a single datastore
% Duplicated for testArray
imgDatastore = arrayDatastore(testArray.images, 'IterationDimension', 4);
labelDatastore = arrayDatastore(testArray.labels, 'IterationDimension', 1);
combinedTestDS = combine(imgDatastore, labelDatastore);

load('MLP2-4-01-26.mat'); % Load the pretrained, but not yet compressed, network of your choice.

miniStore = minibatchqueue(imgDatastore, MiniBatchFormat="SSBC");
[netProjected,info] = compressNetworkUsingProjection(trainedNet,miniStore);
accuracyBTN = testnet(netProjected, testArray.images, testArray.labels, "accuracy") % accuracy before training projected network.

options = trainingOptions("sgdm", MaxEpochs=30, Momentum=0.95, ...
    InitialLearnRate=0.001, Plots="training-progress", ...
    Metrics="accuracy", verbose=false, L2Regularization=2e-3);

trainedPNet = trainnet(trainingArray.images, trainingArray.labels, ...
    netProjected, "crossentropy", options);

accuracy = testnet(trainedPNet, testArray.images, testArray.labels, "accuracy") % Accuracy after retraining.

scoresTest = minibatchpredict(trainedPNet, testArray.images);
YTest = scores2label(scoresTest, categories(testArray.labels));
confusionchart(testArray.labels, YTest);

disp("At this point the environment is setup for quantization, please make use of the Deep Network Quantizer App.");
disp("So far the histogram quantization method has produced the best results. However, your milage may vary.");
disp("Export and enjoy your quantized network, don't forget to save it to a file to test using: MNIST Net 7 Test Quantization Script.");

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
