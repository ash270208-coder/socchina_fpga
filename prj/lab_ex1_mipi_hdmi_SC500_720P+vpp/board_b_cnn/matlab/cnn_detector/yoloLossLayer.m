classdef yoloLossLayer < nnet.layer.RegressionLayer
% yoloLossLayer.m —— 加权 MSE 回归损失（正负样本不平衡 + ignore 区域）
% 每锚通道 [to tx ty tw th]；目标 T 中：
%   to = 1  → 正样本单元（对象分 λobj、坐标 λcoord）
%   to = 0  → 背景单元（对象分 λnoobj）
%   to = -1 → 忽略单元（不计任何损失）
%
% 关键：归一化用"正样本单元数"，不是 numel(Y)。
%   numel(Y) 每批 13 万+ 元素，而坐标只有 ~40 个正样本单元参与，
%   除以 numel(Y) 会把坐标梯度稀释 5 个数量级（实测坐标完全学不动）。
    properties
        LambdaObj   = 5
        LambdaNoobj = 0.5
        LambdaCoord = 5
    end

    methods
        function layer = yoloLossLayer(name, lo, ln, lc)
            layer.Name = name;
            if nargin > 1
                layer.LambdaObj   = lo;
                layer.LambdaNoobj = ln;
                layer.LambdaCoord = lc;
            end
        end

        function loss = forwardLoss(layer, Y, T)
            W    = weightsFor(Y, T, layer);
            nPos = max(1, countPos(T));
            err  = (Y - T).^2 .* W;
            loss = sum(err(:)) / nPos;
        end

        function dLdY = backwardLoss(layer, Y, T)
            W    = weightsFor(Y, T, layer);
            nPos = max(1, countPos(T));
            dLdY = 2 .* (Y - T) .* W ./ nPos;
        end
    end
end

function n = countPos(T)
% 统计 to 通道中 >0.5 的单元数（每锚块的第 1 个通道）
    to = T(:, :, 1:5:end, :);
    n  = sum(to(:) > 0.5);
end

function W = weightsFor(Y, T, layer)
    numA = size(Y, 3) / 5;
    W = zeros(size(Y), 'like', Y);
    for a = 1:numA
        ch = (a-1)*5 + (1:5);
        to    = T(:,:,ch(1),:);
        isObj = to > 0.5;
        isIgn = to < -0.5;
        W(:,:,ch(1),:) = layer.LambdaObj .* isObj + ...
                         layer.LambdaNoobj .* (~isObj & ~isIgn);
        W(:,:,ch(2:5),:) = repmat(layer.LambdaCoord .* isObj, 1, 1, 4, 1);
    end
end
