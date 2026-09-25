function export_fpga_consts()
% export_fpga_consts.m —— 从 out/net_params.mat 提取全精度 mOut / 锚框，
% 生成 FPGA 定点常数 (cnn_params.vh) 与 8 通道/字打包权重 (w_*_packed.mem)。
% 只读 .mat，不依赖训练图片，可随时重跑。
% 输出: out/cnn_params.vh, out/w_conv1..4_packed.mem, out/w_head_packed.mem
root = fileparts(mfilename('fullpath'));
P = load(fullfile(root,'out','net_params.mat'), 'params','anchors','lut_exp'); %#ok<NASGU>

%% ---- cnn_params.vh：Q32 常数 + 锚框 Q12 ----
fid = fopen(fullfile(root,'out','cnn_params.vh'),'w','n','UTF-8');
fprintf(fid,'// 由 export_fpga_consts.m 自动生成 —— Verilog 定点常数，勿手改\n');
fprintf(fid,'// 用法: real = (acc * `MOUT_Q32_xxx + 32''sd2147483648) >>> 32   (acc>=0)\n');
fprintf(fid,'//       real = (acc * `MOUT_Q32_xxx - 32''sd2147483648) >>> 32   (acc<0)\n');
fprintf(fid,'`ifndef CNN_PARAMS_VH\n`define CNN_PARAMS_VH\n\n');
for k = 1:numel(P.params)
    q32 = round(P.params(k).mOut * 2^32);
    if q32 >= 2^31
        error('Q32 常数溢出 (>=2^31): %s = %d', P.params(k).name, q32);
    end
    fprintf(fid,'`define MOUT_Q32_%s 32''d%d\n', upper(P.params(k).name), q32);
    fprintf('MOUT_Q32_%-10s = %d  (mOut = %.10e)\n', upper(P.params(k).name), q32, P.params(k).mOut);
end
% 检测头 Q12：head_q12 = round(acc*mOut*4096) => (acc * Q32*4096 ± 2^31) >>> 32
q12h = round(P.params(end).mOut * 4096 * 2^32);
if q12h >= 2^31
    error('head Q12 常数溢出: %d', q12h);
end
fprintf(fid,'`define MOUT_Q32_HEAD_Q12 32''d%d\n', q12h);
fprintf('MOUT_Q32_HEAD_Q12 = %d\n', q12h);
fprintf(fid,'\n// 锚框 Q12（值 = 原始值 x 4096）\n');
for a = 1:size(P.anchors,1)
    fprintf(fid,'`define ANCHOR%d_W_Q12 18''d%d\n', a, round(P.anchors(a,1)*4096));
    fprintf(fid,'`define ANCHOR%d_H_Q12 18''d%d\n', a, round(P.anchors(a,2)*4096));
    fprintf('ANCHOR%d = [%d %d] Q12  (原始 [%.6f %.6f])\n', a, ...
        round(P.anchors(a,1)*4096), round(P.anchors(a,2)*4096), P.anchors(a,:));
end
fprintf(fid,'\n`endif\n');
fclose(fid);
fprintf('已写出 out/cnn_params.vh\n');

%% ---- 打包权重：8 输出通道/字，64bit，每行 16 hex ----
for k = 1:numel(P.params)
    Wq = double(P.params(k).Wq);
    [Kk,~,Ci,Co] = size(Wq);
    TAPS  = Kk*Kk*Ci;
    Wt    = reshape(Wq, TAPS, Co);          % [tap, cout]
    numGrp = ceil(Co/8);
    words  = zeros(TAPS*numGrp, 1, 'uint64');
    for t = 0:TAPS-1
        for g = 0:numGrp-1
            v = uint64(0);
            for c = 0:7
                if g*8+c < Co
                    v = bitor(v, bitshift(uint64(typecast(int8(Wt(t+1, g*8+c+1)), 'uint8')), 8*c));
                end
            end
            words(t*numGrp+g+1) = v;
        end
    end
    tag = lower(P.params(k).name);
    if strcmp(tag, 'head_conv'), tag = 'head'; end
    f = fopen(fullfile(root,'out',sprintf('w_%s_packed.mem',tag)),'w');
    for i2 = 1:numel(words)
        b = typecast(words(i2), 'uint8');          % 小端字节: b(1)=LSB
        fprintf(f, '%s\n', sprintf('%02X', b(end:-1:1)));   % MSB 在前，16 hex/行
    end
    fclose(f);
    fprintf('w_%-10s packed: %4d 字 x 64bit（%d tap x %d 组）\n', tag, numel(words), TAPS, numGrp);
end
fprintf('export_fpga_consts: OK\n');
