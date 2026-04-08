%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Name: MNIST Net 7 Training Script %
% Author: David Griessmann          %
% Date: 4-01-26                     %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear;close;clc;

% Deep Network Designer generated code
net = dlnetwork;
tempNet = [
    imageInputLayer([28 28 1],"Name","imageinput")
    fullyConnectedLayer(40,"Name","fc")
    reluLayer("Name","relu")
    fullyConnectedLayer(30,"Name","fc_1")
    reluLayer("Name","relu_1")
    % fullyConnectedLayer(20,"Name","fc_2_1")
    % reluLayer("Name","relu_2")
    fullyConnectedLayer(10,"Name","fc_2")
    softmaxLayer("Name","softmax")];
net = addLayers(net,tempNet);

% clean up helper variable
clear tempNet;

net = initialize(net);
% End of generated code

parpool('Threads');
load('mnist.mat');
tic % Start counting ellapsed seconds
sel = false;
% Start dithering dataset
tempTrainingImages = zeros(training.height, training.width, 1, training.count);
parfor i = 1:training.count
    tempTrainingImages(:, :, 1, i) = bayerDither(training.images(:, :, i), sel);
end
trainingArray.images = tempTrainingImages;
trainingArray.labels = categorical(training.labels);

tempTestImages = zeros(test.height, test.width, 1, test.count);
parfor j = 1:test.count
   tempTestImages(:, :, 1, j) = bayerDither(test.images(:, :, j), sel);
end
testArray.images = tempTestImages;
testArray.labels = categorical(test.labels);
% Finished dithering

clearvars tempTrainingImages tempTestImages;
toc % Stop counting ellapsed seconds

options = trainingOptions("sgdm", MaxEpochs=30, Momentum=0.95, ...
    InitialLearnRate=0.01, Plots="training-progress", ...
    Metrics="accuracy", verbose=false, L2Regularization=2e-3);

trainedNet = trainnet(trainingArray.images, trainingArray.labels, ...
    net, "crossentropy", options);

accuracy = testnet(trainedNet, testArray.images, testArray.labels, "accuracy")

scoresTest = minibatchpredict(trainedNet, testArray.images);
YTest = scores2label(scoresTest, categories(testArray.labels));
confusionchart(testArray.labels, YTest);

delete(gcp("nocreate"));

function [result] = bayerDither(input28Square, select)
    if select
        bayer4 = [1, 9, 3, 11; 13, 5, 15, 7; 4, 12, 2, 10; 16, 8, 14, 6]; % Dark version
    else
        bayer4 = [0, 8, 2, 10; 12, 4, 14, 6; 3, 11, 1, 9; 15, 7, 13, 5]; % Light version
    end
    bayer4normed = bayer4./16;  % The dataset is not normalized around zero.
    %  It is important for accuracy that the bayer matrix is normalized and
    %  balanced in the same way as the data.
    bayerUnfolded = repmat(bayer4normed, 7, 7); % Duplicate bayer4 until it tiles on the 28x28 input image
    result = double(input28Square > bayerUnfolded); % Take the thresholds. Over -> 1, Under -> 0.
end
