% stepA_understand.m —— 可视化理解：CNN 到底在干什么（教学用，不改任何东西）
% 跑一次就能看见四件事：
%   ① 网络看到的输入（128×72）
%   ② 手算一个卷积点 vs 网络真实输出（证明"卷积=乘加"）
%   ③ conv1 的 8 张响应图（网络第一层"看到"的东西长什么样）
%   ④ 网络"认为脸在哪"的对象分热力图 + 最终框
clc; clear;
root = fileparts(mfilename('fullpath'));

S = load(fullfile(root, 'detector_net.mat'), 'net', 'inputH', 'inputW', 'anchorBoxes');
net = S.net;
T = load(fullfile(root, 'training_data.mat'), 'T');  T = T.T;

%% 0) 选一张训练图（也可以改成你自己的照片）
idx = 1;
f = T.imageFilename{idx};
img = imread(f);
if size(img, 3) == 1, img = repmat(img, [1 1 3]); end
imgS = imresize(img, [S.inputH S.inputW]);          % 缩放到网络输入尺寸
sx = S.inputW / size(img, 2);   sy = S.inputH / size(img, 1);
gt = T.face{idx} .* [sx sy sx sy];

fprintf('图片: %s\n', f);
fprintf('原图 %d×%d → 缩放为网络输入 %d×%d\n', size(img,2), size(img,1), S.inputW, S.inputH);
fprintf('这张图里的人脸框（输入坐标）: [%.0f %.0f %.0f %.0f]\n', gt(1,:));

%% ① 网络看到的输入
figure('Name', '① 输入'); imshow(imgS); hold on;
rectangle('Position', gt(1,:), 'EdgeColor', 'g', 'LineWidth', 2);
title('① 网络输入 = 128×72 的图（绿框 = 标准答案）');

%% ② 手算一个卷积点，和网络真实输出对比
A1 = activations(net, single(imgS), 'relu1');        % conv1 + BN + ReLU 的真实输出 128×72×8
[Wf, bf] = fold_bn(net.Layers(2).Weights, net.Layers(2).Bias, net.Layers(3));   % 把 BN 折进权重

r = 36;  c = 64;  co = 1;                            % 取一个位置、第 1 个输出通道
patch = zeros(3, 3, 3);
for ky = 1:3, for kx = 1:3, for ci = 1:3
    patch(ky,kx,ci) = imgS(r+ky-2, c+kx-2, ci);      % pad=1：输出(r,c) 看输入的 (r-1..r+1, c-1..c+1)
end, end, end

acc = bf(co);
for ky = 1:3, for kx = 1:3, for ci = 1:3
    acc = acc + double(Wf(ky,kx,ci,co)) * double(patch(ky,kx,ci));
end, end, end
y_hand = max(0, acc);                                % ReLU：负数变 0
y_net  = double(A1(r, c, co));

fprintf('\n=== 手算 vs 网络（conv1 第 %d 通道 @ 位置 (%d,%d)）===\n', co, r, c);
fprintf('  偏置 b        = %.4f\n', bf(co));
fprintf('  27 次乘加累加 = %.4f\n', acc);
fprintf('  过 ReLU 之后  = %.4f   ← 手算结果\n', y_hand);
fprintf('  网络实际输出  = %.4f   ← 网络结果（差 %.2e）\n', y_net, abs(y_hand - y_net));
fprintf('  结论：所谓卷积，就是"一小块窗口 × 一组权重，乘加求和"，和 Sobel 一模一样\n');
fprintf('        区别只是：权重不是人写的，是训练学出来的（共 %d 组）\n', size(Wf, 4));

%% ③ conv1 的 8 张响应图
figure('Name', '③ conv1 的 8 张响应图');
for ch = 1:size(A1, 3)
    subplot(2, 4, ch);
    imagesc(A1(:,:,ch)); axis image off; colormap(gca, gray);
    title(sprintf('模板 %d', ch));
end
sgtitle('③ conv1：8 组自动学出来的模板滑过图 → 8 张响应图（越亮响应越强）');

%% ④ 网络认为脸在哪（对象分热力图）+ 最终框
H = activations(net, single(imgS), 'head_conv');     % 18×32×15
[Gh, Gw, ~] = size(H);
numA = size(S.anchorBoxes, 1);
obj = zeros(Gh, Gw);
for a = 1:numA
    obj = max(obj, min(max(H(:,:,(a-1)*5+1), 0), 1));   % 每锚第 1 通道 = 是不是脸
end
fprintf('\n=== 尺度（3 个候选框"模具"）===\n');
for a = 1:numA
    fprintf('  锚 %d: 宽 %.1f 像素, 高 %.1f 像素\n', a, S.anchorBoxes(a,1), S.anchorBoxes(a,2));
end
[mx, li] = max(obj(:));
[gy, gx] = ind2sub([Gh Gw], li);
fprintf('  对象分最高的一格: (列 %d, 行 %d)，分数 %.3f（全部格子中位数 %.3f）\n', ...
    gx, gy, mx, median(obj(:)));

[boxes, scores] = decode_boxes(H, S.anchorBoxes, S.inputH, S.inputW, false, []);
sc = 0;  if ~isempty(scores), sc = max(scores); end

figure('Name', '④ 网络怎么看这张图');
subplot(1, 3, 1); imshow(imgS); title('输入');
subplot(1, 3, 2);
imagesc(obj); axis image; colorbar; colormap(gca, jet);
title('对象分热力图（18×32，亮 = 更像脸）');
subplot(1, 3, 3); imshow(imgS); hold on;
if ~isempty(gt),    rectangle('Position', gt(1,:),    'EdgeColor','g','LineWidth',2); end
if ~isempty(boxes), rectangle('Position', boxes(1,:), 'EdgeColor','r','LineWidth',2,'LineStyle','--'); end
title(sprintf('绿=标准答案, 红=网络检测（分数 %.2f）', sc));

fprintf('\n说明：\n');
fprintf('  · 中间那张热力图就是"网络的看法"：亮的地方它认为有脸\n');
fprintf('  · 最后它挑分数最高的一格，用 5 个数字算出红框（位置+大小）\n');
fprintf('  · 训练做的事，就是让"有人脸的地方亮、没人的地方暗"\n');
