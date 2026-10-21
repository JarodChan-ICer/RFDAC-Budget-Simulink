> 目录整理说明（2026-10-21）：当前运行方式与目录布局见根目录 README.md。以下指南含历史配置和数值；旧 results/ 位于 archive/2026-10-21_cleanup/results/，旧 backups/ 位于同一归档下。最新单次结果在 outputs/results/，最新 LUT 验证在 outputs/validation/lut_evaluation/。源码现位于 src/、tools/model/、tests/，请使用 setup_rfdac_project 加载当前代码。

# RF-DAC TX EVM、四相 LO 与 jitter 链路预算

## DPD 算法与有限精度 LUT

当前默认算法为 **二维 I/Q 补偿量 LUT**，可以切回解析逆变换做参考。输入与输出均受原来的 `DAC_Bits=10` 限制，模拟 TX、正交误差与 jitter 保留。此处把“4096-QAM、16384 点”明确解释为 **16384 个复数表项，即 128×128 的 I/Q 地址网格**，每个表项存一对 ΔI、ΔQ。

```matlab
cfg = init_rfdac_model();
cfg.DPD_Algorithm = 'lut';             % 'lut' / 'analytic'
cfg.DPD_LUT_Size_Mode = 'total_points';
cfg.DPD_LUT_Points = 16384;            % 总表项数，不是每路 16384 点
cfg.DPD_LUT_Value_Bits = 10;           % 每个 I/Q 补偿值的有符号存储位宽
cfg.DPD_LUT_Fraction_Bits = 0;         % 以 DAC 码为单位的小数位数
cfg.DPD_LUT_Interpolation = 'nearest'; % 纯查表；可选 'linear' 双线性插值
cfg.DPD_LUT_Max_Penalty_dB = 0.1;     % 扫描后推荐容量的允许 EVM 损失
results = run_rfdac_simulation(cfg);
```

点数的确定方式可选：

| `DPD_LUT_Size_Mode` | 使用的配置 | 示例 |
|---|---|---|
| `total_points` | `DPD_LUT_Points` | 16384 → 128×128，I/Q 各 7 位地址 |
| `axis_bits` | `DPD_LUT_Address_Bits=[I_bits Q_bits]` | [7 7] → 128×128；[6 8] → 64×256 |
| `qam_multiple` | `DPD_LUT_Points_Per_QAM_Symbol` | 4 → 总点数为 QAM_Order×4，4096-QAM 对应 16384 |

`total_points` 和 `qam_multiple` 使用方形、每轴为 2 的幂的网格；非方形网格使用 `axis_bits`。地址位数不能超过输入每路的 DAC_Bits，总表项数上限 1048576。`qam_multiple` 只是方便设置容量的规则，不意味着每个 QAM 星座点真的对应四个有效样本或能保证某个 EVM。

**点数、表项数值位宽、最终 DAC 位宽是三项独立约束。**4096-QAM 在符号时刻有 4096 个理想点，但 DPD 位于 RRC 之后，处理逐采样 I/Q 码字，不是只对符号 ID 查表。I/Q 各 10 bit 的完整地址空间为 1024×1024=1048576；128×128 表将每轴 8 个相邻输入码分到同一地址区间。最近邻模式按这些区间读取表项；双线性模式在相邻表项间插值，边缘钳位，不外推。

LUT 存储补偿量而不是直接存储粗网格的输出幅度，运行链路为：

```text
Cin = clip(round(RRC / DAC_LSB))
delta = lookup(Cin)                % 存储的 ΔI、ΔQ，支持有限位宽和可选插值
Cout = clip(round(Cin + delta))    % 最终仍为原 DAC_Bits 位整数码
```

这样压缩 LUT 地址不会把原始信号也降成每轴只有 128 个幅度等级。初始化时在每个输入区间中心计算所选静态模型逆变换，减去原输入得到补偿量，再按 `Value_Bits` 和 `Fraction_Bits` 量化/饱和存表。运行时读取表项，不再调用解析逆函数。表仍由已知模型参数生成，未实现实测回授训练；估计值为空时仍会自动跟随实际静态误差。原有 `DPD_IQ_Enable` 和 `DPD_Nonlinearity_Enable` 决定 LUT 包含哪些校准项。

表项小数位以 **DAC 码**为单位：`Value_Bits=10,Fraction_Bits=0` 表示每个补偿值范围 −512…511 码、步进 1 码；`16,6` 表示范围 −512…511.984375 码、步进 1/64 码。更精细的内部表项或插值不会增加最终 DAC 的 10-bit 输出精度。插值权重与算术当前用 double，没有另外模拟硬件乘加器和权重的定点位宽。

16384 个复数表项、每路 10 bit 的理论紧凑数据载荷为 `16384*2*10/8=40960 bytes=40 KiB`，不含地址、元数据、增益限幅标记和插值器。MATLAB 中用 int32 精确保存受位宽约束的表项，因此 MATLAB 实际内存不等于这个紧凑载荷。

结果的 `results.DPD.LUT` 保留完整表、断点和格式。指标新增 `DPD_Algorithm`、`DPD_LUT_Points`、`DPD_LUT_I_Nodes/Q_Nodes`、`DPD_LUT_Value_Bits/Fraction_Bits`、`DPD_LUT_Interpolation`、`DPD_LUT_Packed_Payload_Bytes`、`DPD_LUT_Value_Clipped_Nodes` 和 `DPD_LUT_Node_Quantization_RMS_Code`。最后两项是整个地址网格的建表诊断，不是实际输入占用概率加权的结果。最近邻、整数码补偿的模式下，最终输出再次取整可能没有额外误差，但表项量化和地址近似误差仍存在，不能把额外取整误差为零解释成无限精度；最终 EVM 仍计入这些误差。

建议通过实际 EVM 与容量的权衡确定精度，而不是仅从 QAM 阶数推算。保留同一 TX 系数、种子及 jitter，比较关闭 DPD、解析参考和不同点数：

```matlab
cfg = init_rfdac_model();
cfg.LO_Jitter_Enable = false; % 可选：先看确定性校准差异
report = sweep_dpd_lut(cfg,[4096 16384 65536]);
% 固定点数后，可改 Value_Bits / Fraction_Bits / Interpolation 再比较。
```

扫参结果保存到 `cfg.Output_Directory/lut_sweep/`，含 CSV、MAT 和 EVM/容量图。`validate_rfdac_lut()` 验证实际查表、有限位宽、三种定容量方式、真实 SLX、五种 QAM 和插值，结果在 `results/lut_evaluation/`。新辅助文件 `rfdac_build_dpd_lut.m`、`rfdac_dpd_lut_lookup.m` 和 `rfdac_dpd_analytic.m` 必须保留。此次修改前备份在 `backups/before_dpd_lut_20261020/`。

扫描按 `20*log10(EVM_LUT/EVM_analytic) <= DPD_LUT_Max_Penalty_dB` 判断是否满足精度要求，并在已测试候选中推荐载荷最小的表，返回 `Recommended_Points`。默认容许 0.1 dB EVM 损失。这个推荐不会修改你指定的 `DPD_LUT_Points`；如果没有候选通过，返回空值。表项位宽和插值由 cfg 固定，想评估它们时改变参数再运行。建议先关闭 jitter 查看确定性精度，再恢复实际工况复核；大噪声/失真底限可能掩盖 LUT 差异。有限记录中误差相关，总 EVM 不保证严格单调，解析逐样本逆变换也不等于全局最优的量化码字选择。

本机完整验证：7 GHz、4096-QAM、TX −45 dB、1° 正交误差、100 fs jitter、16384 符号，保留原来的“仅校准 I/Q、非线性 DPD 关闭”设置：DPD 关闭 / 16384 点最近邻 10-bit 补偿 LUT / 解析参考的 EVM 分别为 **1.119406611% / 0.715737908% / 0.715464049%**。LUT 运行没有非法 DAC 码字，表项也未饱和。

另用相同物理 TX 系数、1024 符号且关闭 jitter 检查点数，结果如下（与上面的完整记录分别比较）：

| 总表项数 | 紧凑载荷 (KiB) | EVM (%) | 相对解析参考的 EVM 损失 (dB) |
|---:|---:|---:|---:|
| 256 | 0.625 | 0.590615 | 约 0.179 |
| 4096 | 10 | 0.580001 | 约 0.022 |
| 16384 | 40 | 0.579368 | 约 0.012 |
| 65536 | 160 | 0.578295 | 约 −0.004 |

该短记录的解析参考 EVM 为 0.578551%。按默认 0.1 dB 损失门槛，已测试候选中推荐 4096 点；这不改变用户指定的 16384 点设置。结果是当前参数和输入记录的测量结论，不是对所有 QAM、带宽与非线性强度的容量保证。

查表及插值的通用定义参考 [MathWorks Lookup Table Overview](https://www.mathworks.com/help/simulink/ug/understand-lookup-table-basics.html)。本工程的 LUT 运行于已有 Level-2 MATLAB S-function 内，无需新增工具箱。以下数值记录为此前解析逆变换版本，当前 LUT 结果以新验证输出为准。

## 10-bit 码字限制与最终星座对比

当前模型的数字链路为：RRC 成形 → **10-bit 输入码字格式化** → DPD 运算 → **10-bit 输出码字取整/饱和** → 原 I/Q DAC、LPF、四相混频器、TX 非线性 → 原接收机。默认每路有符号码字为 −512…511，`LSB=2*DAC_Full_Scale/1024`。DPD 只改变码字，不能送入分数码字或额外的 DAC 位。内部系数/逆变换仍用 double 运算，未建模系数的定点位宽；输出以 `code*LSB` 的电压等效值传给原 DAC。double 精确存储整数不会增加码字精度。

关闭 DPD 时，格式化后的输入码字原样通过；开启时，先按输入码字运算，再重新取整和饱和到相同位宽。因此很小的补偿可能不足一个 LSB，残余 EVM 不会被强制归零。原有模拟非线性、LO 静态误差和随机 jitter 始终在原位置运行。新的 `rfdac_dpd_codewords.m` 为物理链路使用的码字接口；`rfdac_dpd_apply.m` 仅是接口内部的理想数学运算。

绘图开关均在 `init_rfdac_model.m` 中，默认以最终接收星座为主：

| 参数 | 默认值 | 作用 |
|---|---|---|
| `Make_Plots` | true | 所有绘图的总开关 |
| `Plot_Constellation` | true | 最终恢复星座与理想参考点 |
| `Plot_DPD_Comparison` | true | 开启 DPD 时自动补跑关闭 DPD 的对照；左右比较最终接收星座 |
| `Plot_LPF_Response` | false | 单独绘制 TX/RX FIR 响应 |
| `Plot_Waveforms` | false | 单独绘制实际码字、DAC/滤波、RF 和接收 I/Q 时域波形 |
| `Plot_Spectra` | false | 单独绘制基带和 RF 频谱 |
| `Plot_Diagnostics` | false | 单独绘制误差矢量、jitter 和模拟 TX AM/AM |

`Plot_DPD_Comparison` 需要同时开启 `Make_Plots`、`Plot_Constellation` 和 `DPD_Enable`；将增加一次真实 SLX 仿真。对照固定同一模拟 TX 系数、输入数据种子及 jitter 实现，程序会断言它们一致。没有改接收机算法；两组都只移除一个全记录固定复增益。图中上排是 DPD 前后的最终恢复星座，下排是相同区域与坐标的放大图，避免高阶 QAM 的密集点掩盖残余误差。EVM/SNDR 使用全部符号，不只计算放大区域。

```matlab
cfg = init_rfdac_model();
cfg.DAC_Bits = 10;
cfg.LO_Quadrature_Error_Deg = 1;
cfg.Plot_LPF_Response = false;
cfg.Plot_Waveforms = false;
results = run_rfdac_simulation(cfg);
% 若需要辅助图，把上述对应开关改为 true。
```

主图保存为 `results/<Run_Tag>_dpd_before_after_constellation.png`。对照结果保存在 `results.DPD_Comparison.Before_Metrics` 和 `Before_Received_Symbols`；校准后的结果仍为 `results.metrics`、`Received_Symbols`。全记录新增 `Digital_Code_Bits`、`Invalid_Output_Codeword_Pairs`、`DPD_Modified_Codeword_Pairs`、`Input_Code_Quantization_Error_RMS`、`DPD_Output_Quantization_Error_RMS` 等量化诊断，分别记录输入格式化和输出取整。`DAC_SQNR_dB` 在此版本反映输出码字取整误差；旁路时输出与输入码字相同，额外输出取整误差为零，输入格式化误差仍存在并单独报告。

运行 `validate_rfdac_codeword_plots()` 验证码字范围、原模拟非线性继续生效、五种 QAM、绘图开关及 DPD 前后对比。新结果在 `results/dpd_codewords/`，此次修改前备份在 `backups/before_dpd_codeword_plots_20261020/`。当前参数以 init 文件为准；以下 DPD 数字结果是上一版本的历史记录，尚未加上 DPD 输入码字格式化，不应当作当前版本的校准结果。

本次新版本完整实测：7 GHz、4096-QAM、TX 基准 −45 dB、16384 符号、1° 正交误差；`DPD_IQ_Enable=true`，`DPD_Nonlinearity_Enable=false`，即只校准静态 I/Q，保留 TX 压缩。对照如下：

| Jitter | DPD 前 EVM (%) | DPD 后 EVM (%) | DPD 后 EVM (dB) |
|---|---:|---:|---:|
| 关闭 | 1.030681 | 0.564072 | −44.973313 |
| 100 fs | 1.119407 | 0.715464 | −42.908244 |

DPD 输出取整的复数 RMS 误差为 0.000565135 V，包含完整仿真记录；350040 个 I/Q 码字对被修改，非法码字与输出削顶计数均为 0。关闭 jitter 时接近原 −45 dB TX 基准，符合仅校准正交误差的预期；随机 jitter 与原 TX 非线性没有被关闭。

### 正交误差并未严格归零

`DPD_Quadrature_Estimate_Deg=[]` 默认直接使用模型的真实静态误差，系数运算用 double；此处没有估计误差、漂移或系数量化。10 bit 约束的是数据幅度码字，不是将 360° 相位分成 1024 档。对未削顶码字，逆变换为 `I'=round(I+Q*tan(epsilon))`、`Q'=round(Q/cos(epsilon))`。例如输入 [100,200]，1° 理想逆需要 [103.4910,200.0305]，实际只能输出 [103,200]；经过原 LO 后得到 [99.5095,199.9695]，显然仍有残差。

`audit_rfdac_iq_residual()` 使用同一 4096-QAM、16384 符号记录，关闭 TX 压缩和 jitter 后隔离检查：

| 配置 | 最终 EVM (%) | 与理想正交接收记录的差分 RMS (%) |
|---|---:|---:|
| 理想正交、DPD 关闭 | 0.176838 | 0 |
| 1°、DPD 关闭 | 0.890380 | 0.872707 |
| 1°、准确参数、10-bit DPD | 0.182860 | 0.045412 |
| 1°、估计为 0.9°、10-bit DPD | 0.203115 | 0.099075 |

差分 RMS 通过两组各自只移除全记录固定复增益后的最终符号直接相减计算，包含校准码字量化及链路残余，不是用总 EVM 平方相减推算的独立预算项。静态 I/Q 误差被大幅抑制，但未变为零；总链路中 −45 dB TX 失真本身约 0.5623%，会掩盖较小的校准残差。8 GHz DAC、400 MHz 信号及接收滤波也意味着最终带内残差不等于原始单样本量化误差。审计数据见 `results/iq_residual_audit/iq_residual.csv`。保持模型设置不变，把 `DPD_Quadrature_Estimate_Deg` 手工设为 0.9 等值即可研究校准估计偏差。

## DPD 与静态 I/Q 校准（2026-10-20）

此前验证配置为 **7 GHz、4096-QAM、TX EVM −40 dB、正交误差 0.5°、16384 符号**。用户后续修改的参数保留在 init 中。下面的数值和 24 GHz 内容为历史对照配置。

```matlab
cfg = init_rfdac_model();
cfg.DPD_Enable = true;
cfg.DPD_IQ_Enable = true;
cfg.DPD_Nonlinearity_Enable = true;
cfg.LO_Quadrature_Error_Deg = 1;  % 可选：测试 1° 的例子
results = run_rfdac_simulation(cfg);
report = evaluate_rfdac_dpd();   % 1°，各校准组合及 jitter 开/关
```

新增 `Digital Predistortion` 子系统，位置是 **RRC 成形之后、I/Q DAC 量化之前**。接收机仍只进行原有的固定复增益校正，没有在接收端偷偷消除 I/Q 镜像或 jitter。

校准分为两项：非线性 DPD 逆变换，以及静态 I/Q 逆变换。1° 正交误差属于线性 I/Q 不平衡，使用第二项即可校准；联合模式同时补偿 TX 压缩。

对于原有实数 RF 模型 `atan(sqrt(beta)*x)/sqrt(beta)`，正弦包络 A 的基波响应为：

```text
F(A) = 2*A/(1+sqrt(1+beta*A^2))
F_inverse(R) = R/(1-beta*R^2/4)
v = u/(1-beta*abs(u)^2/4)
```

随后对四相 LO 的静态等效映射 `y=alpha*x+image*conj(x)` 进行数字逆变换：

```text
x = (conj(alpha)*v - image*conj(v))/(abs(alpha)^2-abs(image)^2)
```

仅有 epsilon 正交误差时，等价于 `Q_drive=Q/cos(epsilon)`、`I_drive=I+Q*tan(epsilon)`。顺序是先做包络非线性逆变换，再做 I/Q 逆变换。不是直接对基带逐点应用 RF 的 tan 逆函数，也不是把逆函数放在模拟混频器之后。

这是 **已知模型参数下的乐观校准参考**，用于观察本模型的校准上限；当前没有实测回授、参数辨识、在线自适应或器件漂移。包络逆变换只补偿 RF 基波；重构滤波和 DAC 保持造成的记忆/带宽效应未被全局逆置，因此不能声称是任意 DPD 算法的绝对最优。

默认 `DPD_TX_Beta_Estimate=[]` 和 `DPD_Quadrature_Estimate_Deg=[]` 使用模型已知的静态参数。手工填写估计值可研究校准偏差。`DPD_Phase_Errors_Estimate_Deg` 可设置四相独立偏差的估计；空值使用实际配置。自动 TX EVM 标定始终针对 **未启用 DPD 的物理 TX**，校准开关不会重新调坏物理 TX 以抵消 DPD 收益。

`DPD_Max_Gain=2` 默认限制非线性逆变换增益，避免接近逆函数奇点时发散。预失真引入功率扩展，可能造成 DAC 削顶，不能无条件强行反演。结果新增完整记录的 `DPD_Drive_Power_Expansion_dB`、`DPD_Max_Actual_Gain`、`DPD_Limited_Samples`、`DPD_DAC_I_Clipped_Full`、`DPD_DAC_Q_Clipped_Full`。量化误差按 **DPD 后真正送入 DAC 的数字信号**计算。

DPD 不读取、预测或预先消除随机 jitter。`evaluate_rfdac_dpd` 同时给出 jitter 关闭时的确定性校准结果，以及保留 100 fs 时的实际误差限制，并与理想线性 TX 参考比较。还验证独立随机种子、估计误差、过驱动限幅和 24 GHz 历史案例。

新增辅助文件 `rfdac_prepare_dpd.m`、`rfdac_dpd_apply.m`、`rfdac_dpd_block.m`、`update_rfdac_dpd_model.m` 必须保留。比较图/CSV/MAT/验证报告保存在 `results/dpd_evaluation/`。修改前文件备份在 `backups/before_dpd_20261020/`。

本机完整运行：7 GHz、4096-QAM、TX 基准 −40 dB、1° 正交误差、16384 符号，默认理想接收 LO。下表两列分别关闭 jitter 和加入 100 fs jitter，使用相同的物理 TX 系数与数据：

| 校准模式 | 无 jitter EVM (%) / dB | 100 fs EVM (%) / dB |
|---|---:|---:|
| 关闭 DPD | 1.31651 / −37.612 | 1.38705 / −37.158 |
| 仅 I/Q 校准 | 0.99980 / −40.002 | 1.09211 / −39.235 |
| 仅非线性 DPD | 0.85957 / −41.314 | 0.96414 / −40.317 |
| 联合校准 | 0.17651 / −55.064 | 0.47399 / −46.485 |
| 理想线性、无正交误差参考 | 0.17684 / −55.048 | 0.47420 / −46.481 |

联合校准已接近本模型的线性参考。无 jitter 时主要剩余 DAC/滤波误差；开启 jitter 时随机相位误差继续保留。联合校准的数字驱动功率扩展约 0.258 dB，正常工况的增益限幅与全记录 DAC 削顶计数均为 0。独立种子、校准估计偏差、过驱动保护及一般四相误差逆变换均已验证。另以 24 GHz、1024-QAM、TX −43 dB、2048 符号复核，联合 DPD 后无 jitter / 100 fs 的 EVM 为 0.17708% / 1.59086%；该短记录与下方历史完整记录应分别比较。

背景参考：[MathWorks 数字预失真](https://www.mathworks.com/help/comm/ug/digital-predistortion-to-compensate-for-power-amplifier-nonlinearities.html)、[I/Q 不平衡补偿](https://www.mathworks.com/help/comm/ref/comm.iqimbalancecompensator-system-object.html)。本工程使用上述显式模型逆变换，并未实现参考页面中的回授训练流程。

以下为历史配置说明：24 GHz、1024-QAM、400 MHz 总信号带宽、16384 符号。MATLAB/Simulink R2024a。运行这些历史未校准对照时，请显式设置 LO、QAM 和 `DPD_Enable=false`。

## 运行

```matlab
cfg = init_rfdac_model();
cfg.LO_Frequency = 24e9;
cfg.QAM_Order = 1024;
cfg.DPD_Enable = false;
cfg.TX_Target_EVM_dB = -43;
cfg.LO_Quadrature_Error_Deg = 1;
cfg.LO_RMS_Jitter = 100e-15;
results = run_rfdac_simulation(cfg);
report = evaluate_24g_tx_budget(); % 单项、组合、数值验证
sweep = sweep_lo_jitter(cfg);
```

编辑初始化文件后重新加载 cfg，避免沿用基础工作区中的旧参数。全部辅助 .m 文件须与 SLX 同目录。修改前版本保存在 backups/before_tx_evm_20261017/。

## 模型与标定

随机 Gray QAM → RRC → 独立 10-bit I/Q DAC → 零阶保持 → 重构 FIR → 四相正交混频 → TX EVM Nonlinearity → 理想/共享/独立 LO 接收 → 抗混叠 FIR → 抽取、匹配 RRC、定时 → QAM 解调/EVM。

用户确认：TX EVM = −43 dB 是 jitter 关闭、正交完全理想时的整体 TX EVM，包含 DAC/滤波误差，对应 0.707946% RMS。随后额外加入 jitter 与静态正交误差，避免重复计入。

单个 EVM 值不能唯一反推 AM/AM、AM/PM、IP3 或记忆效应。本程序在指定的平滑 atan 模型族中拟合失真强度，用于系统估算；拟合系数不能当作器件实测物理参数。

```text
y = atan(sqrt(beta)*x)/sqrt(beta), beta >= 0
beta=0 时 y=x；dy/dx=1/(1+beta*x^2)>0
```

旧的固定 1 dB Gm 模型已停用。rfdac_fit_tx_evm 使用完整随机记录、相同的因果 DAC/FIR/RF/接收数学链路，在 jitter=0、正交误差=0 时搜索 beta。FFT FIR 只是加速因果卷积，并非零相位滤波。SLX 再测量核实标定。目标低于 DAC/滤波误差底噪时明确报错。改变 QAM、幅度、位数、滤波、采样率、符号数、种子或目标会重新标定；只改变 jitter/正交误差时复用 beta。

| 参数 | 含义 |
|---|---|
| TX_Target_EVM_dB | 历史 −43 dB，当前初始化 −40 dB；整体干净 TX 基准 |
| TX_Nonlinearity_Enable | false 旁路软压缩，保留 DAC/滤波误差 |
| TX_Nonlinearity_Beta | [] 自动拟合；非负数字固定系数 |
| TX_EVM_Fit_Tolerance_dB | 默认 0.01 dB |
| LO_Quadrature_Error_Deg | 历史案例 1°，当前初始化 0.5° |
| LO_Quadrature_Error_Enable | 开关静态相位误差 |
| LO_Phase_Errors_Deg | [0 0 0 0]，四条支路附加偏差 |

结果中 TX_Beta、TX_Calibration 记录系数、目标、实现值、线性底噪及标定符号数。

## 四相 LO

相位默认为 0°、90°+epsilon、180°、270°+epsilon；epsilon=1° 时是 0°、91°、180°、271°。I=(LO0−LO180)/2，Q=(LO270−LO90)/2，RF=I_DAC*I−Q_DAC*Q。每个差分对保持反相。四条支路使用正弦，不包含开关混频器占空比/边沿模型。

正交误差属于线性 I/Q 不平衡，产生共轭镜像；jitter 是相位误差，TX 压缩是幅度非线性。1° 正交误差在近似圆对称符号和单个固定复增益校正下，EVM≈tan(0.5°)=0.872687%。这不是整个星座固定旋转 1°，后者会被相位校准去除。

## Jitter、采样与测量

phi=2*pi*fLO*t+2*pi*fLO*timing_jitter。默认 100 fs、5 MHz 单极点相关高斯过程：a=exp(−2*pi*BW/Fs)，j[n]=a*j[n−1]+sqrt(1−a²)*w[n]，按稳态初始化。不是累积频率噪声，也不是砖墙限带。Jitter_Mode='white' 每个 RF 样本独立。数据/TX/RX 的种子为 Random_Seed、+1、+2。四相共享 TX jitter；接收 LO 支持 ideal/shared/independent，共享模式表示零相对路径延迟。接收机没有相位跟踪。

24 GHz、100 fs 对应 0.01508 rad RMS，小相位近似 jitter EVM≈1.508%。滤波、固定相位去除和有限记录统计会改变实际值。各项误差相关时平方和根只是量级估计，以完整仿真为准。

QAM 为单位平均星座功率、Gray 映射；RRC 滚降 0.25，符号率 320 MBaud。DAC 为 8 GHz，码字 −512…511、满量程 ±1 V。TX/RX Blackman FIR 和匹配 RRC 均为因果滤波，补偿保持和滤波群时延。Sample_Rate_Auto=true 时 24 GHz 自动采用 160 GHz RF 采样率、2048 阶收发 RF FIR；每帧 500 个连续 RF 样本。求解器帧率不是 RF 采样率。无限高次谐波仍须通过固定 beta 的 160/320 GHz EVM 收敛核查。

Waveform_Log_Frames=128 默认保存末尾 128 个连续帧的波形，Inf 保存全部。EVM、SER 和 jitter RMS 使用完整记录；波形/PSD 使用连续预览及真实时间起点。DAC RMS、削顶计数和 RF 峰值为预览统计，Diagnostics_Cover_Full_Record 指明是否覆盖全记录。LO 逐帧生成，减少内存占用。

```text
g = sum(conj(reference).*received)/sum(abs(reference).^2)
z = received/g
EVM = rms(z-reference)/rms(reference)
EVM_percent = 100*EVM
EVM_dB = 20*log10(EVM)
Estimated_SNR_dB = -EVM_dB
```

只移除全记录一个固定复增益，不补偿逐符号相位或 I/Q 镜像。Estimated SNR 严格说是 EVM 等效 SNDR，包含全部噪声/失真/残余滤波误差，未额外添加 AWGN。

## 验证与文件

evaluate_24g_tx_budget 运行线性底噪、TX 标定、正交单项、jitter 单项、TX+正交、TX+jitter、全部叠加七种情况；另检查五种 QAM、目标改变、低于底噪目标的拒绝和固定 beta 的采样收敛。结果在 results/tx_evm_24g/，包括 impairment_budget.csv/.png、impairment_constellation_comparison.png、evaluation_report.txt/.mat 和两组完整结果/图形。实际数值以生成报告为准。

update_rfdac_evm_model 升级现有 SLX 的 TX/LO 子系统，保留其他子系统和布局；build_rfdac_model 可重建。保留 rfdac_prepare、rfdac_fit_tx_evm、rfdac_lo_stream、rfdac_model_init、rfdac_measure、rfdac_resolve_sampling 和 QAM 辅助文件。Normal simulation 使用 Level-2 MATLAB S-function，不要求外部 C 编译器。

依赖 MATLAB、Simulink、Signal Processing、DSP System、Communications 工具箱，已再次检查本机安装，见 matlab_24g_environment.log。

参考：[MathWorks I/Q 不平衡](https://www.mathworks.com/help/comm/ug/visualize-rf-impairments.html)、[EVM 测量](https://www.mathworks.com/help/comm/ref/evmmeasurement.html)。

## 本机实际运行结果

完整 1024-QAM、16384 符号，24 GHz，jitter 配置 100 fs（实测完整记录 RMS 99.278 fs）：

| 情况 | EVM (%) | EVM (dB) | SNDR (dB) |
|---|---:|---:|---:|
| 干净 TX 标定 | 0.707946 | −43.000000 | 43.000000 |
| TX + 1° 正交误差 | 1.115333 | −39.051907 | 39.051907 |
| TX + 100 fs jitter | 1.632958 | −35.740498 | 35.740498 |
| TX + 正交误差 + jitter | 1.845972 | −34.675496 | 34.675496 |

自动拟合 beta=0.4175208477 V^-2，线性链路误差底噪 −55.036547 dB。全部叠加时 411/16384 个符号判错，SER=2.508545%。这是本次波形和无相位跟踪接收机的结果，不表示任意接收算法的极限。

七组误差分解、全部五种 QAM 的目标标定、目标改为 −38 dB、无法达到的 −80 dB 目标拒绝均通过。固定 beta 的 160/320 GHz 采样率对比仅差 0.00003824 dB EVM。详见 results/tx_evm_24g/evaluation_report.txt 和 impairment_budget.csv。
