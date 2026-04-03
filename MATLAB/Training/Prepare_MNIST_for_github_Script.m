%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Name: Prepare MNIST for github Script %
% Author: David Griessmann              %
% Date: 4-03-26                         %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear;close;clc;

load('mnist.mat');

save('test.mat', "test", '-mat');
save('training.mat', "training", '-mat');
pause(1) % Allow the operating sytem to finish saving the file before mucking with it.
zip('trainingMNIST.zip', 'training.mat');
zip('testMNIST.zip', 'test.mat');
pause(1) % As before
delete('test.mat');
delete('training.mat');
