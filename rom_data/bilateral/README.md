# 双边滤波查表文件（ROM IP 初始化）

给 `hdl_source/bilateral_filter_3x3.v` 里的 ROM IP 用的初始化表。
ROM IP 的行为级替身/规格见 `hdl_source/bilateral_rom_ip.v`。

## 文件
| 文件 | 格式 | 内容 | 对应 ROM IP |
|---|---|---|---|
| `bilateral_range.hex` | 256 行 × 2 位十六进制 | 距离核 `w_r(d) = round(255·exp(-d²/(2σr²)))`，`d=0..255`，`σr=35` | `bilateral_rom_range`（8bit × 256） |
| `bilateral_recip.hex` | 2048 行 × 4 位十六进制 | 倒数表 `recip[d] = round(65536/d)`（Q0.16），`d=0..2047`，`recip[0]=0` | `bilateral_rom_recip`（16bit × 2048） |

## 两条使用路线（与 `cnn_rom_ip.v` 一致）
1. **官方 IP 路线（推荐）**：在 TD IP Generator 里生成两个 ROM IP，模块名/端口必须和
   `bilateral_rom_ip.v` 里的替身完全一致（`doa`/`addra`/`clka`，同步读），INIT_FILE 指向上面的 .hex
   （或转成 TD 支持的 .mih/.dath）。综合时定义 `TD_SYN`，`bilateral_rom_ip.v` 的替身被 `ifndef` 排除，
   TD 用官方 IP。
   - `bilateral_rom_range`：8bit × 256，例化 9 次（3×3 窗口每个像素一路）
   - `bilateral_rom_recip`：16bit × 2048，例化 1 次
2. **行为级路线**：不加 IP，`bilateral_rom_ip.v` 里的 `initial $readmemh` 替身直接用于
   仿真/综合；综合时 TD 会把初始化的 `reg` 数组推断为块 ROM（单端口，range 9 路会各占一块）。

## 重新生成（调 σr）
距离核 σr 决定"多大的亮度差算边缘"：σr 越小越保边缘、去噪越弱；越大越平滑。
当前默认 **σr = 35**。要调，改 `$sigma_r` 后重跑（PowerShell）：

```powershell
$sigma_r = 35
$dir = 'rom_data\bilateral'
$range = New-Object System.Collections.Generic.List[string]
for ($d = 0; $d -lt 256; $d++) {
  $v = [int][Math]::Round(255.0 * [Math]::Exp(-($d*$d) / (2.0*$sigma_r*$sigma_r)))
  if ($v -gt 255) { $v = 255 }
  $range.Add(('{0:X2}' -f $v))
}
Set-Content -Path "$dir\bilateral_range.hex" -Value $range -Encoding ASCII

$recip = New-Object System.Collections.Generic.List[string]
for ($d = 0; $d -lt 2048; $d++) {
  $v = if ($d -eq 0) { 0 } else { [int][Math]::Round(65536.0 / $d) }
  if ($v -gt 65535) { $v = 65535 }
  $recip.Add(('{0:X4}' -f $v))
}
Set-Content -Path "$dir\bilateral_recip.hex" -Value $recip -Encoding ASCII
```

## 综合/仿真注意
- 仿真（ModelSim）：把 `bilateral_range.hex` / `bilateral_recip.hex` 放到仿真工作目录
  （`bilateral_rom_ip.v` 里是相对路径 `$readmemh`）。
- 空间核已固化在模块里（二项式 [1 2 1; 2 4 2; 1 2 1]，中心/边/角权重通过右移实现），不需要空间权重表。
- 行缓存（2×1280×8）走 `(* ram_style="block" *)`，TD 自动 BRAM，不用管。
