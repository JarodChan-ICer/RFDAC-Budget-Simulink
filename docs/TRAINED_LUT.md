# 有限训练阶数的 LUT DPD

> **历史方案说明。** 下文记录本次修改之前的静态模型与逐 DAC 采样查表，不是当前默认实现。当前真实 RFDAC + RX 训练和符号域反查见 [LINK_LUT.md](LINK_LUT.md)。历史命令可能需要显式 `DPD_LUT_Training_Mode='static'`，不能作为当前 link 模式的验证。

当前已按要求回退到“取消 RRC、改成符号级映射”之前：**TX RRC 后逐 DAC 采样查表，RX 保留匹配 RRC**。不采用每符号固定选择一个驱动再保持的方案，也没有后加的 RRC_Enable 开关。恢复当时 320 MBaud、500 MHz 收发低通、30° IQ、100 fs jitter 和 42 dB 干净 TX 目标。

`TX_Target_EVM_dB=-42` 恢复为完整干净 TX 的 EVM 标定目标：使用相同的 RRC、DAC、低通和接收测量，标定时关闭 jitter 并采用理想正交。不再使用后加的静态单点基波标定口径；实际 IQ/jitter 和 DPD 前后结果仍独立测量。

2026-11-01 起，`DPD_Algorithm='lut'` 使用有限训练码本。以信号 4096QAM、训练 16384QAM 为例，LUT 中有 128×128 个固定的 I/Q DAC 驱动点；开启校准时，每一个 DPD 输出必须严格等于其中一个点。不存在补偿量加回、输入低位旁路、插值、外推或运行时解析逆变换。

```matlab
cfg = init_rfdac_model();
cfg.RRC_Rolloff = 0.25;
cfg.RRC_Span = 16;      % 偶数，单位为符号
cfg.QAM_Order = 4096;
cfg.DPD_Algorithm = 'lut';
cfg.DPD_LUT_Size_Mode = 'training_order';
cfg.DPD_LUT_Training_Order = 16384;
cfg.DPD_LUT_Training_Observed = []; % 默认使用静态 RF 模型训练观测
cfg.DPD_LUT_Value_Bits = 10;
cfg.DPD_LUT_Fraction_Bits = 0;
cfg.DPD_LUT_Interpolation = 'nearest';
results = run_rfdac_simulation(cfg);
```

## 训练与运行

1. 在 DAC 满量程内生成训练阶数对应的均匀 QAM 网格，取整成原 DAC 位宽的整数码。例如 10-bit DAC、16384 点时，每轴 128 个幅度。网格采用每个等宽区间中心：理想中心为 −508.5、−500.5、…、507.5 码，实际向最近整数取整。每路范围仍受 −512…511 约束，网格不使用单位平均功率归一化，以覆盖整个 DAC 输入范围。
2. 逐候选点建立“绝对 DAC 字 → 静态 TX 复数输出”的配对。默认对每个点保持到稳态，在一周期内均匀取 128 个 RF 相位，经过所选静态 IQ/atan TX，再相干提取基波。这里进行前向 RF 表征，没有调用解析逆函数。线性滤波器的稳态 DC 增益为 1；滤波瞬态、jitter 和观测噪声未参与此静态训练。
3. TX RRC 成形后的每一个 DAC 采样先按输入 DAC 位宽格式化为 `u`，再在训练观测平面选择 `k = argmin(abs(Training_Output(k)-u))`，输出其配对的绝对 DAC 字。查表处理的是成形波形，实际访问的训练点数可能超过 QAM 符号阶数；不冻结成4096项符号映射，也不在一个符号期间保持同一输出。没有插值或补偿增量。
4. 原模拟 TX、重构/接收滤波、LO 误差和随机 jitter 继续运行。DPD 关闭或 IQ/非线性两项均关闭时，原 10-bit 输入码字旁路。

链路为 QAM 符号 → 上采样和 TX RRC → N-bit 输入格式化 → LUT 选择绝对训练驱动 → N-bit DAC/ZOH → TX 低通 → IQ 混频/非线性 → RX 低通 → 匹配 RRC → 延时校正与符号抽样。

**开启训练 LUT 补偿时，物理 DAC 的每一对 I/Q 码字都属于训练驱动集合。**RRC 位于查表之前，不会在查表之后混合产生新的驱动点。训练本身仍采用静态 RF 表征，不包含实际滤波瞬态和观测噪声；完整链路结果通过实际 SLX 测得。

RRC 使用单位能量的 `rcosdesign(rolloff,span,L,'sqrt')`，源冲激幅度乘 sqrt(L)，RX 系数除 sqrt(L)，维持原平均发射幅度和匹配增益约定。滤波乘加采用 double；原 N-bit DAC 的取整、饱和继续实际执行。

`DPD_IQ_Enable` 和 `DPD_Nonlinearity_Enable` 决定静态训练所表征的补偿部分。未提供外部观测时，参数仍来自 `DPD_*_Estimate`，为空则采用当前模型真实参数；因此默认训练仍是理想静态模型训练，不包含真实反馈噪声或有限样本估计误差。`DPD_Max_Gain` 仅约束解析参考的逆函数；有限码本本身受合法 DAC 驱动集合限制，不存在逆函数极点。

## 实测训练观测

`cfg.DPD_LUT_Training_Observed` 可提供与候选驱动一一对应的复数响应，长度必须等于训练阶数，单位与目标基带电压一致。使用 `ndgrid(I_levels,Q_levels)`，按 MATLAB 列优先展开：I 索引先变化、Q 索引后变化。外部观测须先完成时延、固定复增益和 DC 对齐；这是完整复数响应，不是误差向量或 ΔI/ΔQ。提供此字段后，建表不使用模型参数计算响应。完整实测映射仅用于 IQ/非线性联合校准，不能从同一组实测响应中自动分离成单项校准；关闭 DPD 时仍可正常旁路。

## 参数与旧配置

- 推荐 `training_order` + `DPD_LUT_Training_Order`，训练阶数应是方形且每轴为 2 的幂，总上限 1048576。
- 保留 `total_points`、`axis_bits` 和 `qam_multiple` 作为候选数量的兼容入口，含义同样改为有限绝对驱动集合；`axis_bits` 允许矩形网格。
- `DPD_LUT_Value_Bits` 必须至少为 DAC 位宽，仅决定绝对字的存储位宽。`Fraction_Bits` 必须为 0，`Interpolation` 只能为 `nearest`；旧的分数码和 `linear` 设置会明确报错。
- `Output_I/Output_Q` 是绝对整数 DAC 字；`Training_Output` 是配对的静态观测。训练响应、Delaunay 搜索数据和索引为仿真辅助数据，**不包含在 40 KiB 绝对字载荷中**。不能将这个载荷数当作完整硬件实现的存储量。
- 输出字已是整数，因此末端再次取整的误差可以为零；有限训练集合造成的误差仍由最终 EVM 计入。合法字的 DAC 削顶计数为零，也不表示所有目标都可达：超出训练响应范围的目标仍被限制到最近的训练点。
- `DPD_Algorithm='analytic'` 仅保留为不受训练点集合限制的参考，默认仍为 `lut`。
- 旧 MAT 的 ΔI/ΔQ 表只用于历史对照和绘图，不能直接作为新运行表使用；应重新准备 cfg 和 LUT。

## 验证

`cfg.Plot_DPD_LUT_Selection=true`（默认）将同一张对比图排列为**上排两张、下排居中一张**：上排为 DPD OFF / DPD ON 的最终接收星座，下排为训练调制阶数对应的完整 RF 输出星座，例如 16384QAM 的 16384 个静态训练输出。下排用蓝灰色显示全部训练输出，红色显示实际选中的点；不再显示局部放大图，也不在上排叠加 LUT 点。

下排坐标直接使用 `Training_Output` 的 RF 基波复包络，单位为 V，不使用上排的接收符号归一化。红点来自**完整 TX RRC 波形实际访问的训练点**，包括滤波冲洗尾帧，访问次数以 DAC 采样计；重建输出与保存的实际 DAC 码字核对。重复访问的点只显示一次，因此红点数不要求等于4096。完整选点、训练响应和使用次数保存为 `<Run_Tag>_dpd_lut_training_selection.mat`。关闭该绘图开关或使用解析参考时，仅显示上排两张对比图。

如需单独的码本图，仍可手动调用 `[f,usage]=plot_rfdac_lut_selection(results)`；普通仿真不再自动弹出该图。

`validate_rfdac_trained_lut()` 不启动 Simulink，检查 65536 组随机输入的训练集合归属、独立穷举最近点、前向 RF 基波、外部观测导入、关闭 DPD，以及插值/分数码拒绝。`validate_rfdac_lut()` 额外执行真实 SLX 对照和多 QAM 验证。

`validate_pre_no_rrc_restore()` 用取消 RRC 前的原始模型/结果备份，核对恢复后的完整标定、收发 RRC、实际 DPD OFF/ON 输出及选点日志。回退前的符号保持和 RRC 开关版本已完整备份到 `outputs/validation/rollback_to_pre_no_rrc_*/`，不在活动源码路径中。

`evaluate_rfdac_trained_lut()` 使用已保存的单次结果中的物理 β、滤波器与时延，独立分块重放数值 RF 链路，并先与实际保存的 DPD-off SLX 符号核对。结果另存 `outputs/validation/trained_lut_20261101/`，不会覆盖原单次结果。此脚本需要当前目录中保留原 `single_results.mat`，普通运行与核心验证不依赖历史结果。

原来的补偿量 LUT 文档和数值保留在 `MODEL_GUIDE.md` 的历史章节；不能用于预测当前有限训练码本的性能。
