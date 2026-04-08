%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Name: Recover MNIST file from github Script   %
% Author: David Griessmann                      %
% Date: 4-03-26                                 %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear;close;clc;

dir = pwd;
unzip("testMNIST.zip", dir);
load("test.mat");
unzip("trainingMNIST.zip", dir);
load("training.mat");
save("mnist.mat", "test", "training", '-mat');
delete('test.mat');
delete('training.mat');
