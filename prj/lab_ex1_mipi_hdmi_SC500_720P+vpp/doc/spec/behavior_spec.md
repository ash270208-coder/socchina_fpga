# Color_Quantize Behavior Specification

## Requirement Summary

Color_Quantize is a chroma quantization submodule for the 2026 FPGA Competition Topic 2 "Cartoon-style Image Processing" (edge extraction + region filling). It performs per-channel bit truncation on RGB888 pixel data, retaining the upper QUANT_BITS bits and zero-padding the lower bits to create a posterization / color-blocking effect (quantization color banding).

## Public Interface

| Port Name   | Direction | Width | Active Level | Description                                  |
|-------------|-----------|-------|--------------|----------------------------------------------|
| I_clk       | input     | 1     | rising edge  | System clock                                 |
| I_rst_n     | input     | 1     | low          | Asynchronous active-low reset                |
| I_tlast     | input     | 1     | high         | AXI-Stream TLAST (end of line/frame)         |
| I_tuser     | input     | 1     | high         | AXI-Stream TUSER (start of frame)            |
| I_tdata     | input     | 24    | high         | Packed RGB888: R[23:16], G[15:8], B[7:0]    |
| I_tvalid    | input     | 1     | high         | AXI-Stream TVALID                            |
| O_tlast     | output    | 1     | high         | Delayed TLAST (aligned to output data)       |
| O_tuser     | output    | 1     | high         | Delayed TUSER (aligned to output data)       |
| O_tdata     | output    | 24    | high         | Quantized RGB888: R[23:16], G[15:8], B[7:0] |
| O_tvalid    | output    | 1     | high         | Delayed TVALID (aligned to output data)      |

## Parameters and Defaults

| Parameter   | Default | Range    | Description                                      |
|-------------|---------|----------|--------------------------------------------------|
| QUANT_BITS  | 4       | 1 to 8   | Number of high bits to retain per channel. Clamped to [1,8] via localparam KEEP_BITS. |

- KEEP_BITS = clamped(QUANT_BITS, 1, 8)
- ZERO_BITS = 8 - KEEP_BITS (number of low bits zeroed out)

## Clocking and Reset

- Single clock domain: I_clk (rising edge).
- Asynchronous active-low reset (I_rst_n).
- All pipeline registers and control shift registers reset to 0.
- No clock-domain crossing; purely synchronous within one clock domain.

## Functional Behavior

### Per-Pixel Quantization

For each valid input pixel (I_tvalid = 1):

1. Extract R, G, B channels from I_tdata[23:0]:
   - in_r = I_tdata[23:16]
   - in_g = I_tdata[15:8]
   - in_b = I_tdata[7:0]

2. Quantize each channel independently:
   - Keep the upper KEEP_BITS bits (most significant bits).
   - Zero-pad the lower ZERO_BITS bits.
   - Formula: `out = {in[7 : 8-KEEP_BITS], {ZERO_BITS{1'b0}}}`

3. Pack the three quantized channels back into 24-bit output:
   - O_tdata = {quant_r, quant_g, quant_b}

### Pipeline Stages

| Stage | Description                        | Latency |
|-------|------------------------------------|---------|
| 1     | Quantization: truncate + zero-pad  | 1 cycle |
| 2     | Output register: pack and drive    | 1 cycle |
| Total | End-to-end pipeline latency        | 2 cycles|

### Control Signal Alignment

- A 2-bit shift register (`tvalid_shift`, `tlast_shift`, `tuser_shift`) delays control signals by exactly 2 clock cycles.
- Each cycle, the shift register shifts in the current input signal and the MSB drives the corresponding output.
- On reset, all shift registers clear to 0, ensuring no spurious output pulses.

### Example: QUANT_BITS = 4

Input byte:  `8'b1011_0110` (0xB6 = 182)
Keep top 4:  `1011`
Zero low 4:  `1011_0000` (0xB0 = 176)
Quantization step size: 16 (= 2^ZERO_BITS = 2^4)

Input byte:  `8'b0101_1111` (0x5F = 95)
Keep top 4:  `0101`
Zero low 4:  `0101_0000` (0x50 = 80)

### Example: QUANT_BITS = 8

No quantization occurs. KEEP_BITS = 8, ZERO_BITS = 0. Output equals input with 2-cycle latency.

### Example: QUANT_BITS = 1

Maximum posterization. Each channel has only 2 levels: 0x00 or 0x80.

## Timing, Latency, and Throughput

- **Latency**: 2 clock cycles from input to output (input sample -> quantize register -> output register).
- **Throughput**: 1 pixel per clock cycle (fully pipelined, no stalls).
- **No backpressure**: The module does not generate or consume O_tready. It processes every cycle where I_tvalid is asserted. This matches the style of Sobel_edge.v which also omits tready.

## Assumptions and Chosen Defaults

1. The input is a continuous AXI-Stream of RGB888 pixels, one pixel per clock when I_tvalid is high.
2. No backpressure mechanism is needed (consistent with Sobel_edge.v style).
3. QUANT_BITS is a static parameter set at elaboration time, not a runtime register.
4. Parameter clamping via localparam ensures synthesis safety even with out-of-range parameter values.
5. The module operates independently on each color channel (no cross-channel interaction).
6. No rounding is applied; truncation (floor) is used for simplicity and hardware efficiency.

## Edge Cases and Error Handling

- **QUANT_BITS = 8**: ZERO_BITS = 0, the concatenation `{in[7:0], {0{1'b0}}}` produces the original input. No quantization effect.
- **QUANT_BITS = 1**: Maximum posterization, only the MSB is kept. Each channel has 2 levels.
- **QUANT_BITS > 8 or < 1**: Clamped by localparam KEEP_BITS to the range [1, 8].
- **Reset during active stream**: All pipeline registers and shift registers clear. Output returns to zero. The first 2 valid pixels after reset de-assertion will appear at the output after 2 cycles.
- **Back-to-back valid inputs**: The pipeline supports continuous 1-pixel-per-clock throughput with no gaps.

## Synthesis Notes

- All logic is purely combinational (bit slicing, concatenation) plus registers. No multipliers, dividers, or RAMs.
- Estimated resource usage: 48 flip-flops (3x8 quantize + 24 output + 6 shift register bits) + 0 LUTs for the quantize operation (pure wiring).
- The `timescale 1ns / 1ps` directive matches the project convention.
- Synthesis tool will optimize the bit-slice operations into direct wire routing.

## Verification Plan

1. **Functional correctness**: Feed known RGB patterns and verify output matches expected truncated values for each QUANT_BITS setting.
2. **Pipeline alignment**: Verify O_tvalid, O_tlast, O_tuser are exactly 2 cycles delayed from their respective inputs.
3. **Reset behavior**: Assert reset mid-stream, verify all outputs go to 0 and pipeline recovers cleanly.
4. **Parameter sweep**: Test QUANT_BITS = 1, 2, 3, 4, 6, 8 to confirm correct truncation width.
5. **Boundary values**: Test all-zeros (0x000000) and all-ones (0xFFFFFF) input.
6. **Continuous stream**: Feed a full frame (e.g., 256x256) and verify no pixel is dropped or duplicated.
7. **Control signal edge cases**: Verify tlast/tuser at frame boundaries propagate correctly through the 2-stage pipeline.

## Acceptance Criteria

- All outputs are stable and valid when O_tvalid is asserted.
- Output data matches the truncation formula for every input pixel.
- Control signals (tlast, tuser, tvalid) are aligned to output data within +/-0 cycles (exact 2-cycle delay).
- No combinational loops, no inferred latches.
- Synthesizable with zero warnings in the target FPGA toolchain.
- No stubs, TODOs, or incomplete logic.

---

# Cartoon_Blend Behavior Specification

## Requirement Summary

Cartoon_Blend 是 2026 嵌赛 FPGA 选题二"卡通化图像风格化处理"的合成阶段模块。它将 Sobel 边缘检测的二值 mask（1-bit 标志）叠加到色块化（低位量化）的 RGB888 彩色像素流上：边缘位置输出纯黑像素形成描边效果，非边缘位置透传原始彩色像素，最终形成卡通黑描边风格化图像。

## Public Interface

| 端口名          | 方向   | 位宽  | 有效电平 | 描述                                    |
|----------------|--------|-------|---------|----------------------------------------|
| I_clk          | input  | 1     | -       | 系统时钟（组合逻辑模块，实际不使用时钟沿）  |
| I_rst_n        | input  | 1     | 低有效   | 异步复位（组合逻辑模块，实际不使用复位）    |
| I_tlast        | input  | 1     | 高有效   | AXI-Stream 行结束标志，直接透传          |
| I_tuser        | input  | 1     | 高有效   | AXI-Stream 帧起始标志，直接透传          |
| I_color_tdata  | input  | 24    | -       | 上游 Color_Quantize 输出的量化 RGB888 像素 [23:16]=R, [15:8]=G, [7:0]=B |
| I_edge_flag    | input  | 1     | 高有效   | 上游 Sobel_edge 输出的边缘二值标志，1=边缘，0=非边缘 |
| I_tvalid       | input  | 1     | 高有效   | AXI-Stream 数据有效标志，直接透传        |
| O_tlast        | output | 1     | 高有效   | 透传 I_tlast                            |
| O_tuser        | output | 1     | 高有效   | 透传 I_tuser                            |
| O_tdata        | output | 24    | -       | 合成后的 RGB888 像素输出                 |
| O_tvalid       | output | 1     | 高有效   | 透传 I_tvalid                           |

## Parameters and Defaults

| 参数名      | 默认值 | 描述           |
|------------|--------|---------------|
| IMG_WIDTH  | 1024   | 图像宽度（像素）|
| IMG_HEIGHT | 600    | 图像高度（像素）|

> 注：IMG_WIDTH / IMG_HEIGHT 保留为参数以与项目其他模块保持接口一致，本模块内部未使用。

## Clocking and Reset

- 本模块为纯组合逻辑，无内部寄存器，不使用时钟沿和复位。
- I_clk 和 I_rst_n 端口保留以保持与项目其他模块的接口一致性，便于上层 top 统一例化。

## Functional Behavior

### 像素合成规则（逐拍组合逻辑）

对于每一个有效输入拍（I_tvalid=1 时）：

1. **边缘像素**（I_edge_flag = 1）：
   - O_tdata = 24'h000000（纯黑像素，R=0, G=0, B=0）
   - 形成卡通黑描边效果

2. **非边缘像素**（I_edge_flag = 0）：
   - O_tdata = I_color_tdata（直接透传上游量化后的彩色像素）

### 控制信号透传

- O_tvalid = I_tvalid（零延迟透传）
- O_tlast = I_tlast（零延迟透传）
- O_tuser = I_tuser（零延迟透传）

### 输入对齐约束

- I_color_tdata 与 I_edge_flag 必须在同一拍到达且对齐到同一像素位置。
- 对齐由上层 top 模块通过延时链保证（Color_Quantize 与 Sobel_edge 的流水线级数不同，需要在 top 中对齐）。
- 本模块不承担任何对齐职责。

## Timing, Latency, and Throughput

- **延迟**：0 拍（纯组合逻辑，无流水线延迟）
- **吞吐**：每时钟周期处理 1 个像素
- **组合逻辑深度**：1 级 2-to-1 MUX（从输入到输出仅经过一个选择器）

## Assumptions and Chosen Defaults

1. 输入对齐已由上层保证：I_color_tdata 和 I_edge_flag 在同一拍对应同一像素位置。
2. I_edge_flag 为单比特信号：1 表示边缘，0 表示非边缘。上层 Sobel_edge 输出为 8-bit（0xFF/0x00），需由 top 取其最高位或最低位作为 I_edge_flag 输入。
3. 边缘像素统一输出纯黑（24'h000000），不做边缘颜色可配置。
4. 不包含反压（tready）端口——与 Sobel_edge.v 和 Color_Quantize.v 保持一致风格，视频流为单向推送模型。

## Edge Cases and Error Handling

1. **复位期间**：由于纯组合逻辑，输出直接反映输入状态，无复位行为。若输入在复位期间为不确定态，输出也为不确定态——由上层保证复位期间输入为已知值。
2. **I_tvalid=0 期间**：输出 O_tvalid=0，O_tdata 仍有组合逻辑值但下游不应采样。
3. **图像边界像素**：Sobel 边缘检测在图像边界（前两行、前两列）强制输出非边缘（0x00），这些位置本模块正常透传彩色像素，符合预期。

## Synthesis Notes

- 纯组合逻辑模块，综合后无寄存器、无触发器。
- I_clk 和 I_rst_n 虽在端口声明中，但因内部未使用，综合工具会自动优化掉。
- 关键路径：I_edge_flag 到 O_tdata 的 2-to-1 MUX，延迟极小，不会成为时序瓶颈。
- 无 latch、无 incomplete case、无 incomplete if-else。

## Verification Plan

1. **边缘像素测试**：I_edge_flag=1 时，无论 I_color_tdata 为何值，O_tdata 必须为 24'h000000。
2. **非边缘透传测试**：I_edge_flag=0 时，O_tdata 必须等于 I_color_tdata（遍历典型色值：白、黑、红、绿、蓝、灰阶）。
3. **控制信号透传测试**：O_tvalid/O_tlast/O_tuser 必须与输入严格一致，无延迟。
4. **连续流测试**：连续输入 1024x600 帧，验证无丢拍、无错位。
5. **边界切换测试**：I_edge_flag 在相邻像素间快速切换（0->1->0），验证输出无毛刺锁存。

## Acceptance Criteria

- [ ] 所有输出为纯组合逻辑，无内部寄存器
- [ ] 边缘像素（I_edge_flag=1）输出严格为 24'h000000
- [ ] 非边缘像素（I_edge_flag=0）输出严格等于 I_color_tdata
- [ ] 控制信号 O_tvalid/O_tlast/O_tuser 零延迟透传
- [ ] 综合无 latch、无 warning
- [ ] 仿真中输出与输入同拍，无额外延迟
