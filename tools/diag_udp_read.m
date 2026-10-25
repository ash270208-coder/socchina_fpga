function diag_udp_read
% 诊断 MATLAB udpport 的 read 到底怎么读包：打印连续 10 个 read 的长度和 seq
u = udpport('datagram', 'LocalPort', 6666, 'Timeout', 5);

fprintf('=== 连续 read(u,1402) 10 次 ===\n');
for k = 1:10
    r = read(u, 1402, 'uint8');
    if isa(r, 'udpport.datagram.Datagram')
        pkt = r.Data;
    else
        pkt = r;
    end
    pkt = pkt(:);
    if numel(pkt) >= 2
        seq = double(pkt(1))*256 + double(pkt(2));
        fprintf('第%2d次: len=%5d  seq=%2d  (前4字节 %02x %02x %02x %02x)\n', ...
            k, numel(pkt), seq, pkt(1), pkt(2), pkt(3), pkt(4));
    else
        fprintf('第%2d次: len=%d\n', k, numel(pkt));
    end
end

fprintf('\n=== 连续 read(u,1050) 10 次 ===\n');
for k = 1:10
    r = read(u, 1050, 'uint8');
    if isa(r, 'udpport.datagram.Datagram')
        pkt = r.Data;
    else
        pkt = r;
    end
    pkt = pkt(:);
    if numel(pkt) >= 2
        seq = double(pkt(1))*256 + double(pkt(2));
        fprintf('第%2d次: len=%5d  seq=%2d  (前4字节 %02x %02x %02x %02x)\n', ...
            k, numel(pkt), seq, pkt(1), pkt(2), pkt(3), pkt(4));
    else
        fprintf('第%2d次: len=%d\n', k, numel(pkt));
    end
end
end
