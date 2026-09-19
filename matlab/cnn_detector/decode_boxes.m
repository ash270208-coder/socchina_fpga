function [boxes, scores] = decode_boxes(head, anchors, inputH, inputW, use_lut, lut_exp)
% decode_boxes.m —— 检测头解码（与 Verilog 保持同一契约）
% head: [Gh Gw Cout]，Cout = numAnchors*5，每锚通道顺序 [to tx ty tw th]
%   score = clamp(to, 0, 1)——回归训练的目标就是 0/1，原始输出即分数（不套 sigmoid）
%   cx = (gx + clamp(tx,0,1))·cellW，cy = (gy + clamp(ty,0,1))·cellH
%   w = anchorW·exp(tw)，h = anchorH·exp(th)（exp 可选 LUT）
% 返回 [x y w h]（左上角，输入图坐标）+ scores；已按分数降序。
% use_lut = true 时用 step3 导出的 exp LUT（验证 Verilog 查表误差）。
    if nargin < 5, use_lut = false; end
    [Gh, Gw, Cout] = size(head);
    numA = size(anchors, 1);
    if Cout ~= 5 * numA
        error('检测头通道数应为 5×锚数（当前 %d，期望 %d）', Cout, 5 * numA);
    end
    if use_lut
        ex = @(x) lut_eval(lut_exp, x, 4, 128, 2048);
    else
        ex = @exp;
    end

    [gy, gx] = ndgrid(0:Gh-1, 0:Gw-1);
    cellW = inputW / Gw;   cellH = inputH / Gh;

    boxes  = zeros(0, 4);
    scores = zeros(0, 1);
    for a = 1:numA
        ch = (a-1)*5 + (1:5);
        p  = head(:, :, ch);
        to = min(max(p(:,:,1), 0), 1);          % 分数 = 原始对象分截断
        tx = min(max(p(:,:,2), 0), 1);          % 格内偏移截断
        ty = min(max(p(:,:,3), 0), 1);
        w  = anchors(a,1) .* ex(p(:,:,4));
        h  = anchors(a,2) .* ex(p(:,:,5));
        cx = (gx + tx) * cellW;   cy = (gy + ty) * cellH;
        x1 = cx - w/2;            y1 = cy - h/2;
        boxes  = [boxes;  x1(:) y1(:) w(:) h(:)]; %#ok<AGROW>
        scores = [scores; to(:)];                  %#ok<AGROW>
    end

    % 后处理：与 FPGA 后端策略一致（阈值 + 每帧只留最高分 1 框；
    % 板级再叠加时域确认）。回归对象分偏低，阈值 0.15（可按实测调）。
    keep = scores >= 0.15;
    boxes = boxes(keep, :);  scores = scores(keep);
    [scores, ord] = sort(scores, 'descend');
    boxes = boxes(ord, :);
    if size(boxes, 1) > 1
        boxes = boxes(1, :);  scores = scores(1);
    end
    if ~isempty(boxes)
        boxes(:,1) = max(0, min(inputW, boxes(:,1)));
        boxes(:,2) = max(0, min(inputH, boxes(:,2)));
    end
end

function y = lut_eval(lut, x, range, scale, q)
    idx = round((x + range) * scale) + 1;
    idx = max(1, min(numel(lut), idx));
    y = double(lut(idx)) / q;
end
