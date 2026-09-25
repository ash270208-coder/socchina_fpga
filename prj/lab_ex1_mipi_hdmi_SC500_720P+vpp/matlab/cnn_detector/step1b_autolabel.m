% step1b_autolabel.m —— 半自动标框（不用手算坐标）
% 这是脚本：点 Run 或输入 >> step1b_autolabel
%
% 流程：
%   1) 自动：对 data/images/ 每张图跑 MATLAB 自带人脸检测器（vision.CascadeObjectDetector），
%      检出的脸自动写入 data/boxes.csv（坐标由程序生成，你不需要看坐标）；
%      涂颜料的脸大概率检不出 → 第 2 步手动补。
%   2) 手动补标（只补漏检的图，比如彩绘脸）：
%      a. 命令行输入 imageLabeler
%      b. 「Add Images」选 data/images/ 里漏检的图（本脚本末尾会列出名单）
%      c. 工具栏选矩形框，鼠标拖拽画框（坐标自动记录）
%      d. 「Export Labels → To Workspace」，变量名保持默认 gTruth
%      e. 运行：save(fullfile(fileparts(mfilename('fullpath')),'data','labels_manual.mat'),'gTruth')
%      f. 重跑本脚本 → 手动框覆盖同图自动框，合并写入 boxes.csv
clc;
root = fileparts(mfilename('fullpath'));
imgDir = fullfile(root, 'data', 'images');
outCsv = fullfile(root, 'data', 'boxes.csv');
manualFile = fullfile(root, 'data', 'labels_manual.mat');

%% 1) 自动检测
exts = {'.jpg', '.jpeg', '.png', '.bmp'};
d = dir(fullfile(imgDir, '*'));
imgs = string({d.name})';
isImg = false(size(imgs));
for e = 1:numel(exts)
    isImg = isImg | endsWith(lower(imgs), exts{e});
end
imgs = imgs(isImg);
if isempty(imgs), error('%s 里没有图片（先放图再跑本脚本）', imgDir); end

detector = vision.CascadeObjectDetector('FrontalFaceCART', 'MergeThreshold', 4);
map = containers.Map();
for i = 1:numel(imgs)
    I = imread(fullfile(imgDir, imgs{i}));
    b = detector(I);                         % [x y w h]，正是 boxes.csv 需要的格式
    if ~isempty(b), map(char(imgs{i})) = b; end
end
nAuto = numel(map);

%% 2) 合并手动补标（手动框覆盖同图的自动框）
if isfile(manualFile)
    M = load(manualFile);  g = M.gTruth;
    LD = g.LabelData;                        % 表：imageFilename + 每个标签类一列框
    lblCols = LD.Properties.VariableNames(2:end);
    nManual = 0;
    for i = 1:height(LD)
        [~, base, ext] = fileparts(char(LD.imageFilename{i}));
        key = [base ext];
        b = [];
        for c = 1:numel(lblCols)
            bb = LD.(lblCols{c}){i};
            if ~isempty(bb), b = [b; bb]; end %#ok<AGROW>
        end
        if ~isempty(b)
            map(key) = b;                    % 手动框覆盖自动框
            nManual = nManual + 1;
        end
    end
    fprintf('合并手动标注：%d 张图\n', nManual);
end

%% 3) 写 boxes.csv
keys = map.keys;
fid = fopen(outCsv, 'w');
fprintf(fid, '文件名,x,y,w,h\n');
nBox = 0;
for i = 1:numel(keys)
    b = map(keys{i});
    for r = 1:size(b, 1)
        fprintf(fid, '%s,%d,%d,%d,%d\n', keys{i}, ...
            round(b(r,1)), round(b(r,2)), round(b(r,3)), round(b(r,4)));
        nBox = nBox + 1;
    end
end
fclose(fid);
fprintf('写入 %s：%d 张图共 %d 个框（其中自动检出 %d 张）\n', outCsv, numel(keys), nBox, nAuto);

%% 4) 列出没检出的图（负样本不用管，漏掉的彩绘脸请手动补）
missed = setdiff(cellstr(imgs), keys);
if ~isempty(missed)
    fprintf('\n以下 %d 张图没检出脸（纯背景负样本忽略；是脸的话按文件头注释手动补标）：\n', numel(missed));
    for i = 1:numel(missed)
        fprintf('  %s\n', missed{i});
    end
end
