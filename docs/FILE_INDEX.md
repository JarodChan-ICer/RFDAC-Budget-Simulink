# 常用文件索引

## 日常使用

| 文件 | 用途 |
|---|---|
| `../init_rfdac_model.m` | 日常链路仿真的参数入口，包含系统、DPD/LUT、接收机与绘图设置 |
| `../init_rfdac_identification.m` | 独立的辨识实验配置，包含被测 TX 参数、训练、绘图与重复试验设置 |
| `../run_rfdac_identification.m` | RX 小/大摆幅辨识、冻结估计参数、四种校准对比 |
| `../show_rfdac_identification.m` | 从已保存报告显示辨识图和四宫格，不重新仿真 |
| `../run_rfdac_simulation.m` | 实际 SLX 仿真、测量、保存和可选 DPD 前后比较 |
| `../run_rfdac_iq_mismatch_sweep.m` | 7 GHz/100 fs/45 dB TX、1°–3° IQ 扫描；16384 实测蛇形 → 映射 4096 → 实际 4096 蛇形输出与业务 EVM |
| `../plot_rfdac_results.m` | 对 results 结构绘图，遵循 init 中的各绘图开关 |
| `../sweep_lo_jitter.m` | jitter 扫描 |
| `../sweep_dpd_lut.m` | LUT 容量扫描、精度损失与容量推荐 |
| `../setup_rfdac_project.m` | 自动添加当前源码/工具/测试路径，设置输出与缓存目录 |
| `../rfdac_lo_jitter_link_budget.slx` | 当前交付模型 |

## 当前模型实现

`src/rfdac_default_config.m` 提供共享基础默认值；两类 init 在此基础上分别设置各自实验。修改日常 init 不会传递到辨识 init；需要共享同一设置时应显式传入 cfg。

`src/rfdac_prepare.m` 准备参数和数据，`rfdac_fit_tx_evm.m` 标定原模拟 TX。

`src/rfdac_capture_serpentine.m` 在实际 SLX 中采集指定整数 DAC 码的蛇形输入输出，并应用配置的 RX 均衡器与统一定时。`src/plot_rfdac_iq_mismatch_sweep.m` 绘制 IQ 扫描及三阶段星座。流程和指标定义见 `docs/IQ_MISMATCH_SWEEP.md`。

`src/rfdac_fit_rx_equalizer.m` 根据实际 TX/RX LPF 及 DAC 保持器的带内响应自动拟合 RX FIR；`docs/RX_EQUALIZER.md` 说明参数、延迟、增益限制及对比方式；`tests/validate_rfdac_rx_equalizer.m` 验证实际 SLX 的平坦度、EVM、定时与旁路。

`src/rfdac_prepare_dpd.m` 选择算法与参数；`rfdac_lut_grid.m` 生成训练网格；`rfdac_train_link_lut.m` 通过实际SLX发送零前导蛇形DAC码；`rfdac_align_ppt_training.m` 从接收复包络检帧/相位对齐；`rfdac_build_ppt_lut.m` 插值测得的前向映射，并预计算最近输出到原输入的反查表；`rfdac_lut_training_key.m` 管理物理配置变化后的训练失效。`rfdac_dpd_lut_lookup.m` 按TX RRC之后的每个DAC采样访问冻结表；`rfdac_prepare.m` 为S-function单独准备精简的运行码字表；`rfdac_dpd_codewords.m` 保证物理DAC码合法。当前流程见 `docs/PPT_DPD.md`，真实链路验证为 `tests/validate_rfdac_ppt_lut.m`。`rfdac_train_dpd_lut.m` 与 `rfdac_dpd_analytic.m` 仅保留显式静态/解析参考。

业务TX/RX RRC完整保留；训练时原始蛇形线通过 `tools/model/rfdac_upgrade_ppt_source.m` 的校准分支注入DAC，并采集RX匹配RRC之前的复包络。`tests/validate_pre_no_rrc_restore.m` 仅为更早的历史版本回放，不验证当前PPT流程。

`src/rfdac_measure.m` 测量最终接收符号；`rfdac_lo_stream.m` 生成 jitter；`rfdac_qam_map.m` 和 `rfdac_qam_demod.m` 实现 QAM 接口。`src/plot_*.m`、`rfdac_export_figure.m` 为绘图辅助。

`src/rfdac_project_root.m`、`rfdac_output_directory.m`、`rfdac_find_result.m` 负责整理后的路径和旧数据兼容。

## 模型工具与验证

`tools/model/build_rfdac_model.m` 重建模型；`update_*.m` 维护模型结构版本，其中 `update_rfdac_rx_equalizer_model.m` 在 RX 匹配 RRC 前插入自动均衡 FIR。它们是主动使用的代码，不能仅因为带 update 前缀就删除。`polish_*.m` 仅维护布局和模型截图。

`tests/verify_project_layout.m` 检查目录整理后的可运行性；`validate_rfdac_lut.m` 检查 LUT；`validate_rfdac_codeword_plots.m` 检查码字与绘图开关；`audit_rfdac_iq_*.m` 检查 I/Q 校准残差和开关行为。`evaluate_*.m` 与 `finalize_*.m` 保留较早案例评估/交付复核流程。

`docs/MODEL_GUIDE.md` 含不同阶段的详细说明和历史数值，阅读历史结果时注意其当时的参数；根目录 README 描述当前目录布局。

## 输出管理

只看当前运行时，打开 `outputs/results/`。需要对照已验证的 LUT 数值时，打开 `outputs/validation/lut_evaluation/`。过往所有日志、较早结果和阶段性备份都在 `archive/2026-10-21_cleanup/`。

`outputs/cache/` 是可重建缓存；不要把 `archive/`、缓存或旧备份加入 MATLAB 路径。测试与批处理日志请显式写到 `outputs/logs/`，例如 MATLAB 的 `-logfile outputs/logs/my_check.log`。
