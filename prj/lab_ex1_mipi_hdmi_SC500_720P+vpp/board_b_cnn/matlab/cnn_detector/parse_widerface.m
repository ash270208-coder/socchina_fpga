function T = parse_widerface(gtPath, imageRoot, maxImages, opts)
% parse_widerface.m —— 解析 WIDER FACE 标注文本（带自动质量过滤，不用手动挑图）
% gtPath    : wider_face_train_bbx_gt.txt 路径
% imageRoot : WIDER_train/images 目录
% maxImages : 最多取多少张（0 = 全部）
% opts（可选结构体，缺省用默认值）：
%   minFaceRatio / maxFaceRatio : 框宽/图宽 保留范围，默认 0.08 / 0.6
%       （对应缩放到 128 宽后脸宽 10~77px，正好落在锚框 12~90px 覆盖内）
%   maxBlur    : 丢弃 blur>maxBlur 的框，默认 1（0=清晰 1=轻微 2=严重）
%   dropInvalid: 丢弃 invalid=1 的框，默认 true
%   maxPose    : 丢弃 pose>maxPose 的框，默认 1（0=正脸 1=偏 2=夸张姿态）
%   maxIllum   : 丢弃 illumination>maxIllum 的框，默认 1（都保留：暗光样本对 SC500 有用）
%   maxOccl    : 丢弃 occlusion>maxOccl 的框，默认 1（0=无 1=部分 2=重度）
% 返回 table：imageFilename (char) / face ([M 4] double, [x y w h])
    if nargin < 3, maxImages = 0; end
    if nargin < 4, opts = struct(); end
    def = struct('minFaceRatio', 0.08, 'maxFaceRatio', 0.6, ...
                 'maxBlur', 1, 'dropInvalid', true, ...
                 'maxPose', 1, 'maxIllum', 1, 'maxOccl', 1);
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}), opts.(fn{i}) = def.(fn{i}); end
    end

    fid = fopen(gtPath, 'r');
    if fid < 0, error('无法打开标注文件: %s（路径不存在或没有权限）', gtPath); end
    dinfo = dir(gtPath);
    if isempty(dinfo) || dinfo.bytes == 0
        fclose(fid);
        error('标注文件 %s 是空文件（0 字节）。请确认下载的是 wider_face_train_bbx_gt.txt，而不是 .zip 压缩包', gtPath);
    end

    files = {}; faces = {};
    nImgRead = 0; nBoxRaw = 0; nBoxKeep = 0; nSkipMiss = 0;
    nHeader = 0; nLines = 0;
    while ~feof(fid)
        line = strtrim(fgetl(fid));
        nLines = nLines + 1;
        if isempty(line), continue; end
        % 兼容两种标注格式：
        %   新版："# 0--Parade/xxx.jpg"（带 # 前缀）
        %   旧版（官方原始 txt）："0--Parade/xxx.jpg"（无 # 前缀）
        if line(1) == '#'
            rel = strtrim(line(2:end));
        elseif ~isempty(regexpi(line, '\.jpg', 'once'))
            rel = line;
        else
            continue;                        % 框数量行 / 坐标行，跳过
        end
        nHeader = nHeader + 1;
        cntLine = strtrim(fgetl(fid));
        if isempty(cntLine), break; end
        nbox = str2double(cntLine);
        b = zeros(nbox, 4);   attr = zeros(nbox, 6);
        for k = 1:nbox
            d = sscanf(fgetl(fid), '%f');
            b(k, :) = d(1:4);
            if numel(d) >= 10, attr(k, :) = d(5:10); end
        end
        nImgRead = nImgRead + 1;
        nBoxRaw  = nBoxRaw + nbox;
        % 图宽（imfinfo 只读文件头，不加载整图）
        try
            info = imfinfo(fullfile(imageRoot, rel));
            imgW = info(1).Width;
        catch
            nSkipMiss = nSkipMiss + 1;
            continue;
        end
        ratio = b(:,3) ./ imgW;
        % 属性列：1=blur 2=expression 3=illumination 4=invalid 5=occlusion 6=pose
        keep = b(:,3) >= 8 & ...
               ratio >= opts.minFaceRatio & ratio <= opts.maxFaceRatio & ...
               attr(:,1) <= opts.maxBlur   & ...
               attr(:,6) <= opts.maxPose   & ...
               attr(:,3) <= opts.maxIllum  & ...
               attr(:,5) <= opts.maxOccl;
        if opts.dropInvalid
            keep = keep & (attr(:,4) == 0);
        end
        b = b(keep, :);
        nBoxKeep = nBoxKeep + sum(keep);
        if isempty(b), continue; end
        files{end+1} = fullfile(imageRoot, rel); %#ok<AGROW>
        faces{end+1} = b;                        %#ok<AGROW>
        if maxImages > 0 && numel(files) >= maxImages, break; end
    end
    fclose(fid);
    if nHeader == 0
        error(['没有在 %s 中找到任何 "#..." 图片行（共读 %d 行）。可能原因：\n' ...
               '  1) gtPath 指向了 .zip 压缩包本身（请先解压出 .txt 再指向它）；\n' ...
               '  2) 文件编码不是 UTF-8/ASCII（如 UTF-16，请用记事本打开后"另存为"，编码选 UTF-8）；\n' ...
               '  3) 下载的不是训练集标注（比如下成了验证集或空文件）。'], gtPath, nLines);
    end
    T = table(files', faces', 'VariableNames', {'imageFilename', 'face'});
    fprintf('WIDER 解析完成：读图 %d 张，取 %d 张（保留 %d 个框 / 原始 %d 个框）', ...
        nImgRead, height(T), nBoxKeep, nBoxRaw);
    if nSkipMiss > 0
        fprintf('；%d 张图片文件缺失已跳过', nSkipMiss);
    end
    fprintf('\n');
end
