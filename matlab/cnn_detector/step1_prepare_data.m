% step1_prepare_data.m —— 组装训练数据表（输出 training_data.mat）
% 这是脚本：点 Run 或输入 >> step1_prepare_data
% mode 三选一：
%   'A'  自采：data/images/ 下所有图（.jpg/.jpeg/.png/.bmp）都进数据集；
%        data/boxes.csv 每行：文件名,x,y,w,h（左上角，一张图多个框多行，表头自动跳过）；
%        boxes.csv 里没有的图 = 无人脸负样本。
%   'B'  WIDER FACE 子集：改下方 gtPath/imgRoot 为你的实际路径；
%        质量过滤（脸大小/模糊/姿态等）自动完成，见 parse_widerface.m。
%   'AB' 混合（推荐最终形态）：WIDER 提供多样性 + 自采提供域匹配/彩绘脸/负样本。
clc;
root = fileparts(mfilename('fullpath'));
outFile = fullfile(root, 'training_data.mat');
mode = 'B';                    % 'A' 自采 / 'B' WIDER / 'AB' 混合
                               % 拍好自采照片（含彩绘脸+负样本）后改成 'AB'

Tself = [];
Tw    = [];
switch mode
  case {'A', 'AB'}
    Tself = build_self_table(root);
end
switch mode
  case {'B', 'AB'}
    % 已按你机器上的实际路径填好（若移动了文件夹再改这里）
    gtPath  = 'E:\widerface\wider_face_split\wider_face_split\wider_face_train_bbx_gt.txt';
    imgRoot = 'E:\widerface\WIDER_train\WIDER_train\images';
    Tw = parse_widerface(gtPath, imgRoot, 3000);   % 取 3000 张（质量过滤后）
end
switch mode
  case 'A',  T = Tself;
  case 'B',  T = Tw;
  case 'AB', T = [Tself; Tw];
  otherwise, error('mode 只能为 A / B / AB');
end

save(outFile, 'T');
nWithFace = sum(cellfun(@(b) size(b,1) > 0, T.face));
nBoxes    = sum(cellfun(@(b) size(b,1), T.face));
fprintf('已保存 %s：共 %d 张图（%d 张有人脸，%d 张负样本），共 %d 个框\n', ...
    outFile, height(T), nWithFace, height(T) - nWithFace, nBoxes);
fprintf('提醒：涂颜料的人脸必须出现在训练集里——检测上限由数据覆盖决定。\n');

function T = build_self_table(root)
    imgDir = fullfile(root, 'data', 'images');
    if ~exist(imgDir, 'dir')
        error('请先创建目录 %s 并放入图片（mode A/AB 需要；纯 WIDER 训练请把 mode 改成 B）', imgDir);
    end
    exts = {'.jpg', '.jpeg', '.png', '.bmp'};
    d = dir(fullfile(imgDir, '*'));
    allImgs = string({d.name})';
    isImg = false(size(allImgs));
    for e = 1:numel(exts)
        isImg = isImg | endsWith(lower(allImgs), exts{e});
    end
    allImgs = allImgs(isImg);
    if isempty(allImgs)
        error('%s 里没有图片（支持 .jpg/.jpeg/.png/.bmp）', imgDir);
    end

    csvFile = fullfile(root, 'data', 'boxes.csv');
    map = containers.Map();
    if isfile(csvFile)
        [names, x, y, w, h] = read_boxes_csv(csvFile);
        names = regexprep(names, '.*[\\/]', '');       % CSV 里若带路径，取 basename
        uniq = unique(names, 'stable');
        for i = 1:numel(uniq)
            m = strcmp(names, uniq{i});
            map(char(uniq{i})) = [x(m) y(m) w(m) h(m)];
        end
        missing = setdiff(cellstr(uniq), cellstr(allImgs));
        if ~isempty(missing)
            warning('boxes.csv 里 %d 个文件在 images/ 下找不到，已忽略（如 %s）', ...
                    numel(missing), missing{1});
        end
    else
        warning('未找到 %s，全部图片按负样本（无人脸）处理', csvFile);
    end

    files = cellstr(fullfile(imgDir, allImgs));
    faces = cell(numel(allImgs), 1);
    for i = 1:numel(allImgs)
        if isKey(map, char(allImgs{i}))
            faces{i} = map(char(allImgs{i}));
        else
            faces{i} = zeros(0, 4);                   % 负样本：无框
        end
    end
    T = table(files, faces, 'VariableNames', {'imageFilename', 'face'});
end

function [names, x, y, w, h] = read_boxes_csv(f)
    c = readcell(f);
    if isempty(c), error('boxes.csv 是空的'); end
    % 自动跳过表头行：若第一行任一列不是数值（如 NAME,x,y,w,h / 文件名,x,y,w,h），视为表头
    firstRowNum = cellfun(@(e) isnumeric(e), c(1, :));
    if ~all(firstRowNum)
        fprintf('检测到表头行，已自动跳过：%s\n', strjoin(string(c(1, :)), ','));
        c(1, :) = [];
    end
    if size(c, 2) ~= 5
        error('boxes.csv 每行应为 5 列：文件名,x,y,w,h（当前是 %d 列）', size(c, 2));
    end
    names = string(c(:, 1));
    nums  = zeros(size(c, 1), 4);
    for j = 1:4
        col = c(:, j+1);
        ok  = cellfun(@(e) isnumeric(e) && isscalar(e), col);
        if ~all(ok)
            bad = find(~ok, 1);
            error('boxes.csv 第 %d 行第 %d 列不是数字（值: "%s"）。格式应为：文件名,x,y,w,h', ...
                  bad, j+1, string(col{bad}));
        end
        nums(:, j) = cell2mat(col);
    end
    x = nums(:,1); y = nums(:,2); w = nums(:,3); h = nums(:,4);
end
