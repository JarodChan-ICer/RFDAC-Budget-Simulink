# 通过实际 RFDAC 和接收解调训练 LUT DPD

> **历史：2026-11-01的随机符号训练版本。** 当前已按用户芯片实测PPT改为零前导蛇形线、检帧/相位对齐、前向插值和TX RRC后逐采样反查，使用方法见 [PPT_DPD.md](PPT_DPD.md)。以下符号域位置、nearest设置和历史数值不适用于当前默认流程。

默认 `DPD_LUT_Training_Mode='link'`。旧版确实仅使用 IQ/atan 静态前向公式，未发送训练波形；该方式现在只能通过显式设置 `'static'` 作为参考，不能代表实际链路训练结果。

## 4096QAM 的使用方法

```matlab
cfg = init_rfdac_model();
cfg.QAM_Order = 4096;
cfg.DPD_Algorithm = 'lut';
cfg.DPD_LUT_Training_Mode = 'link';
cfg.DPD_LUT_Training_Order = 16384;
cfg.DPD_LUT_Training_Repeats = 4;
cfg.DPD_LUT_Training_Observed = [];
results = run_rfdac_simulation(cfg);
```

运行入口自动完成训练、建表和独立数据验证，无需手动运行一次 16384QAM。首次运行需要额外的实际 SLX 训练时间；同一 MATLAB 会话中，完全相同的物理链路和训练设置可以复用捕获。更改物理参数会重新训练。训练失败直接报错，不会退回静态公式。

## 实际执行的步骤

1. 生成 128×128 个量化后的训练输入点。默认每轴覆盖 DAC 满量程的 80%，为 RRC 峰值留出余量；可用 `DPD_LUT_Drive_Range` 修改。点按 `ndgrid(I,Q)` 展开，I 索引先变化。每个点是原 DAC 位宽下的整数码乘 LSB。
2. 每个训练点每轮出现一次，每轮独立打乱顺序；默认四轮，共 65536 个有效训练符号，另加 32 个预热符号。训练种子 1073 与默认业务种子 73 独立。训练期间关闭 DPD。
3. **调用原生 SLX**，经过 TX RRC → N-bit DAC 量化/饱和 → ZOH → TX 低通 → 带 IQ 误差和 jitter 的 LO 混频 → RF 非线性 → RX 下变频 → RX 低通 → 匹配 RRC → 时延校正 → 符号抽样。训练沿用业务链路实际设置；不关闭 jitter，不将滤波器替换为 DC 增益。
4. 记录接收端的复数软符号 `Received_Symbols_Raw`，按照已知发送点的索引配对。每点的多次真实观测求平均成为 `Training_Output`，同时保存全部原始观测、计数及散布。这里的“解调”是相干下变频和符号恢复，不先做硬判决，否则会抹掉待校正的畸变。
5. 对 4096QAM 每个目标 `u = Input_Amplitude * constellation(k)`，选择 `j = argmin(abs(Training_Output - u))`，再发送训练时对应的原始输入点 `Training_Drive(j)`。查表不会读取 β 或 IQ 估计参数，不使用解析逆、插值或补偿量加回。
6. 将选中的输入点再次经过完整业务 RFDAC/RX 链路，以独立数据与 jitter 序列测量最终 EVM/SER。DPD OFF/ON 比较固定同一个物理 β、业务数据和 jitter，实现公平对照。

训练观测使用物理 V，目标同样使用物理 V。没有用训练星座拟合的复增益归一化观测，以免改变训练点与输入的实际对应。最终 EVM 仍沿用工程原有单一复增益拟合口径。RX 观测链路假定增益、时钟和相位已标定；若改为外部硬件捕获，需要先完成相应对齐。

`TX_Target_EVM_dB=-42` 仍用于原业务链路的干净 TX 标定。标定后的物理 `TX_Beta` 在高阶训练、DPD OFF、DPD ON 三阶段冻结，不能因训练幅度或调制阶数改变而重新拟合。物理模型参数只属于被仿真的器件，不能参与查表反推。

## 查表位置与误差

查表位于 **TX RRC 之前的符号域**，因为训练反馈是在 RX 匹配滤波之后抽出的符号。不能将符号域测得的点直接用于 RRC 后的每个 DAC 采样，两者不是同一传输映射。

DPD 选择的每个**输入符号**属于 16384 点训练集合；随后 RRC 会合成新的采样值，物理 DAC 仍对这些采样做原位宽量化和饱和。因此“所有物理 DAC 采样都属于 16384 点集合”不再是此方案的约束。没有取消 RRC，也没有在符号周期内将 DAC 输出保持为单一点。

这是有限点、有限观测的无记忆符号 LUT：不能完全消除 RRC/模拟滤波器造成的上下文依赖、幅度变化引起的非线性记忆效应及随机 jitter。训练平均不会消除业务验证中的随机误差。16384 个候选点也可能不足以让 4096 个目标各自获得唯一、足够精确的对应点；程序按实际最近点选择，不强行保证一一映射或改善到某个 EVM。增大训练轮数只改善每点平均观测精度，增加训练阶数才会改变候选分辨率。

真实链路观测包含 IQ 和非线性的联合影响，因此 link 模式要求 `DPD_IQ_Enable` 和 `DPD_Nonlinearity_Enable` 同时开启（或者关闭整个 DPD）。不能由同一组复数观测分离单项校准。独立的 RX 参数辨识四种对照实验保留显式 `'static'` 模式，性质是基于辨识参数的静态参考。

## 输出、复用与外部观测

- 默认对比图上排显示 DPD OFF/ON 的最终 4096QAM 接收星座；下排居中显示 **16384QAM 经实际 RFDAC 和 RX 后的观测均值**，红点是本次业务真正选用的训练点。统计按业务符号计数，冲洗尾帧不算 LUT 访问。
- `<Run_Tag>_dpd_link_training.mat` 保存训练表、原始观测、发送索引、每点次数、散布、物理 β、种子与完整配置指纹，便于审计。只有 `Save_Results=true` 时自动写入。
- `<Run_Tag>_results.mat` 保存业务结果和训练表；`<Run_Tag>_dpd_lut_training_selection.mat` 保存图中的实际选点及计数。
- `results.DPD.Symbol_LUT_Indices` 是4096个理想业务点到训练点的映射；`Symbol_Drives` 是再次发送的原输入点。访问次数取决于实际发送的数据；不同目标可以选择同一训练点。
- `DPD_LUT_Training_Observed` 可导入与训练输入逐点配对的外部 RX 复数观测，顺序和单位须与本工程一致，不能提供误差向量或硬判决。重新手动提供外部观测时应清空 `DPD_LUT_Training_Metadata=struct()`；程序生成的观测带指纹，物理配置变化时自动失效。
- 直接点 SLX 的 Run 前，先通过 `run_rfdac_simulation(cfg)` 完成训练；之后模型可使用工作区中带训练结果的 cfg。未训练或配置变更时，直接 Run 会明确要求通过运行入口重新训练，避免在模型 InitFcn 内嵌套启动同一模型。
- 10-bit、16384点的 I/Q 候选字载荷仍为40 KiB；观测数据、搜索索引和4096点符号映射另计，不可称为完整硬件存储量。

## 验证与历史结果

```matlab
setup_rfdac_project();
validate_rfdac_link_lut(false); % 小码本，实际 SLX 训练与独立穷举查表校验
validate_rfdac_link_lut(true);  % 完整 16384QAM 训练 + 4096QAM 业务、DPD OFF/ON
validate_rfdac_link_lut_integration(); % 保存、直接运行、物理/阶数变化重训、模型生成
validate_rfdac_trained_lut();   % 显式 static 模式的旧码本核心回归，不验证新链路训练
```

实际链路验证检查：训练覆盖、原始接收样本按发送索引重新计算的均值、4096个目标的独立穷举最近点、忽略模型估计参数、RRC/DAC 日志重放，以及 DPD OFF/ON 的相同数据/jitter/β。报告和对比图位于 `outputs/validation/link_lut_20261101/`。

2026-11-01 完整实际 SLX 验证通过：7 GHz、30° IQ、100 fs jitter、10-bit DAC，业务4096QAM共16384符号，16384个训练候选每点4次，物理 β 固定为0.469191101 V⁻²。

| 指标 | DPD OFF | 实际链路训练 LUT ON |
|---|---:|---:|
| EVM | 26.232753% | 1.678858% |
| EVM dB | −11.623 | −35.500 |
| SER | 99.6277% | 18.3411% |

精确浮点指标见 `full_metrics.csv`，原始训练观测与业务结果见 `full_validation.mat`，对比图见 `full_dpd_before_after_constellation.png`。训练观测均值相对旧静态基波公式的 RMS 差为7.863608 mV；训练过程也实际出现 DAC 饱和（I/Q 分别5858/5512个采样），并未替换为无饱和理想观测。业务 DPD ON 的完整记录没有 DAC 饱和，但 SER 仍明显非零，不能视为4096QAM已无误码恢复。测试运行均保存在验证目录，没有覆盖原 `single_results.mat`。

本次修改前的活动源码及 SLX 已备份在 `outputs/validation/before_demodulated_lut_20261101/`。旧 MAT、历史静态模型 EVM 和旧的逐 DAC 采样码本校验只用于追溯，不代表当前 link 模式性能。
