%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Name  : Fix bias bits length              %
% Author: David                             %
% Date  : 2026-04-17                        %
% Notes : Take the first 8 bits as the bias %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
clear; close; clc;

% A better approach that leverages the fi information
load("/MATLAB Drive/quantizedNet7_9.mat")

val = quantizationDetails(quantizedNet);
layers = table2cell(val.QuantizedLearnables(:, 3));
layers2 = layers;
for i=1:3
    layers2{2*i} = fi(layers{2*i}, 1, 8);
end
allWeights = cellfun(@storedInteger, layers2, 'UniformOutput', false);


% Simply takes 8-bits from the 32-bit biases
% load("/MATLAB Drive/weights7_9.mat")

% biases = [allWeights(2); allWeights(4); allWeights(6)];
% allWeights2 = allWeights;
% 
% for i=1:3
%     chunks = int2bit(allWeights{2*i}, 8, true);
%     allWeights2{2*i} = bit2int(chunks, 8, isSigned = true);
% end