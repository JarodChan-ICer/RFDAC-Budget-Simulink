# RF-DAC LO Jitter / I/Q / DPD 链路预算

工程入口集中在根目录。修改 `init_rfdac_model.m` 后，重新加载 cfg 再仿真：

当前日常默认使用 15 GHz LO、100 fs RMS jitter、42 dB TX SNR（干净链路 EVM −42 dB）、1° 正交相位误差、0.8° 差分相位误差、两路 Q LO 增益 1.10、4096QAM 和 16384 点实测 LUT DPD。`run_rfdac_iq_mismatch_sweep()` 默认检查 1°、2°、3°，并对比 4096 点蛇形输出与 RRC 业务的 EVM。两种校准的运行方法见 [IQ_MISMATCH_SWEEP.md](docs/IQ_MISMATCH_SWEEP.md)。

小/大摆幅 RX 辨识与四种校准对比：运行 `report = run_rfdac_identification();`。专用配置在 `init_rfdac_identification.m`，与日常模型配置独立，不需要先运行 `init_rfdac_model`。当前设置保留 TX 等效 SNR 42 dB（EVM −42 dB）、10 GHz、100 fs、1°；默认只做一次完整辨识，并显示最终四宫格等三张图。已有结果可用 `show_rfdac_identification();` 直接显示，无需重新仿真。完整使用方法、重复辨识的目的与可信度说明见 [RX_IDENTIFICATION.md](docs/RX_IDENTIFICATION.md)。

首次从 GitHub 下载后，在 MATLAB 中进入仓库根目录再执行下面命令。Git 仓库包含当前源码、SLX 和文档；`outputs/` 与 `archive/` 不上传，输出目录由初始化自动创建。`validate_rfdac_link_lut` 可从新克隆运行；历史重绘/审计脚本需要相应旧结果，或先运行对应验证脚本生成数据。

```matlab
cfg = init_rfdac_model();
results = run_rfdac_simulation(cfg);
```

`init_rfdac_model` 和运行入口会自动加载 `src/`、`tools/model/` 与 `tests/`；不需要手工添加路径，也不要对工程执行 `addpath(genpath(...))`，否则历史备份可能覆盖当前代码。直接打开 SLX 时，模型的 PostLoadFcn 也会完成路径设置。

## 文件放在哪里

| 位置 | 内容 |
|---|---|
| 根目录 | 当前 SLX、初始化、单次仿真、绘图、两类扫参及路径设置入口 |
| `src/` | 当前模型运行依赖：QAM、jitter、测量、DPD/LUT 与绘图辅助函数 |
| `tools/model/` | 模型生成、升级及布局工具；`update_*.m` 仍是运行依赖，不能删除 |
| `tests/` | 验证、误差审计和历史案例评估脚本 |
| `docs/MODEL_GUIDE.md` | 模型原理、参数、LUT 精度和历史测量说明 |
| `docs/FILE_INDEX.md` | 常用文件与维护说明 |
| `outputs/results/` | 最新单次仿真与手动扫参结果；已保留整理前最新的 single MAT/CSV/星座图 |
| `outputs/validation/` | 验证脚本生成的报告；已保留最新 LUT 验证与扫参结果 |
| `outputs/logs/` | 后续验证/批处理日志 |
| `outputs/cache/` | 可再生成的 Simulink 缓存与生成代码，避免写到根目录 |
| `archive/2026-10-21_cleanup/` | 旧日志、旧结果、阶段性源码备份与旧缓存，均保留 |

当前默认按芯片实测PPT实现**蛇形训练二维LUT**：零前导 + 16384点蛇形码 → 实际RFDAC及RX解调 → 检帧与相位对齐 → 线性插值为完整10-bit二维码字网格 → 目标输出a找最近响应b → 反查原输入c。业务查表在TX RRC之后，处理每个DAC速率采样，业务收发RRC保留。原始训练点直接注入DAC，使用RX匹配RRC之前的实际复包络建表；不再使用随机QAM符号的平均接收星座，也不限制输出只能属于原始16384点。详细流程及PPT对应关系见 [PPT_DPD.md](docs/PPT_DPD.md)。

## 常用操作

```matlab
% 业务收发 RRC 保留；LUT 在 TX RRC 之后按 DAC 采样执行
cfg.RRC_Rolloff = 0.25;
cfg.RRC_Span = 16;

% RX 自动拟合均衡器：补偿 TX/RX LPF 及 DAC 保持器的带内下降
cfg.RX_Equalizer_Enable = true;
cfg.RX_Equalizer_Order = 256; % DAC 速率 FIR，位于 RX 匹配 RRC 之前
cfg.RX_Equalizer_Max_Boost_dB = 6;

% DPD 设置：带零前导的16384点蛇形线，实际RF捕获后插值建表
cfg.DPD_Algorithm = 'lut';
cfg.DPD_LUT_Training_Mode = 'link';
cfg.DPD_LUT_Size_Mode = 'training_order';
cfg.DPD_LUT_Training_Order = 16384;
cfg.DPD_LUT_Training_Repeats = 2;
cfg.DPD_LUT_Training_Dwell_Samples = 25;
cfg.DPD_LUT_Training_Prefix_Zeros = 512;
cfg.DPD_LUT_Drive_Range = 1;
cfg.DPD_LUT_Training_Observed = []; % 自动捕获实际链路，无静态回退
cfg.DPD_LUT_Value_Bits = 10;
cfg.DPD_LUT_Fraction_Bits = 0;
cfg.DPD_LUT_Interpolation = 'linear'; % 前向响应插值，再从合法整数DAC码中最近邻反查

% 最终接收星座及 DPD 前后对比
cfg.Plot_Constellation = true;
cfg.Plot_DPD_Comparison = true;
cfg.Plot_DPD_LUT_Selection = true; % 上排 DPD 前/后，下排居中显示训练 RF 星座并标红选点
cfg.Plot_LPF_Response = false; % true: LPF 响应及均衡前后带内平坦度
cfg.Plot_Waveforms = false;
results = run_rfdac_simulation(cfg);

% 扫描
sweep = sweep_lo_jitter(cfg);
lut_report = sweep_dpd_lut(cfg,[4096 16384 65536]);

% 维护验证：先加载路径，再选择验证项目
setup_rfdac_project();
validate_rfdac_ppt_lut(false); % 实际RF小码本、检帧、相位和插值校验
validate_rfdac_ppt_lut(true);  % 完整16384点训练、4096QAM对照
validate_rfdac_ppt_lut(true,30); % 大IQ误差对照
validate_rfdac_trained_lut();   % 显式static参考的有限码本核心回归
```

单次仿真仍以 `single_results.mat`、`single_metrics.csv` 和 `single_dpd_before_after_constellation.png` 为默认文件名，写入 `outputs/results/`。修改 `cfg.Run_Tag` 可保留不同命名的运行；修改 `cfg.Output_Directory` 可指定自己的输出目录。绘图开关都在 init 中。

整理前保存的 MAT 文件仍保持原内容。旧 cfg 中指向本工程原 `results/` 的输出路径，在运行/绘图入口会重定向到 `outputs/results/`，避免再次生成旧目录。历史验证脚本通过 `rfdac_find_result` 查找归档数据，档案目录不会加入 MATLAB 搜索路径。

RX 均衡器在每次初始化时根据实际滤波器系数自动拟合，并自动计入 FIR 延迟；禁用时系数为 1、额外延迟为 0。运行 `validate_rfdac_rx_equalizer()` 可验证实际 SLX 的均衡前后 EVM、带内平坦度和增益限制。参数、方法及限制见 [RX_EQUALIZER.md](docs/RX_EQUALIZER.md)。

## 归档与恢复

未删除历史日志或测量结果。`archive/2026-10-21_cleanup/file_moves.csv` 记录原路径、当前位置、大小和移动时 SHA-256；`source_before_cleanup.zip` 保存整理前的完整根目录源码、配置、模型与 README。`organize_files.ps1` 是此次一次性整理记录，请勿重复执行。

归档中的旧源码仅供追溯，不应与 `src/` 混用。原科学验证结论及全部测量数据继续保留；本次整理不重新定义 EVM 或修改 RF/DPD 数学模型。
