function boardA_recv_frame
% boardA_recv_frame.m —— 板A收图脚本（MATLAB 版）
%
% 用法：PC 网卡 192.168.240.2，防火墙放行 UDP 6666，MATLAB 运行 boardA_recv_frame
%
% ★ 关键（实测 2026-10-13）：
%   1. read(u,count,'uint8') 在 datagram 模式下会按"4x5 转置"顺序返回缓冲里的
%      数据报：0,5,10,15,1,6,11,16,... 一轮正好漏掉某些 seq。
%      所以**不能写"凑齐才退出"**，否则每个 Timeout 空等一次，看起来像死住。
%      这里改成：有上限地读，缺包补 0，照常出图。
%   2. 分包方案自动识别：
%        旧 bit: 20 包 = 19x1400 + 1048   (datagram 1402 / 1050)
%        新 bit: 24 包 = 24x1152          (datagram 1154，等长，修复11)

W = 128; H = 72;
FRAME = W * H * 3;                  % 27648

u = udpport('datagram', 'LocalPort', 6666, 'Timeout', 0.3);
fprintf('等待板子图像数据...\n');

% ---- 第一步：收集数据报（有上限，凑不齐也继续）----
PAY_FULL = []; PAY_LAST = []; NPKT = [];
pkts = {}; got = [];
MAXREAD = 80;
for k = 1:MAXREAD
    if ~isempty(got) && all(got), break; end
    r = read(u, 1200, 'uint8');
    if isa(r, 'udpport.datagram.Datagram')
        pkt = r.Data;
    else
        pkt = r;
    end
    pkt = pkt(:);
    if numel(pkt) < 2, continue; end

    % 首包决定分包方案
    if isempty(NPKT)
        if numel(pkt) >= 1402
            NPKT = 20; PAY_FULL = 1400; PAY_LAST = 1048;
            fprintf('  分包方案: 20 包 (19x1400 + 1048)\n');
        else
            NPKT = 24; PAY_FULL = 1152; PAY_LAST = 1152;
            fprintf('  分包方案: 24 包 (等长 1152)\n');
        end
        pkts = cell(1, NPKT);
        got  = false(1, NPKT);
    end

    s = double(pkt(1))*256 + double(pkt(2));
    if s < 0 || s >= NPKT || got(s+1), continue; end
    pkts{s+1} = pkt;
    got(s+1)  = true;
    fprintf('  收到 seq %2d (%4d 字节)  %d/%d\n', s, numel(pkt), sum(got), NPKT);
end

if isempty(NPKT)
    error('一个数据报都没收到——检查板子是否在发、防火墙是否放行 6666');
end

% ---- 第二步：按 seq 拼图（缺包补 0）----
img = zeros(FRAME, 1, 'uint8');
for s = 0:NPKT-1
    if ~got(s+1), continue; end
    pkt = pkts{s+1};
    n_img = PAY_FULL;
    if s == NPKT-1, n_img = PAY_LAST; end
    n_img = min(n_img, numel(pkt)-2);
    n_img = min(n_img, FRAME - s*PAY_FULL);
    img(s*PAY_FULL + (1:n_img)) = pkt(3 : 2+n_img);
end

fprintf('收齐 %d/%d 个包。\n', sum(got), NPKT);
if ~all(got)
    fprintf('缺 seq: %s（底部会有黑带，可重跑）\n', mat2str(find(~got)-1));
end

% ---- 第三步：重塑显示 ----
% ★ 帧相位错位已由 RTL 修复10（非采集帧清空 img_fifo）根治，
%   原始图就是正的，这里不再需要任何软件平移。
FIX_SHIFT = false;                  % 万一在旧 bit 上要临时补平移才改 true
rgb = reshape(img, [3, W, H]);
rgb = permute(rgb, [3, 2, 1]);
% ★ [修复12] 已进 RTL：pixel_to_bytes 现在按 R,G,B 输出，这里不用再换。
%   若跑的是未含修复12的旧 bit，把 CH_SWAP 改成 true（旧 bit 是 B,R,G 序）。
CH_SWAP = false;
if CH_SWAP
    rgb = rgb(:, :, [2 3 1]);
end
if FIX_SHIFT
    rgb = circshift(rgb, -7, 1);
    rgb = circshift(rgb, 40, 2);
end
imshow(rgb);
title(sprintf('板A 图像  %d x %d', W, H));
fprintf('已显示一帧 %d x %d 图像。\n', W, H);

% ---- 第四步：存盘，方便离线分析 ----
here = fileparts(mfilename('fullpath'));
if isempty(here), here = pwd; end
imwrite(rgb, fullfile(here, 'recv_raw.png'));
fid = fopen(fullfile(here, 'recv_raw.bin'), 'wb');
fwrite(fid, img, 'uint8');
fclose(fid);
fprintf('已存盘: recv_raw.png / recv_raw.bin\n');
end
