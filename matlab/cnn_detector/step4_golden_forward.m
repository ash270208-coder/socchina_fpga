% step4_golden_forward.m —— int8 定点金标准前向 + 解码 + 与浮点网络对比
% 这是脚本：点 Run 或输入 >> step4_golden_forward
% 运行前：先跑 step1、step2、step3。测试图优先级：脚本目录 test.jpg → data/test/ 第一张 → 训练集第一张。
% 输出：浮点网络与 int8 定点前向的检测结果对比（同一张图，首框 IoU > 0.5 = 量化链路正确），并画图。
% 后续用途：把逐层输出保存下来，作为 ModelSim 仿真的金标准。
clc;
root = fileparts(mfilename('fullpath'));
P = load(fullfile(root, 'out', 'net_params.mat'), 'params', 'anchors', 'lut_sig', 'lut_exp');
S = load(fullfile(root, 'detector_net.mat'), 'net', 'inputH', 'inputW');
net = S.net;

testImage = fullfile(root, 'test.jpg');
if ~isfile(testImage)
    testDir = fullfile(root, 'data', 'test');
    if exist(testDir, 'dir')
        d = dir(fullfile(testDir, '*'));
        d = d(~[d.isdir]);
        exts = {'.jpg', '.jpeg', '.png', '.bmp'};
        keep = false(1, numel(d));                  % 行向量，与 endsWith 输出形状一致
        for e = 1:numel(exts)
            keep = keep | endsWith(lower({d.name}), exts{e});
        end
        d = d(keep);
        if ~isempty(d), testImage = fullfile(testDir, d(1).name); end
    end
end
if ~isfile(testImage)
    T = load(fullfile(root, 'training_data.mat'), 'T');
    testImage = T.T.imageFilename{1};
    fprintf('未找到 test.jpg 与 data/test/ 图片，用训练集第一张：%s\n', testImage);
end
img = imread(testImage);
if size(img, 3) == 1, img = repmat(img, [1 1 3]); end
imgSmall = imresize(img, [S.inputH S.inputW]);

%% ---- 浮点参考（训练好的网络前向，取 head_conv 输出）----
Hf = activations(net, single(imgSmall), 'head_conv');
[bf, sf] = decode_boxes(Hf, P.anchors, S.inputH, S.inputW, false, P.lut_exp);
if isempty(bf)
    fprintf('浮点网络: 无框通过阈值\n');
else
    fprintf('浮点网络: 最高分 %.3f, 框 [%.1f %.1f %.1f %.1f]\n', sf, bf);
end

%% ---- int8 定点前向（与 Verilog 同一公式）----
dumpGolden = true;                             % true = 导出 ModelSim 对照用的逐层金标准
dumpDir = fullfile(root, 'out', 'golden');
if dumpGolden && ~exist(dumpDir, 'dir'), mkdir(dumpDir); end

x = double(imgSmall);                          % 0..255，sIn = 1
if dumpGolden, dumpMat(fullfile(dumpDir, 'x0_input.txt'), x); end
for k = 1:numel(P.params)
    p = P.params(k);
    fprintf('[定点] 层 %d %s: X=%s, W=%s, bInt=%s\n', k, p.name, ...
        mat2str(size(x)), mat2str(size(p.Wq)), mat2str(size(p.bInt)));
    acc = conv2d_int(x, double(p.Wq), p.bInt, p.stride, p.pad);
    realV = acc .* p.mOut;
    if k < numel(P.params)
        x = min(max(round(realV), 0), 255);    % ReLU + 8-bit 无符号量化
        if dumpGolden
            dumpMat(fullfile(dumpDir, sprintf('x%d_%s.txt', k, p.name)), x);
        end
    else
        head = realV;                          % 检测头保持实域，送 LUT 解码
        if dumpGolden
            dumpMat(fullfile(dumpDir, 'head_real.txt'), int32(round(head * 4096)));  % Q12
        end
    end
end
if dumpGolden
    fprintf('金标准已导出到 %s（ModelSim 逐层对照用，head 为 Q12 定点）\n', dumpDir);
end
[boxes, scores] = decode_boxes(head, P.anchors, S.inputH, S.inputW, false, P.lut_exp);
if isempty(boxes)
    fprintf('int8 定点: 无框通过阈值\n');
else
    fprintf('int8 定点: 最高分 %.3f, 框 [%.1f %.1f %.1f %.1f]\n', scores, boxes);
end

%% ---- 对比（同一输入坐标，直接算 IoU）----
if ~isempty(bf) && ~isempty(boxes)
    iou = bboxOverlapRatio(bf(1,:), boxes(1,:));
    fprintf('首框 IoU = %.3f（> 0.5 说明量化/解码链路正确）\n', iou);
    if iou < 0.5
        fprintf(['IoU 偏低排查顺序：\n 1) 检测头通道顺序（每锚 [to tx ty tw th]）；\n' ...
                 ' 2) 锚框尺寸是否匹配；\n 3) 校准图数量 numCal 是否太少。\n']);
    end
elseif isempty(bf) && ~isempty(boxes)
    fprintf('注意：浮点无框但定点有框，量化引入了误检（或浮点分数恰在阈值下）\n');
end

%% ---- 画图（不用 legend，避免版本差异下的句柄兼容问题）----
imshow(imgSmall);  hold on;
if ~isempty(bf)
    rectangle('Position', bf(1,:), 'EdgeColor', 'g', 'LineWidth', 2);
end
if ~isempty(boxes)
    rectangle('Position', boxes(1,:), 'EdgeColor', 'r', 'LineWidth', 2, 'LineStyle', '--');
end
title(sprintf('绿 = 浮点，红虚线 = int8（%d×%d 输入），IoU 见命令行输出', S.inputW, S.inputH));

if dumpGolden
    fid = fopen(fullfile(dumpDir, 'boxes.txt'), 'w');
    if ~isempty(bf)
        fprintf(fid, 'float  框 [%.4f %.4f %.4f %.4f]  score %.4f\n', bf(1,:), sf);
    else
        fprintf(fid, 'float  无框\n');
    end
    if ~isempty(boxes)
        fprintf(fid, 'int8   框 [%.4f %.4f %.4f %.4f]  score %.4f\n', boxes(1,:), scores);
    else
        fprintf(fid, 'int8   无框\n');
    end
    fclose(fid);
end

%% ---- 导出辅助 ----
function dumpMat(f, X)
    fid = fopen(f, 'w');
    fprintf(fid, '%s\n', mat2str(size(X)));      % 第 1 行：尺寸
    fprintf(fid, '%d\n', int32(X(:)));           % 之后每行一个值（列主序）
    fclose(fid);
end
