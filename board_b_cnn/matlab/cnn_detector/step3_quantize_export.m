% step3_quantize_export.m —— BN 折叠 → int8 量化 → 激活校准 → 导出 .mem + 参数头
% 这是脚本：点 Run 或输入 >> step3_quantize_export
% 运行前：先跑 step1、step2。输出全部在 out/ 目录：
%   w_conv1..4.mem / w_head.mem   卷积权重，int8 二进制补码 hex，每行一个值，
%                                 顺序 = 列主序 [ky kx cin cout]（即 MATLAB weights(:)）
%   b_conv1..4.mem / b_head.mem   折叠后偏置 b_int，32-bit 二进制补码 hex
%   lut_sigmoid.mem               8-bit ×1024 项（检测头 to 通道的分数）；lut_exp.mem 16-bit Q11（tw/th）
%   net_params.mat / params_summary.txt  全部定标常数（Verilog 接口契约）
% 检测头通道契约（每锚 5 通道）：[to tx ty tw th]
%   score = sigmoid(to)；cx = (gx+tx)·cellW（tx 截 [0,1]）；w = anchorW·exp(tw)；h = anchorH·exp(th)
clc;
root = fileparts(mfilename('fullpath'));
outDir = fullfile(root, 'out');
if ~exist(outDir, 'dir'), mkdir(outDir); end

S = load(fullfile(root, 'detector_net.mat'), 'net', 'anchorBoxes', 'inputH', 'inputW', 'numCal');
net = S.net;  anchors = S.anchorBoxes;
lay = net.Layers;
T = load(fullfile(root, 'training_data.mat'), 'T');  T = T.T;

fprintf('--- 网络层清单（核对用）---\n');
for i = 1:numel(lay)
    fprintf('%2d  %-22s  %s\n', i, lay(i).Name, class(lay(i)));
end

%% 1) 提取 conv(+BN) 并折叠（conv1..conv4 + head_conv）
params = [];
for i = 1:numel(lay)
    if isa(lay(i), 'nnet.cnn.layer.Convolution2DLayer') && ~strcmp(lay(i).Name, 'loss')
        if i < numel(lay) && isa(lay(i+1), 'nnet.cnn.layer.BatchNormalizationLayer')
            [W, b] = fold_bn(lay(i).Weights, lay(i).Bias, lay(i+1));
        else
            W = lay(i).Weights;  b = lay(i).Bias;
        end
        params(end+1).name   = lay(i).Name;                     %#ok<SAGROW>
        params(end).Wfloat   = W;
        params(end).bfloat   = b;
        params(end).stride   = lay(i).Stride(1);
        params(end).pad      = lay(i).PaddingSize(1);
    end
end
nLayer = numel(params);
for k = 1:nLayer
    fprintf('层 %-10s 权重 %s\n', params(k).name, mat2str(size(params(k).Wfloat)));
end
if nLayer ~= 5
    warning('预期 5 层（conv1..4 + head_conv），实际 %d 层，请核对层清单', nLayer);
end

%% 2) 权重逐层 int8 对称量化
for k = 1:nLayer
    W = params(k).Wfloat;
    s = max(abs(W(:))) / 127;
    if s == 0, s = 1; end
    params(k).sW = s;
    params(k).Wq = int8(round(W / s));
end

%% 3) 激活校准：每层输出 scale = max(0, 输出) / 255（8-bit 无符号）
%    硬件里 BN 已折叠进卷积，卷积输出 ≈ BN 输出，故用 activations(..., 'bnN') 取范围
nCal = min(S.numCal, height(T));
rng(0);  idx = randperm(height(T), nCal);
actNames = {'bn1', 'bn2', 'bn3', 'bn4', 'relu4'};
calMax = containers.Map();
maxAbsHead = 0;
maxAbsTwTh = 0;                     % 只统计 tw/th 通道（exp LUT 真正作用的对象）
for n = 1:nCal
    img = single(imresize(imread(T.imageFilename{idx(n)}), [S.inputH S.inputW]));
    for a = 1:numel(actNames)
        A = activations(net, img, actNames{a});
        m = max(A(:));  if m < 0, m = 0; end
        if isKey(calMax, actNames{a})
            calMax(actNames{a}) = max(calMax(actNames{a}), m);
        else
            calMax(actNames{a}) = m;
        end
    end
    % 检测头输出范围：全通道（信息用）与 tw/th 通道（exp LUT 定标用）
    H = activations(net, img, 'head_conv');
    maxAbsHead = max(maxAbsHead, max(abs(H(:))));
    numA = size(H, 3) / 5;
    chTwTh = zeros(1, 2*numA);
    for a = 1:numA, chTwTh((a-1)*2+(1:2)) = (a-1)*5 + [4 5]; end
    maxAbsTwTh = max(maxAbsTwTh, max(abs(H(:,:,chTwTh,:)), [], 'all'));
end
fprintf('检测头全通道实域范围: ±%.4f（其中 tw/th: ±%.4f）\n', maxAbsHead, maxAbsTwTh);

%% 4) 定点账本（Verilog 与金标准共用的公式）
%    整数累加: acc = Σ(Wq·xq) + b_int
%    层输出:   xq_next = round(acc · mOut)，mOut = sW·sIn/sOut（ReLU 层截到 0..255）
%    检测头:   输出还原实域 head = acc · (sW·sIn)（直接送 LUT 解码）
sIn = 1;                                        % 输入 RGB 0..255，scale = 1
for k = 1:nLayer
    params(k).sIn = sIn;
    if k == nLayer
        params(k).sOut = params(k).sW * sIn;
        params(k).mOut = params(k).sW * sIn;    % head = acc × (sW·sIn) 还原到实数域
    else
        sOut = calMax(sprintf('bn%d', k)) / 255;
        if sOut <= 0, sOut = 1/255; end         % 防零
        params(k).sOut = sOut;
        params(k).mOut = params(k).sW * sIn / sOut;
        sIn = sOut;
    end
    params(k).bInt = round(params(k).bfloat / (params(k).sW * params(k).sIn));
    fprintf('层 %-10s bInt 尺寸 %s（conv1..4 应为 [1 通道数]，head 应为 [1 15]）\n', ...
        params(k).name, mat2str(size(params(k).bInt)));
    if any(abs(params(k).bInt) > 2^31 - 1)
        warning('层 %s 的 bInt 超出 int32，请检查校准范围', params(k).name);
    end
end

%% 5) 解码 LUT
LUT_N = 1024;
% sigmoid: 实域 x∈[-8,8)，idx = round((x+8)*64)，输出 8-bit（用于 to 通道分数）
xs = linspace(-8, 8 - 16/LUT_N, LUT_N);
lut_sig = uint8(round(255 ./ (1 + exp(-xs))));
% exp:     实域 x∈[-4,4)，idx = round((x+4)*128)，输出 Q11（用于 tw/th）
xe = linspace(-4, 4 - 8/LUT_N, LUT_N);
lut_exp = uint16(round(2048 .* exp(xe)));
if maxAbsTwTh > 3.9
    warning('tw/th 输出 ±%.2f 超出 exp LUT 输入范围 ±4，将被饱和裁剪（仅影响极端框，通常无害）', maxAbsTwTh);
end

%% 6) 导出 .mem
for k = 1:nLayer
    p = params(k);
    tag = lower(p.name);
    if strcmp(tag, 'head_conv'), tag = 'head'; end
    write_i8 (fullfile(outDir, sprintf('w_%s.mem', tag)), p.Wq(:));
    write_i32(fullfile(outDir, sprintf('b_%s.mem', tag)), p.bInt);
end
write_u8 (fullfile(outDir, 'lut_sigmoid.mem'), lut_sig);
write_u16(fullfile(outDir, 'lut_exp.mem'),    lut_exp);
save(fullfile(outDir, 'net_params.mat'), 'params', 'anchors', 'lut_sig', 'lut_exp', 'maxAbsHead');
fprintf('已导出权重/偏置/LUT 到 %s\n', outDir);

%% 6b) FPGA 专用导出：高精度定点常数 + 打包权重（方案 A：综合用官方 ROM IP）
% 每层 mOut 的 Q32 常数（硬件公式 real = (acc*Q32 + 2^31) >>> 32）
vhFile = fullfile(outDir, 'cnn_params.vh');
fid = fopen(vhFile, 'w');
fprintf(fid, '// 由 step3_quantize_export.m 自动生成 —— Verilog 定点常数，勿手改\n');
fprintf(fid, '// 用法：real = (acc * `MOUT_Q32_xxx + 32''sd2147483648) >>> 32\n');
fprintf(fid, '`ifndef CNN_PARAMS_VH\n`define CNN_PARAMS_VH\n\n');
for k = 1:nLayer
    q32 = round(params(k).mOut * 2^32);
    params(k).mOutQ32 = q32;
    fprintf(fid, '`define MOUT_Q32_%s 32''d%d\n', upper(params(k).name), q32);
end
fprintf(fid, '\n// 锚框（Q4 定点：值 = 原始值 × 16）\n');
for a = 1:size(anchors, 1)
    fprintf(fid, '`define ANCHOR%d_W_Q4 16''d%d\n', a, round(anchors(a,1)*16));
    fprintf(fid, '`define ANCHOR%d_H_Q4 16''d%d\n', a, round(anchors(a,2)*16));
end
fprintf(fid, '\n`endif\n');
fclose(fid);
fprintf('定点常数已写入 %s\n', vhFile);

% 打包权重 ROM：每个字 64 位 = 8 个输出通道的 int8
%   字地址 = tap*numGrp + grp；字内 LSB = 该组第 0 个通道
for k = 1:nLayer
    p  = params(k);
    Wq = p.Wq;
    Kk = size(Wq,1);  Ci = size(Wq,3);  Co = size(Wq,4);
    TAPS  = Kk*Kk*Ci;
    Wt    = reshape(double(Wq), TAPS, Co);          % [tap, 输出通道]
    numGrp = ceil(Co/8);
    words  = zeros(TAPS*numGrp, 1, 'uint64');
    for t = 0:TAPS-1
        for g = 0:numGrp-1
            v = uint64(0);
            for c = 0:7
                ci = g*8 + c;
                if ci < Co
                    b8 = typecast(int8(Wt(t+1, ci+1)), 'uint8');
                    v  = bitor(v, bitshift(uint64(b8), 8*c));
                end
            end
            words(t*numGrp + g + 1) = v;
        end
    end
    tag = lower(p.name);
    if strcmp(tag, 'head_conv'), tag = 'head'; end
    fid = fopen(fullfile(outDir, sprintf('w_%s_packed.mem', tag)), 'w');
    for i2 = 1:numel(words)
        fprintf(fid, '%s\n', dec2hex(words(i2), 16));
    end
    fclose(fid);
    fprintf('打包权重 %-22s %4d 字 × 64bit（%d tap × %d 组）\n', ...
        sprintf('w_%s_packed.mem', tag), numel(words), TAPS, numGrp);
end

%% 7) 参数摘要（人读版接口契约）
fid = fopen(fullfile(outDir, 'params_summary.txt'), 'w');
fprintf(fid, '输入: %d x %d x 3 (uint8 RGB 0..255, scale=1)\n', S.inputW, S.inputH);
fprintf(fid, '锚框 [w h]: %s\n', mat2str(anchors));
fprintf(fid, '检测头通道（每锚 5 通道）: [to tx ty tw th]\n');
fprintf(fid, '层  stride pad  [K K Cin Cout]  sW       sIn      sOut     mOut\n');
for k = 1:nLayer
    p = params(k);
    fprintf(fid, '%-9s %-6d %-3d %-16s %.6g %.6g %.6g %.6g\n', ...
        p.name, p.stride, p.pad, mat2str(size(p.Wfloat)), p.sW, p.sIn, p.sOut, p.mOut);
end
fprintf(fid, '检测头实域范围: ±%.4f\n', maxAbsHead);
fprintf(fid, 'LUT: sigmoid 输入[-8,8) idx=round((x+8)*64) 输出8bit（to 分数）; exp 输入[-4,4) idx=round((x+4)*128) 输出Q11（tw/th）\n');
fprintf(fid, '.mem 权重顺序: 列主序 [ky kx cin cout]，int8 二进制补码 hex（2 字节/行）\n');
fprintf(fid, '.mem 偏置顺序: [cout]，int32 二进制补码 hex（8 字节/行）\n');
fclose(fid);
fprintf('参数摘要已写入 %s\n', fullfile(outDir, 'params_summary.txt'));

%% ---- 写文件辅助 ----
function write_i8(f, v)
    u = typecast(v(:), 'uint8');
    fid = fopen(f, 'w');
    fprintf(fid, '%02X\n', u);
    fclose(fid);
end

function write_i32(f, v)
    u = typecast(int32(v(:)), 'uint32');
    fid = fopen(f, 'w');
    fprintf(fid, '%08X\n', u);
    fclose(fid);
end

function write_u8(f, v)
    fid = fopen(f, 'w');
    fprintf(fid, '%02X\n', v(:));
    fclose(fid);
end

function write_u16(f, v)
    fid = fopen(f, 'w');
    fprintf(fid, '%04X\n', v(:));
    fclose(fid);
end
