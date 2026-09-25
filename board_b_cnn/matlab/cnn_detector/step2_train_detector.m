% step2_train_detector.m —— 方案 A 网络训练（全标准层 + 回归目标）
% 这是脚本：点 Run 或输入 >> step2_train_detector
% 网络 = conv1(3×3,3→8) → conv2(s2,8→16) → conv3(s2,16→32) → conv4(32→32)
%      → head_conv(1×1, 32→15 = 3 锚 × [to tx ty tw th])，输出 18×32×15
% 训练要点（针对"框画错位置"的改进）：
%   ① 锚框按数据 k-means 自动估计；② 每个 GT 多分配一个次优锚；
%   ③ ignore 区域（框附近但非正样本的格不计背景损失）；④ 加权损失见 yoloLossLayer.m
% 运行前：先跑 step1_prepare_data.m 生成 training_data.mat
clc;
root = fileparts(mfilename('fullpath'));

%% ---- 参数 ----
inputH = 72; inputW = 128;                     % 720p ÷10
maxEpochs = 80;   miniBatch = 16;   lr0 = 1e-3;
numCal    = 32;                                % 校准图数量（step3 用）

%% ---- 数据 ----
S = load(fullfile(root, 'training_data.mat'), 'T'); T = S.T;
imgs = cellstr(string(T.imageFilename));
bx0  = T.face;
if ~iscell(bx0)
    bx0 = mat2cell(double(bx0), ones(size(bx0,1),1), size(bx0,2));
end
fprintf('训练图 %d 张\n', numel(imgs));

%% ---- 预读图片尺寸、把 GT 框缩放到输入坐标 ----
Gh = inputH/4; Gw = inputW/4;                  % 网格 18×32
cellW = inputW/Gw;  cellH = inputH/Gh;         % 每格 4×4 输入像素
boxesIn = cell(numel(imgs), 1);
allsz = zeros(0, 2);
for i = 1:numel(imgs)
    b = bx0{i};
    if iscell(b) && numel(b) == 1, b = b{1}; end
    b = double(b);
    if ~isempty(b)
        info = imfinfo(imgs{i});
        sx = inputW / info.Width;   sy = inputH / info.Height;
        b = b(:, 1:4) .* [sx sy sx sy];
        b = b(b(:,3) >= 2 & b(:,4) >= 2, :);
    end
    boxesIn{i} = b;
    if ~isempty(b), allsz = [allsz; b(:,3) b(:,4)]; end %#ok<AGROW>
end

%% ---- 锚框：按数据自动估计（对数空间 k-means，3 个）----
anchorBoxes = kmeans_anchors(allsz, 3, 25);
fprintf('自动锚框 [w h]（输入域）: %s\n', mat2str(round(anchorBoxes*10)/10));
fprintf('GT 框宽 w 中位/90%%: %.1f / %.1f；框高 h 中位/90%%: %.1f / %.1f\n', ...
    qval(allsz(:,1),0.5), qval(allsz(:,1),0.9), qval(allsz(:,2),0.5), qval(allsz(:,2),0.9));

%% ---- 预编码回归目标（两遍：先正样本，再 ignore 区）----
numA = size(anchorBoxes, 1);
resp4 = zeros(Gh, Gw, 5*numA, numel(imgs), 'single');
nPos = 0; nIgn = 0; anchorCnt = zeros(1, numA);
for i = 1:numel(imgs)
    Y = zeros(Gh, Gw, 5*numA, 'single');
    b = boxesIn{i};
    if ~isempty(b)
        % 第一遍：正样本（最优锚 + 次优锚，增加坐标训练信号）
        for k = 1:size(b, 1)
            x = b(k,1); y = b(k,2); w = b(k,3); h = b(k,4);
            d = abs(log(w./anchorBoxes(:,1))) + abs(log(h./anchorBoxes(:,2)));
            [ds, ord] = sort(d);
            aList = ord(1);
            if numel(ord) > 1 && ds(2) <= ds(1) + 0.3
                aList = ord(1:2);
            end
            cx = x + w/2;  cy = y + h/2;
            gx = floor(cx/cellW);  gy = floor(cy/cellH);
            gx = min(max(gx, 0), Gw-1);  gy = min(max(gy, 0), Gh-1);
            for a = aList(:)'
                ch = (a-1)*5;
                Y(gy+1, gx+1, ch+1) = 1;                     % to
                Y(gy+1, gx+1, ch+2) = cx/cellW - gx;         % tx
                Y(gy+1, gx+1, ch+3) = cy/cellH - gy;         % ty
                Y(gy+1, gx+1, ch+4) = log(w/anchorBoxes(a,1)); % tw
                Y(gy+1, gx+1, ch+5) = log(h/anchorBoxes(a,2)); % th
                nPos = nPos + 1;  anchorCnt(a) = anchorCnt(a) + 1;
            end
        end
        % 第二遍：ignore 区（该锚框与某个 GT 的 IoU>0.4 但未被分配为正样本的格）
        for k = 1:size(b, 1)
            x = b(k,1); y = b(k,2); w = b(k,3); h = b(k,4);
            for a = 1:numA
                aw = anchorBoxes(a,1);  ah = anchorBoxes(a,2);
                halfc = ceil(aw/(2*cellW)) + 1;
                halfr = ceil(ah/(2*cellH)) + 1;
                gx0 = floor((x+w/2)/cellW);  gy0 = floor((y+h/2)/cellH);
                for yy = max(0, gy0-halfr):min(Gh-1, gy0+halfr)
                    for xx = max(0, gx0-halfc):min(Gw-1, gx0+halfc)
                        if Y(yy+1, xx+1, (a-1)*5+1) ~= 0, continue; end
                        ccx = (xx+0.5)*cellW;  ccy = (yy+0.5)*cellH;
                        if box_iou([ccx-aw/2, ccy-ah/2, aw, ah], [x y w h]) > 0.4
                            Y(yy+1, xx+1, (a-1)*5+1) = -1;      % 忽略
                            nIgn = nIgn + 1;
                        end
                    end
                end
            end
        end
    end
    resp4(:,:,:,i) = Y;
end
fprintf('目标编码：正样本单元 %d，忽略单元 %d；各锚命中 %s\n', ...
    nPos, nIgn, mat2str(anchorCnt));

%% ---- 网络（全标准层 + 自定义加权损失）----
layers = [
    imageInputLayer([inputH inputW 3], 'Name', 'input', 'Normalization', 'none')
    convolution2dLayer([3 3],  8, 'Padding', 'same', 'Name', 'conv1')
    batchNormalizationLayer('Name', 'bn1')
    reluLayer('Name', 'relu1')
    convolution2dLayer([3 3], 16, 'Stride', 2, 'Padding', [1 1 1 1], 'Name', 'conv2')
    batchNormalizationLayer('Name', 'bn2')
    reluLayer('Name', 'relu2')
    convolution2dLayer([3 3], 32, 'Stride', 2, 'Padding', [1 1 1 1], 'Name', 'conv3')
    batchNormalizationLayer('Name', 'bn3')
    reluLayer('Name', 'relu3')
    convolution2dLayer([3 3], 32, 'Padding', 'same', 'Name', 'conv4')
    batchNormalizationLayer('Name', 'bn4')
    reluLayer('Name', 'relu4')
    convolution2dLayer([1 1], 15, 'Name', 'head_conv')      % 3 锚 × [to tx ty tw th]
    yoloLossLayer('loss')                                    % 加权回归损失
    ];
lgraph = layerGraph(layers);

%% ---- 数据流（图片 + 目标数组成对）----
imds = imageDatastore(imgs, 'ReadFcn', @(f) imresize(imread(f), [inputH inputW]));
ads  = arrayDatastore(resp4, 'IterationDimension', 4);
ds   = combine(imds, ads);

%% ---- 训练 ----
options = trainingOptions('sgdm', ...
    'MiniBatchSize', miniBatch, 'MaxEpochs', maxEpochs, ...
    'InitialLearnRate', lr0, 'LearnRateSchedule', 'piecewise', ...
    'LearnRateDropPeriod', 15, 'LearnRateDropFactor', 0.5, ...
    'Momentum', 0.9, 'Shuffle', 'every-epoch', ...
    'Plots', 'training-progress', 'Verbose', true);
net = trainNetwork(ds, lgraph, options);

save(fullfile(root, 'detector_net.mat'), 'net', 'anchorBoxes', 'inputH', 'inputW', 'numCal');
fprintf('训练完成，已保存 detector_net.mat（下一步跑 step3）\n');

%% ---- 辅助函数 ----
function C = kmeans_anchors(sz, k, iters)
% 对数空间 k-means 估计锚框（无需任何工具箱）
    if isempty(sz)
        C = [16 18; 28 32; 48 54];  return;
    end
    X = log(max(sz, 2));
    n = size(X, 1);
    k = min(k, n);
    rng(0);
    C = X(randperm(n, k), :);
    for it = 1:iters
        d2 = zeros(n, k);
        for j = 1:k
            d2(:, j) = sum((X - C(j, :)).^2, 2);
        end
        [~, lab] = min(d2, [], 2);
        for j = 1:k
            if any(lab == j), C(j, :) = mean(X(lab == j, :), 1); end
        end
    end
    C = sortrows(exp(C), 1);
    C = max(C, 4);
end

function v = box_iou(a, b)
    x1 = max(a(1), b(1));              y1 = max(a(2), b(2));
    x2 = min(a(1)+a(3), b(1)+b(3));    y2 = min(a(2)+a(4), b(2)+b(4));
    inter = max(0, x2-x1) * max(0, y2-y1);
    v = inter / (a(3)*a(4) + b(3)*b(4) - inter + eps);
end

function v = qval(vec, p)
    vec = sort(vec(:));
    if isempty(vec), v = NaN; return; end
    v = vec(min(numel(vec), max(1, round(p*numel(vec)))));
end
