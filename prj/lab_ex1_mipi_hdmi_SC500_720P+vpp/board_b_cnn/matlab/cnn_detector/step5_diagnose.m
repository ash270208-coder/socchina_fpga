% step5_diagnose.m —— 诊断：对象分热力图 / top 候选 / 训练图上的定位质量
% 这是脚本：点 Run 或输入 >> step5_diagnose
% 运行前：先跑 step1、step2（step3/step4 不需要）
% 输出两件事：
%   ① 测试图的 top-10 候选（分数、锚、框、所在格）——看模型"觉得脸在哪"
%   ② 20 张训练图上"预测框 vs 真实框的 IoU"——判断是训练不足还是测试图域差异
clc;
root = fileparts(mfilename('fullpath'));
P = load(fullfile(root, 'out', 'net_params.mat'), 'anchors');
S = load(fullfile(root, 'detector_net.mat'), 'net', 'inputH', 'inputW');
T = load(fullfile(root, 'training_data.mat'), 'T'); T = T.T;
net = S.net;  anchors = P.anchors;
cellW = S.inputW/32;  cellH = S.inputH/18;

%% 1) 测试图 top-10 候选
testImage = fullfile(root, 'test.jpg');
if ~isfile(testImage)
    td = fullfile(root, 'data', 'test');
    d = dir(fullfile(td, '*'));
    exts = {'.jpg', '.jpeg', '.png', '.bmp'};
    keep = false(1, numel(d));
    for e = 1:numel(exts), keep = keep | endsWith(lower({d.name}), exts{e}); end
    d = d(keep);
    if ~isempty(d), testImage = fullfile(td, d(1).name); end
end
if ~isfile(testImage)
    testImage = T.imageFilename{1};
    fprintf('未找到测试图，用训练集第一张\n');
end
img = imread(testImage);
if size(img, 3) == 1, img = repmat(img, [1 1 3]); end
imgSmall = imresize(img, [S.inputH S.inputW]);
H = activations(net, single(imgSmall), 'head_conv');
cand = decodeAll(H, anchors, S.inputH, S.inputW);
[s, ord] = sort(cand(:,5), 'descend');
fprintf('=== 测试图 %s ===\n', testImage);
fprintf('top-10 候选（score / 锚 / 框[x y w h] / 命中格）:\n');
for i = 1:min(10, size(cand,1))
    r = cand(ord(i), :);
    gx = floor((r(1)+r(3)/2)/cellW);  gy = floor((r(2)+r(4)/2)/cellH);
    fprintf('%2d) %.3f  锚%d  框[%6.1f %6.1f %6.1f %6.1f]  格(%2d,%2d)\n', ...
        i, r(5), r(6), r(1), r(2), r(3), r(4), gx, gy);
end
fprintf('分数中位/最大: %.3f / %.3f\n', median(cand(:,5)), max(cand(:,5)));

imshow(imgSmall); hold on;
cols = lines(5);
for i = 1:min(5, size(cand,1))
    r = cand(ord(i), :);
    rectangle('Position', r(1:4), 'EdgeColor', cols(i,:), 'LineWidth', 1.5);
    text(r(1), max(1,r(2)), sprintf('%.2f', r(5)), 'Color', cols(i,:));
end
title('测试图 top-5 候选（颜色=排名）');

%% 2) 训练图上的定位质量（GT 已知 → 能算出到底准不准）
nEval = 20;
rng(0); idx = randperm(height(T), min(nEval, height(T)));
ious = zeros(numel(idx), 1);  sc = zeros(numel(idx), 1);
for n = 1:numel(idx)
    f = T.imageFilename{idx(n)};
    im = imread(f);  if size(im,3) == 1, im = repmat(im,[1 1 3]); end
    A = activations(net, single(imresize(im,[S.inputH S.inputW])), 'head_conv');
    c = decodeAll(A, anchors, S.inputH, S.inputW);
    [sc(n), o] = max(c(:,5));
    bb = c(o, 1:4);
    info = imfinfo(f);
    sx = S.inputW/info.Width;  sy = S.inputH/info.Height;
    gt = T.face{idx(n)} .* [sx sy sx sy];
    if ~isempty(gt)
        ious(n) = max(bboxOverlapRatio(bb, gt(:,1:4)));
    end
end
fprintf('\n=== 训练图定位质量（%d 张，用 top-1 候选 vs GT）===\n', numel(idx));
fprintf('IoU: 中位 %.2f，均值 %.2f，>0.3 占比 %.0f%%，>0.5 占比 %.0f%%\n', ...
    median(ious), mean(ious), 100*mean(ious>0.3), 100*mean(ious>0.5));
fprintf('top-1 分数：中位 %.2f\n', median(sc));

%% ---- 工具：解码全部候选（不设阈值、不取 top-1）----
function cand = decodeAll(H, anchors, inputH, inputW)
    [Gh, Gw, ~] = size(H);
    numA = size(anchors, 1);
    cellW = inputW/Gw;  cellH = inputH/Gh;
    [gy, gx] = ndgrid(0:Gh-1, 0:Gw-1);
    cand = zeros(0, 6);
    for a = 1:numA
        ch = (a-1)*5 + (1:5);
        p = H(:, :, ch);
        to = min(max(p(:,:,1), 0), 1);
        tx = min(max(p(:,:,2), 0), 1);
        ty = min(max(p(:,:,3), 0), 1);
        w = anchors(a,1) .* exp(p(:,:,4));
        h = anchors(a,2) .* exp(p(:,:,5));
        cx = (gx + tx) * cellW;   cy = (gy + ty) * cellH;
        cand = [cand; cx(:)-w(:)/2, cy(:)-h(:)/2, w(:), h(:), to(:), a*ones(numel(to),1)]; %#ok<AGROW>
    end
end
