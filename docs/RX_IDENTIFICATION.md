# RX 辨识与四种校准验证

## 运行

```matlab
report = run_rfdac_identification();
```

该入口独立读取 `init_rfdac_identification.m`，不需要先运行或修改 `init_rfdac_model.m`。当前配置为 TX EVM −42 dB（等效 SNR +42 dB）、10 GHz、100 fs、1°、4096-QAM。下面的 40 dB 是显式修改参数的示例：

```matlab
[cfg,opt] = init_rfdac_identification();
cfg.TX_Target_EVM_dB = -40;       % 干净 TX 的 EVM 等效 SNR 为 +40 dB
cfg.LO_Frequency = 10e9;
cfg.LO_RMS_Jitter = 100e-15;
cfg.LO_Quadrature_Error_Deg = 1;
opt.Figure_Visible = 'on';       % 默认 on：显示并保存图；off：只保存 PNG
opt.Monte_Carlo_Repeats = 0;     % 默认 0：主辨识一次；5 => 另加 5 次，共 6 次
report = run_rfdac_identification(cfg,opt);
validation = validate_rfdac_identification(report);
```

修改工作区中的 cfg/opt 后，必须把它们显式传给 `run_rfdac_identification(cfg,opt)`。无参调用会重新加载辨识 init，忽略工作区中的修改；只传 cfg 则使用默认 opt。两套 init 共用纯基础默认值，但互不调用；辨识程序的缺省字段也不会从日常 init 补入。需要刻意沿用日常模型参数时，可以运行 `cfg = init_rfdac_model(); [~,opt] = init_rfdac_identification(); report = run_rfdac_identification(cfg,opt);`。

`cfg` 决定被测器件、采样、QAM 和 LUT 格式；`opt` 决定辨识采集/验证长度、重复次数、输出目录以及辨识图的可见性。这里最终图的开关是 `opt.Figure_Visible`，不是 `cfg.Make_Plots` / `cfg.Plot_Constellation`。后两者被流程关闭以免每次内部采集都弹出普通链路图；最终三张辨识图仍会统一生成。验证符号数由 `opt.Validation_Symbols` 决定，训练符号数由 `opt.Training_Symbols` 决定；四种校准的启用组合由流程固定，覆盖 cfg 中的 DPD_Enable/IQ_Enable/Nonlinearity_Enable。

此前版本默认 `opt.Figure_Visible='off'`，因此不弹窗，但图已经保存。显示最新默认目录中的已有结果，无需再训练或仿真：

```matlab
show_rfdac_identification();
% 也可以指定内存中的报告或另一个 MAT 文件
show_rfdac_identification(report);
show_rfdac_identification(fullfile('outputs','validation','rx_identification', ...
    'identification_report.mat'));
```

重绘会重新导出报告旁的 PNG，不修改报告中的数据或辨识结果。`run_rfdac_identification` 需完整运行到结束才会生成最终图；中途停止不会得到完整四宫格。

主结果为 `outputs/validation/rx_identification/identification_four_cases.png`。一张四宫格按顺序显示“仅 TX 非线性校准、仅静态 I/Q 校准、联合校准、完全不校准”，每格都是完整真实 SLX 输出经过原接收机得到的最终符号，叠加理想参考点并标注 EVM/MER。高阶 QAM 增加同一角落区域的放大 inset，EVM 使用所有符号计算。

另有 `identification_estimates.png` 显示真值、估计值和模型条件 95% 置信区间；`identification_reliability.png` 显示小摆幅外推和主辨识区间。启用重复辨识时，后者还显示各次估计及经验覆盖率；默认单次运行会注明重复性未评价。MAT、CSV 与文本报告保存在同一目录。

历史 40 dB 案例的完整实测仿真结果（white jitter、4096-QAM、16384 验证符号、额外 5 次辨识；不是当前 −42 dB 配置的输出）：

| 辨识量 | 配置真值 | RX 估计 | 条件 95% 区间 |
|---|---:|---:|---:|
| 干净 TX EVM 等效 SNR (dB) | 40 | 39.998392 | [39.983482, 40.013332] |
| 有效静态 I/Q 相位误差 (deg) | 1 | 1.002508 | [0.991779, 1.013238] |

6 次独立训练的 TX SNR 估计 RMSE 为 0.003100 dB，I/Q 估计 RMSE 为 0.002903°。此组试验的区间覆盖 6/6，样本很少，不应解释为已证明任何硬件都具有 95% 覆盖率。

| 使用冻结 RX 估计值的校准模式 | 最终 EVM (%) | 最终 MER (dB) |
|---|---:|---:|
| 仅 TX 非线性 | 0.862650 | 41.283310 |
| 仅静态 I/Q | 1.004898 | 39.957561 |
| 联合校准 | 0.194015 | 54.243296 |
| 不校准 | 1.315031 | 37.621282 |

没有改成理想器件：四组的真实 TX beta、1° 正交误差、jitter 设置/实现及验证符号完全相同；DPD 仅改变有限精度数字码字，全部输出合法且未削顶。这组校准后高 MER 与 RF 样本独立的 white jitter 及带内接收滤波有关，不是声称消除了随机 jitter。

## “不知道 TX 性能”的边界

这里实现的是**已知结构、未知参数**的辨识。RX 事先不知道 TX 的 SNR 数值、压缩强度 beta 和正交失配角度；也不获得真实的 jitter 序列。但仍有以下前提：

- 静态 I/Q 混合及无记忆 RF atan 压缩是所选模型族；参数数值未知。
- DAC 位宽/满量程、已发送码字、采样时钟、已知训练序列及名义 TX/RX 线性滤波/时延是公开或经过标定的。
- 观测接收链是已校准的相干线性链路。本实验还额外施加未知观测增益 0.83 和未知 DC 偏置 0.003，估计器自行拟合，不能直接使用它们。
- jitter 是零均值平稳高斯过程，RMS 已知。辨识使用自己的 `cfg.Jitter_Mode`（white/bandlimited）设置，并在报告中记录。

这不是“任意未知 TX，只给一个总 EVM 和 100 fs，就能唯一反推出所有物理误差”的承诺。若 RX 自身有未知失配、名义滤波不准或 TX 模型不属于所用族，置信区间不包含这些系统偏差，需要另做校准、模型扩展和模型失配验证。

辨识观测是模型 RF 接收端口的高采样率实数波形，保留所用仿真采样带宽，并非只输入一张星座图或一个总 EVM。实测若只提供窄带复基带/解调符号，应使用对应观测带宽与接收滤波的前向模型重新辨识，不能直接套用这里的精度保证。当前 TX 模型中 I/Q 路径名义匹配，估计的有效静态 I/Q 误差才与设置的 LO 正交偏差对应；真实芯片还需排除 DAC/LPF/观测 RX 失配的贡献。

## 数据隔离

仿真器先在正常摆幅下标定实际 TX，使 jitter=0、理想正交、关闭 DPD 时达到 `cfg.TX_Target_EVM_dB`；随后把实际 beta 固定。降低训练摆幅时不会重新拟合一个“仍达到同一目标 EVM”的 TX。所有训练、Monte Carlo 和四种校准都使用同一个物理器件参数。

估计器 `rfdac_identify_tx(captures,meta,options)` 只接收：

- `captures`：每次训练的 `Codes`、`RF`、`Start_Time`、`Amplitude`。
- `meta`：白名单中的名义线性路径、时钟、训练符号、DAC 格式及已知 jitter 统计。
- `options`：估计器采样数和聚类长度等数值选项。

不会传入完整 cfg、prepared p、真实 beta、失配角度、目标 SNR、RF 非线性前波形或实际 LO phase-error 数组。`training_observations.mat` 保存独立的白名单数据包，便于审计和替换为实测数据。含真值的 report 只在仿真器/评分器一侧组装。

## 小摆幅与工作摆幅

默认用 0.07、0.10、0.14 三个幅度系数采集小信号数据，工作幅度系数为 0.35。每次发送已知 4096-QAM，训练码字仍是实际 10-bit 码字。捕获相同时间窗的输入码字和 RF 观测，不读取内部模拟节点。

估计器使用已知码字和名义线性滤波重构输入基函数，并舍弃截断记录的 FIR 初始瞬态。小摆幅拟合 I/Q 两条通道的 cos/sin 线性响应与 DC，由两条复响应的相对角度估计有效正交误差。为减少小摆幅仍存在的压缩偏差，再对三组估计随输入功率的变化向零功率外推。

固定该 I/Q 估计后，在工作摆幅下拟合未知 beta。观测增益、DC 和公共相位作为 nuisance 参数独立估计。三点高斯积分近似计算已知 RMS jitter 下的条件均值响应，不使用实际 jitter 样本，也不会把一次偶然落到理想点的散点作为可重复补偿值。

得到 beta 后，`rfdac_predict_clean_tx` 只根据估计参数、公开参考符号和标称线性链路，重放 TX RRC、DAC/ZOH、收发低通、RX RRC 和定时，预测 jitter 关闭、理想正交时的完整干净 TX EVM/MER。该步骤不读取目标 dB 值。真实 TX 的 SLX 评分仿真在估计值冻结之后执行。

## SNR 与随机噪声

与本工程此前约定一致，正的 TX SNR 表示 `-20*log10(EVM)`，即包含 DAC、滤波与确定性压缩误差的等效 SNDR/MER。此次“校准 TX SNR”指校准其确定性 TX 非线性，不能逆置独立 AWGN 或消除随机 jitter。

不能简单将 `2*pi*fLO*sigma_t` 的平方从最终解调 EVM 平方中扣除：该值是原始相位 RMS，经过滤波和符号接收后的带内误差取决于 jitter 的频谱/相关性。报告额外计算一个故意简化的功率相减结果作为反例，不用它辨识或训练 DPD。

本次把原始 jitter RMS 和理论 I/Q 项直接从未校准 EVM 平方中相减，会得到约 42.448 dB，而真实基准为 40 dB。该错误做法没有正确处理接收带宽与误差相关性。

例如同为 100 fs，`white` 与 5 MHz `bandlimited` jitter 的校准后 EVM 可以明显不同。改变时可使用：

```matlab
[cfg,opt] = init_rfdac_identification();
cfg.Jitter_Mode = 'bandlimited';
cfg.Jitter_Bandwidth = 5e6;
opt.Output_Directory = fullfile(opt.Output_Directory,'bandlimited');
report = run_rfdac_identification(cfg,opt);
```

也可在已有主报告基础上运行 `extra = evaluate_rfdac_identification_jitter(report);`，只做另一种 jitter 频谱的少量训练和未校准/联合校准对照，保存 `jitter_sensitivity.csv`。该补充试验的记录长度会在表中单列；同一频谱下的前后校准始终使用相同输入和 jitter 实现。

已完成的 5 MHz bandlimited 补充试验（2048 符号训练、4096 符号验证）得到 TX SNR 39.997787 dB、I/Q 误差 1.018131°，条件区间分别为 [39.992376,40.003202] dB 和 [0.977929,1.058333]°，均包含真值。未校准 / 联合校准 EVM 为 1.444256% / 0.649605%。其随机相位误差没有被 DPD 消除，尽管已知 timing jitter RMS 与主实验同为 100 fs。主/补充记录长度不同，所以该对照用于说明频谱相关性与残余误差的关系，不是逐样本一一对应的误差分解。

## 校准、验证与可信度

辨识结果冻结后，四种模式都显式传入非空的 beta 与 I/Q 估计值，避免现有“空值自动读取真实模型参数”的便捷接口导致真值泄露。实际 TX、数据种子与 jitter 实现固定不变；验证序列不同于训练序列。最终使用 16384QAM 有限训练码本，每项是绝对 10-bit I/Q DAC 字，不存补偿增量或插值。静态码本观测由冻结的估计参数生成，不再读取实际参数；原非线性和正交误差继续存在。这里的 RX 参数辨识训练与有限码本的静态点表征是两个步骤，见 [TRAINED_LUT.md](TRAINED_LUT.md)。

置信区间使用按时间分块的 cluster-sandwich 协方差，小摆幅 I/Q 估计的不确定性进一步传播到 beta 区间，再通过干净 TX 预测映射到 SNR 区间。默认每块 32 个符号；它适合当前 white/5 MHz 相关模型，若相关性更长，应增大块长并增加记录。

一次完整辨识包含三组小摆幅和一组工作摆幅的采集。`opt.Monte_Carlo_Repeats` 指额外完整重做的次数，不是同一套系数的迭代次数。每次更换输入/jitter 随机种子，保持真实器件参数不变，重新采集和拟合，以统计相对于仿真真值的估计偏差、RMSE 和条件区间的经验覆盖率。实际测量没有真值时，可以比较估计的重复性，不能直接算真值偏差或覆盖率。

四种校准始终只使用最初主辨识的冻结参数，不取多次结果的平均，不挑选最好的一次。默认 `opt.Monte_Carlo_Repeats=0` 已足够得到参数估计和四宫格；单次拟合仍给出模型条件置信区间，但不评价重复性，重复统计在报告中为 NaN。设为 5 则总计 6 次完整辨识，用于初步可信度检查，并增加运行时间。

6 次试验仍不能证明实际硬件具有 95% 的覆盖保证。更充分的论证应增加试验次数、温度/频率/摆幅范围以及观测链与模型失配测试。

参考：[ADI I/Q 调制器校准](https://www.analog.com/en/resources/app-notes/an-1039.html)、[MathWorks EVM/MER 测量](https://www.mathworks.com/help/comm/ug/measure-modulation-accuracy.html)。
