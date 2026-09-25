function Y = conv2d_int(X, W, biasInt, stride, pad)
% conv2d_int.m —— 定点卷积（金标准）
% X / W / biasInt 为整数（double 数组携带整数值）。
% 关键：double 在 int32 范围内累加是精确的（<=2^53 无舍入），
% 因此这里用 double 矩阵乘得到与 Verilog 整数累加器逐位一致的结果。
% X: [H W Cin]（uint8 域 0..255）；W: [K K Cin Cout]（int8 值）；biasInt: [1 Cout]
    [H, Wd, Cin] = size(X);
    [K, ~, ~, Cout] = size(W);
    biasInt = reshape(biasInt, 1, []);           % 强制 [1 Cout]，兼容各种存储形状
    if K == 1
        cols = reshape(permute(X, [3 1 2]), Cin, H * Wd);
        Wm = reshape(W, Cin, Cout);
        if size(cols, 1) ~= size(Wm, 1)
            error('卷积尺寸不匹配: X=%s, W=%s', mat2str(size(X)), mat2str(size(W)));
        end
        Y  = cols.' * Wm + biasInt;
        Ho = H; Wo = Wd;
    else
        Xp = zeros(H + 2*pad, Wd + 2*pad, Cin);
        Xp(pad+1:pad+H, pad+1:pad+Wd, :) = X;
        Hpos = H + 2*pad - K + 1;                  % 可选的窗口起点数（行/列方向）
        Wpos = Wd + 2*pad - K + 1;
        rs = 1:stride:Hpos;
        cs = 1:stride:Wpos;
        [rr, cc] = ndgrid(rs, cs);
        sel = rr + (cc-1)*Hpos;                    % im2col 列主序线性位置（行、列都按 stride 跳）
        cols = zeros(K*K*Cin, numel(sel));
        for c = 1:Cin
            Cc = im2col(Xp(:,:,c), [K K], 'sliding');
            cols((c-1)*K*K+1 : c*K*K, :) = Cc(:, sel);
        end
        Wm = reshape(W, K*K*Cin, Cout);
        if size(cols, 1) ~= size(Wm, 1)
            error('卷积尺寸不匹配: X=%s, W=%s (cols=%s, Wm=%s)', ...
                mat2str(size(X)), mat2str(size(W)), mat2str(size(cols)), mat2str(size(Wm)));
        end
        Y  = cols.' * Wm + biasInt;
        Ho = numel(rs);
        Wo = numel(cs);
    end
    Y = reshape(Y, Ho, Wo, Cout);
end
