# RF-DAC LO Jitter / I/Q / DPD 链路预算

工程入口集中在根目录。修改 `init_rfdac_model.m` 后，重新加载 cfg 再仿真：

首次从 GitHub 下载后，在 MATLAB 中进入仓库根目录再执行下面命令。Git 仓库包含当前源码、SLX 和文档；`outputs/` 与 `archive/` 不上传，输出目录由初始化自动创建。`verify_project_layout` 与 `validate_rfdac_lut` 可从新克隆运行；历史重绘/审计脚本需要相应旧结果，或先运行对应验证脚本生成数据。

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

本次整理保留原参数，包含 7 GHz、4096-QAM、TX −45 dB、white jitter 和 16384 点 LUT。实际使用值始终以 init 文件为准。

## 常用操作

```matlab
% DPD 设置：16384 个复数表项 = 128x128，每路 10-bit 补偿值
cfg.DPD_Algorithm = 'lut';
cfg.DPD_LUT_Points = 16384;
cfg.DPD_LUT_Value_Bits = 10;
cfg.DPD_LUT_Fraction_Bits = 0;

% 最终接收星座及 DPD 前后对比
cfg.Plot_Constellation = true;
cfg.Plot_DPD_Comparison = true;
cfg.Plot_LPF_Response = false;
cfg.Plot_Waveforms = false;
results = run_rfdac_simulation(cfg);

% 扫描
sweep = sweep_lo_jitter(cfg);
lut_report = sweep_dpd_lut(cfg,[4096 16384 65536]);

% 维护验证：先加载路径，再选择验证项目
setup_rfdac_project();
verify_project_layout();       % 目录、直接打开模型、实际仿真、缓存、旧结果读取
validate_rfdac_lut();          % 完整 LUT 验证，耗时较长
```

单次仿真仍以 `single_results.mat`、`single_metrics.csv` 和 `single_dpd_before_after_constellation.png` 为默认文件名，写入 `outputs/results/`。修改 `cfg.Run_Tag` 可保留不同命名的运行；修改 `cfg.Output_Directory` 可指定自己的输出目录。绘图开关都在 init 中。

整理前保存的 MAT 文件仍保持原内容。旧 cfg 中指向本工程原 `results/` 的输出路径，在运行/绘图入口会重定向到 `outputs/results/`，避免再次生成旧目录。历史验证脚本通过 `rfdac_find_result` 查找归档数据，档案目录不会加入 MATLAB 搜索路径。

## 归档与恢复

未删除历史日志或测量结果。`archive/2026-10-21_cleanup/file_moves.csv` 记录原路径、当前位置、大小和移动时 SHA-256；`source_before_cleanup.zip` 保存整理前的完整根目录源码、配置、模型与 README。`organize_files.ps1` 是此次一次性整理记录，请勿重复执行。

归档中的旧源码仅供追溯，不应与 `src/` 混用。原科学验证结论及全部测量数据继续保留；本次整理不重新定义 EVM 或修改 RF/DPD 数学模型。
