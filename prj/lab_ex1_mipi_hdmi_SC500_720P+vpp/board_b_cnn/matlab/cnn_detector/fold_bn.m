function [Wf, bf] = fold_bn(convW, convB, bn)
% fold_bn.m —— 把 BN 折叠进卷积（部署前必做：硬件没有 BN 层）
%   W' = W * Scale / sqrt(Var + Eps)
%   b' = (b - Mean) * Scale / sqrt(Var + Eps) + Offset
% 所有参数先转 double 并整形为 [1 1 1 Cout]，兼容不同 MATLAB 版本的存储形态
    if isa(bn, 'nnet.cnn.layer.BatchNormalizationLayer')
        s = bn.Scale;  o = bn.Offset;
        m = bn.TrainedMean;  v = bn.TrainedVariance;  e = bn.Epsilon;
    else
        s = bn.s; o = bn.o; m = bn.m; v = bn.v; e = bn.e;
    end
    s = reshape(double(s), 1, 1, 1, []);
    o = reshape(double(o), 1, 1, 1, []);
    m = reshape(double(m), 1, 1, 1, []);
    v = reshape(double(v), 1, 1, 1, []);
    W = double(convW);
    a = s ./ sqrt(v + double(e));                  % [1 1 1 Cout]
    if numel(a) ~= size(W, 4)
        error('BN 参数与卷积输出通道数不匹配：conv=%s, bn=%s', ...
              mat2str(size(W)), mat2str(size(a)));
    end
    Wf = W .* a;
    if isempty(convB)
        bf = (0 - m) .* a + o;
    else
        b  = reshape(double(convB), 1, 1, 1, []);   % 先整形为 [1 1 1 Cout]，避免与 4-D 参数隐式扩展错位
        bf = (b - m) .* a + o;
    end
    bf = reshape(bf, 1, []);
end
