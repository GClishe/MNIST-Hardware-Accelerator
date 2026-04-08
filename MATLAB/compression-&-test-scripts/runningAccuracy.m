function [accuracy] = runningAccuracy(predictionScores, ~, labels)
%runningAccuracy Take the accuracy of a NN for a single prediction & label
%   As input takes one prediction and one label and finds how accurate that
%   singluar prediction was.
arguments (Input)
    predictionScores % (1, :) double {mustBeNumeric}
    ~
    labels % categorical
end

arguments (Output)
    accuracy (1,1) double {mustBeNumeric}
end

labels = readall(labels);
label = labels{:,2};

classNames = categories(label);
predictedLabels = scores2label(predictionScores,classNames);
accuracy = mean(squeeze(predictedLabels) == label);
end