# 常用文件索引

## 日常使用

| 文件 | 用途 |
|---|---|
| `../init_rfdac_model.m` | 唯一集中参数入口，包含系统、DPD/LUT、接收机与绘图设置 |
| `../run_rfdac_simulation.m` | 实际 SLX 仿真、测量、保存和可选 DPD 前后比较 |
| `../plot_rfdac_results.m` | 对 results 结构绘图，遵循 init 中的各绘图开关 |
| `../sweep_lo_jitter.m` | jitter 扫描 |
| `../sweep_dpd_lut.m` | LUT 容量扫描、精度损失与容量推荐 |
| `../setup_rfdac_project.m` | 自动添加当前源码/工具/测试路径，设置输出与缓存目录 |
| `../rfdac_lo_jitter_link_budget.slx` | 当前交付模型 |

## 当前模型实现

`src/rfdac_prepare.m` 准备参数和数据，`rfdac_fit_tx_evm.m` 标定原模拟 TX。

`src/rfdac_prepare_dpd.m` 选择算法与系数；`rfdac_build_dpd_lut.m` 建表；`rfdac_dpd_lut_lookup.m` 执行查表；`rfdac_dpd_analytic.m` 提供解析参考；`rfdac_dpd_codewords.m` 强制有限码字格式；`rfdac_dpd_block.m` 是模型 S-function 接口。

`src/rfdac_measure.m` 测量最终接收符号；`rfdac_lo_stream.m` 生成 jitter；`rfdac_qam_map.m` 和 `rfdac_qam_demod.m` 实现 QAM 接口。`src/plot_*.m`、`rfdac_export_figure.m` 为绘图辅助。

`src/rfdac_project_root.m`、`rfdac_output_directory.m`、`rfdac_find_result.m` 负责整理后的路径和旧数据兼容。

## 模型工具与验证

`tools/model/build_rfdac_model.m` 重建模型；两个 `update_*.m` 维护模型结构版本。它们是主动使用的代码，不能仅因为带 update 前缀就删除。`polish_*.m` 仅维护布局和模型截图。

`tests/verify_project_layout.m` 检查目录整理后的可运行性；`validate_rfdac_lut.m` 检查 LUT；`validate_rfdac_codeword_plots.m` 检查码字与绘图开关；`audit_rfdac_iq_*.m` 检查 I/Q 校准残差和开关行为。`evaluate_*.m` 与 `finalize_*.m` 保留较早案例评估/交付复核流程。

`docs/MODEL_GUIDE.md` 含不同阶段的详细说明和历史数值，阅读历史结果时注意其当时的参数；根目录 README 描述当前目录布局。

## 输出管理

只看当前运行时，打开 `outputs/results/`。需要对照已验证的 LUT 数值时，打开 `outputs/validation/lut_evaluation/`。过往所有日志、较早结果和阶段性备份都在 `archive/2026-10-21_cleanup/`。

`outputs/cache/` 是可重建缓存；不要把 `archive/`、缓存或旧备份加入 MATLAB 路径。测试与批处理日志请显式写到 `outputs/logs/`，例如 MATLAB 的 `-logfile outputs/logs/my_check.log`。
