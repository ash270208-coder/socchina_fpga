% step0_check_env.m —— 环境自检（脚本，点 Run 或输入 >> step0_check_env）
% 判据：关键函数在 = 工具箱在（这是最可靠的检查，工具箱名单 API 因版本而异只作参考）
fprintf('=== MATLAB 环境自检 ===\n');
v = ver('MATLAB');
fprintf('MATLAB %s %s\n', v.Version, v.Release);

% [1] 关键函数检查（权威）
fprintf('\n[1] 关键函数检查（函数在 = 对应工具箱在）\n');
funcs = {'yolov2Layers', 'trainYOLOv2ObjectDetector', 'boxLabelDatastore', ...
         'imageDatastore', 'trainNetwork', 'activations', 'fi', 'im2col', 'readcell'};
funcOk = true;
for i = 1:numel(funcs)
    has = ~isempty(which(funcs{i}));
    fprintf('  函数 %-28s : %s\n', funcs{i}, okstr(has));
    funcOk = funcOk && has;
end

% [2] 工具箱名检查（尽力而为：名单 API 读不到就以函数检查为准）
fprintf('\n[2] 工具箱检查\n');
tbxNames = list_toolbox_names();
proxies = {
    'Deep Learning Toolbox',   'trainNetwork';
    'Computer Vision Toolbox', 'trainYOLOv2ObjectDetector';
    'Image Processing Toolbox','im2col';
    'Fixed-Point Designer',    'fi';
    };
allOk = true;
for i = 1:size(proxies, 1)
    byName = any(strcmp(tbxNames, proxies{i, 1}));
    byFunc = ~isempty(which(proxies{i, 2}));
    ok = byName || byFunc;
    fprintf('  %-24s : %s%s\n', proxies{i, 1}, okstr(ok), note(byName, byFunc));
    allOk = allOk && ok;
end

fprintf('\n结果: %s\n', okstr(allOk && funcOk));
if ~(allOk && funcOk)
    fprintf(['缺失项安装方法：MATLAB 菜单「主页 → 附加功能 → 获取附加功能」搜索对应工具箱，' ...
             '用学校正版授权账号安装（Deep Learning / Computer Vision / Image Processing / ' ...
             'Fixed-Point Designer）。\n']);
else
    fprintf('环境就绪，可以运行 step1_prepare_data 了。\n');
end

function names = list_toolbox_names()
    names = {};
    try
        tbx = matlab.addons.toolbox.installedToolboxes;
        names = arrayfun(@(x) x.Name, tbx, 'UniformOutput', false);
    catch
        try
            A = matlab.addons.installedAddons;
            names = A.Name;
        catch
        end
    end
end

function s = note(byName, byFunc)
    if byName
        s = '';
    elseif byFunc
        s = '（名单未读到，按函数判定）';
    else
        s = '';
    end
end

function s = okstr(b)
    if b, s = 'OK'; else, s = '缺失!'; end
end
