function Y = conv2d_float(X, W, b, stride, pad)
% conv2d_float.m —— 多通道卷积（float，校准/参考用）
% X: [H W Cin]（double 或 single）；W: [K K Cin Cout]；b: [1 Cout]
% 语义与 MATLAB convolution2dLayer 一致（'same' 填充、stride 截断尾列）
    [H, Wd, Cin] = size(X);
    [K, ~, ~, Cout] = size(W);
    if K == 1
        cols = reshape(permute(X, [3 1 2]), Cin, H * Wd);
        Wm = reshape(W, Cin, Cout);
        Y  = cols.' * Wm + b;                  % [H*W, Cout]
        Ho = H; Wo = Wd;
    else
        Xp = zeros(H + 2*pad, Wd + 2*pad, Cin, 'like', X);
        Xp(pad+1:pad+H, pad+1:pad+Wd, :) = X;
        Hpos = H + 2*pad - K + 1;
        Wpos = Wd + 2*pad - K + 1;
        rs = 1:stride:Hpos;
        cs = 1:stride:Wpos;
        [rr, cc] = ndgrid(rs, cs);
        sel = rr + (cc-1)*Hpos;                    % 行、列都按 stride 跳
        cols = zeros(K*K*Cin, numel(sel), 'like', X);
        for c = 1:Cin
            Cc = im2col(Xp(:,:,c), [K K], 'sliding');
            cols((c-1)*K*K+1 : c*K*K, :) = Cc(:, sel);
        end
        Wm = reshape(W, K*K*Cin, Cout);
        Y  = cols.' * Wm + b;
        Ho = numel(rs);
        Wo = numel(cs);
    end
    Y = reshape(Y, Ho, Wo, Cout);
end
