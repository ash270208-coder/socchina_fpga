# ============================================================================
# 双边滤波查表生成脚本
# ----------------------------------------------------------------------------
# 作用: 生成 bilateral_range / bilateral_recip 两张查表的初始化文件
#        (.hex 给 ModelSim 仿真用, .dath 给安路 TD 综合的 ROM IP 用)
#
# 用法 (在 PowerShell 里):
#     cd D:\TD_project\lab_ex1_mipi_hdmi_SC500_720P+vpp\rom_data\bilateral
#     powershell -ExecutionPolicy Bypass -File .\gen_bilateral_lut.ps1
#   或 (装了 pwsh):
#     pwsh -File .\gen_bilateral_lut.ps1
#
# 要调保边缘强度: 改下面 $sigma_r (越小越保边缘/去噪越弱, 越大越平滑)
# ============================================================================

$sigma_r = 35

$dir = $PSScriptRoot   # 脚本所在目录, 即 rom_data\bilateral

# 1. 距离核 w_r(d) = round(255 * exp(-d^2 / (2*sigma_r^2))), d = 0..255
$range = New-Object System.Collections.Generic.List[string]
for ($d = 0; $d -lt 256; $d++) {
    $v = [int][Math]::Round(255.0 * [Math]::Exp(-($d * $d) / (2.0 * $sigma_r * $sigma_r)))
    if ($v -gt 255) { $v = 255 }
    $range.Add(('{0:X2}' -f $v))
}

# 2. 倒数表 recip[d] = round(65536 / d), Q0.16, d = 0..2047
$recip = New-Object System.Collections.Generic.List[string]
for ($d = 0; $d -lt 2048; $d++) {
    if ($d -eq 0) {
        $v = 0
    } else {
        $v = [int][Math]::Round(65536.0 / $d)
    }
    if ($v -gt 65535) { $v = 65535 }
    $recip.Add(('{0:X4}' -f $v))
}

# 写文件 (.hex 和 .dath 内容完全一样, 只是扩展名不同)
Set-Content -Path "$dir\bilateral_range.hex"  -Value $range -Encoding ASCII
Set-Content -Path "$dir\bilateral_recip.hex"  -Value $recip -Encoding ASCII
Set-Content -Path "$dir\bilateral_range.dath" -Value $range -Encoding ASCII
Set-Content -Path "$dir\bilateral_recip.dath" -Value $recip -Encoding ASCII

Write-Host "生成完毕 (sigma_r = $sigma_r):"
Write-Host "  bilateral_range.hex/.dath  -> $($range.Count) 行 (距离核 8bit x 256)"
Write-Host "  bilateral_recip.hex/.dath  -> $($recip.Count) 行 (倒数表 16bit x 2048)"
