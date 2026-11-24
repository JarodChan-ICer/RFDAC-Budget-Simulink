# 按芯片实测 PPT 实现的二维 LUT DPD

来源为用户提供的 `DPA_cs_260920.pptx` 第3–9页。原 PPT 未修改。

## PPT 与程序的对应

| PPT | 实测步骤 | 当前实现 |
|---|---|---|
| 第4页 | 16384QAM原输入经RF-DAC，测得畸变响应，再插值形成2D LUT | `rfdac_lut_grid` 建立128×128码点；`rfdac_train_link_lut` 通过实际SLX采集；`rfdac_build_ppt_lut` 插值为1024×1024合法DAC驱动的响应 |
| 第5页 | 目标点a → 最近输出点b → b对应的原输入点c | 对每个目标DAC码预先搜索最近的插值响应b，存储其对应驱动c；`rfdac_dpd_lut_lookup` 按每个基带采样访问 |
| 第6页 | 带前导零的蛇形线 → 取完整一帧 → 解调和相位对齐 | 实际发送零段、蛇形码点、零段；从真实接收复包络检测零段，结合已知蛇形相关定位帧，再用已知输入与实际观测估计共同相位 |
| 第7页 | 前后EVM实测对照，示例3GHz、100MBaud | 保留当前7GHz、320MBaud主配置，固定物理β和相同业务数据/jitter比较OFF/ON；不把PPT的约5dB收益当作仿真必须达到的数值 |
| 第9页 | 无记忆2D LUT在300MBaud以上改善受限 | 保留RRC/模拟滤波器等记忆效应及真实业务链路，用独立业务数据测量残差，不引入解析模型替代反馈 |

PPT只说明了插值、前导零、蛇形线和相位对齐，没有给出插值核、每点保持长度、零段长度或检测代码。工程采用以下可调整的实现选择：**线性前向插值、每点保持25个DAC更新、请求前后各512个零采样、重复2个完整帧、相位对齐而不拟合消除幅度压缩**。RX 均衡器启用后，训练与验证均在相同的均衡后、匹配 RRC 前观测；零段会按实际滤波支持长度自动延长，当前默认为954个 DAC 采样，并保存实际长度。这些数值是仿真实现参数，不是从PPT中推断出的芯片设置。

## 使用方法

```matlab
cfg = init_rfdac_model();
cfg.QAM_Order = 4096;
cfg.DPD_Algorithm = 'lut';
cfg.DPD_LUT_Training_Mode = 'link';
cfg.DPD_LUT_Training_Order = 16384;
cfg.DPD_LUT_Interpolation = 'linear';
results = run_rfdac_simulation(cfg);
```

首次运行自动采集、对齐、建表，再运行业务及可选的DPD OFF对照。相同物理参数和训练设置可以复用同一MATLAB会话的捕获及建表缓存；配置改变则使旧训练失效。直接点击SLX的Run之前，先通过上述入口完成训练。

## 训练和业务处理位置

**训练：**零前导 + 128×128蛇形原始DAC码 → N-bit DAC/ZOH → TX重构滤波 → 实际IQ/jitter混频 → RF非线性 → RX相干下变频/低通 → DAC速率复包络 → 配置的 RX 均衡 FIR → 检帧 → 每点取中部样本均值 → 每帧相位对齐 → 同点多帧平均。

蛇形线的相邻点只沿一个I/Q轴变化，每列扫描方向交替；相比随机训练符号，它避免在整个码平面任意跳跃。原始训练码点直接注入DAC之前，因此训练时绕过TX RRC，观测位于RX匹配RRC之前。这样表征的是PPT中的“基带码点到RF-DAC输出复包络”映射。训练仍经过实际DAC、ZOH、模拟收发滤波、RF非线性、IQ与jitter，未使用静态基波公式生成响应。

**业务：**4096QAM → 上采样/TX RRC → N-bit目标采样a → 二维LUT反查输入c → N-bit DAC/ZOH → 相同RF链路 → RX低通/匹配RRC → 时延校正/符号恢复 → EVM/SER。

业务TX/RX RRC完整保留。查表在TX RRC之后，处理每个DAC速率采样，不再将业务QAM符号限制为原始16384训练点之一。

## 插值和反查

16384个**真实测量点**形成规则的输入坐标网格。对它们对应的复数输出做二维线性前向插值，得到当前10-bit DAC的1024×1024个合法整数码对所对应的预测输出。插值不会创造分数DAC码，也不会在未训练的输入矩形外外推。

随后，对全部合法目标码a进行**精确最近邻搜索**：在这些插值输出中选择距离a最近的b，并存储b对应的整数驱动c。运行时只按目标I/Q码访问已冻结的反查索引，不执行解析逆模型、迭代辨识或读取即时jitter。最近邻优先使用Statistics Toolbox的KD树；没有该工具箱时使用MATLAB的Delaunay精确搜索，临时内存和建表时间较大。

这与“只在原始16384个输出中选点”不同：原始点数仍为16384，但插值后的候选DAC码对为1048576，因此不再额外引入128级码本网格的分辨率限制。物理DAC本身仍是10-bit。

`sweep_dpd_lut`扫描的是原始训练点数量，报告中的`LUT_Points`沿用这一含义；新增`Dense_Candidate_Points`单独表示插值后的候选数量。训练点变少不会自动缩小当前10-bit稠密运行表的地址空间。

共同相位从已知蛇形输入与真实接收点估计，不读取真实LO相位误差或模型IQ参数；相位对齐保留幅度压缩。最终业务EVM继续沿用工程原有的单一复增益拟合口径。RX观测链路幅度视为已标定的物理V；外部硬件捕获需要自行完成采样率、时钟、量纲和幅度标定。

## 参数、结果和限制

- `DPD_LUT_Training_Dwell_Samples=25`：每个蛇形点保持的DAC更新次数，中部采样用于估计响应。
- `DPD_LUT_Training_Prefix_Zeros=512`：每帧蛇形前后的请求零段；不足以覆盖收发滤波与 RX 均衡器时自动延长，实际值保存在 `Prefix_Zero_Samples`。
- `DPD_LUT_Training_Repeats=2`：完整帧数，保存每帧观测、相位和平均散布。
- `DPD_LUT_Drive_Range=1`：覆盖完整合法DAC输入范围；减小它会缩小可校正区域，超出范围的目标只能选最近的边界输出。
- `DPD_LUT_Training_Observed`：可导入按`ndgrid(I,Q)`排列、已完成相位与量纲对齐的复数反馈；不得输入硬判决或误差增量。外部观测应同时清空`DPD_LUT_Training_Metadata=struct()`。
- `DPD_LUT_Training_Metadata`：保存实际复包络、检测到的帧、零段RMS、蛇形顺序、中部取样位置、逐帧相位、逐点观测与配置指纹。完整物理β在训练和业务阶段冻结，建表不使用β或IQ估计参数。
- `results.DPD.LUT.Training_Output`为原始16384个对齐测量均值；`Dense_Output`为插值后的1048576个响应；`Inverse_Index`为目标码a到原输入c的反查索引。
- 当前稠密二维实现支持每轴不超过10-bit。10-bit直接映射的20-bit输入地址、20-bit输出码字载荷为2.5 MiB；训练数据、插值响应和主机搜索辅助数组另计，不再声称完整LUT仅40 KiB。

普通运行仍写入`outputs/results/`的`single_results.mat`、`single_metrics.csv`和三宫格对比图，训练数据另存`single_dpd_link_training.mat`。下方星座面板显示插值输出网格和实际选用的响应点；为控制绘图时间，背景最多显示60000个网格点，实际访问计数保持完整。

这是无记忆2D LUT，无法消除所有频率相关/动态非线性、滤波记忆和随机jitter。PPT所示收益只属于其特定测试设置，不是本工程的验收门槛。link模式支持联合校准，以及 `DPD_IQ_Enable=true`、`DPD_Nonlinearity_Enable=false` 的仅 IQ 校准。后者从实测输出方向拟合线性 IQ 几何，保留 TX 的径向非线性，不是简单给联合逆表关闭一个标志；方法与42 dB验证见 [IQ_ONLY_CALIBRATION.md](IQ_ONLY_CALIBRATION.md)。仅非线性单项的实测分离仍不支持。独立RX参数辨识实验仍使用显式`static`参考模式。

## 验证

2026-11-08新增的指定工况为7 GHz、100 fs、TX SNR45 dB、IQ1°–3°、16384实测训练点与4096QAM。运行 `run_rfdac_iq_mismatch_sweep()` 可逐角度完成“实测16384输出 → 插值映射4096输入 → 实际4096蛇形输出”，并独立测量RRC业务EVM。详见 [IQ_MISMATCH_SWEEP.md](IQ_MISMATCH_SWEEP.md)。下面2026-11-02数值保留为当时参数下的历史结果。

```matlab
setup_rfdac_project();
validate_rfdac_ppt_lut(false);   % 实际RF小码本流程、合成帧/相位、插值节点和独立最近点校验
validate_rfdac_ppt_lut(true);    % 当前1°配置，完整16384点训练 + 4096QAM业务
validate_rfdac_ppt_lut(true,30); % 30°大IQ误差对照
validate_rfdac_link_lut_integration(); % 保存/直接运行/失效重训/阶数与新模型生成
validate_rfdac_trained_lut();    % 显式static参考回归
```

本轮验证保存到`outputs/validation/ppt_dpd_20261102/`。修改前源码和SLX位于`outputs/validation/before_ppt_dpd_20261102/`。前一版随机符号训练和有限16384点符号映射的结果仅作历史对照，不代表当前PPT流程。

2026-11-02已完成7GHz、320MBaud、100fs jitter、10-bit DAC下的完整验证：16384个原始训练点、每点25个DAC更新、2个蛇形帧；4096QAM业务共16384符号。物理β固定为0.469191101183668 V⁻²，DPD OFF/ON业务数据和jitter完全相同。

| IQ误差 | DPD OFF EVM | PPT LUT ON EVM | OFF SER | ON SER |
|---|---:|---:|---:|---:|
| 1° | 1.171232% | 0.190505% | 2.825928% | 0/16384 |
| 30° | 26.232753% | 0.185678% | 99.627686% | 0/16384 |

精简运行表对完整1°业务的再次RF仿真，与完整测量表的接收符号最大差为0。保存/自动前后对照、直接SLX运行、估计参数无效化测试、物理参数/训练阶数变化后重训、qam_multiple兼容入口、新建模型生成均通过。精确指标见`verified_comparison.csv`，完整报告为`final_validation.mat`；1°、30°图分别为`full_dpd_before_after_constellation.png`、`full_iq_30_dpd_before_after_constellation.png`。

这些是当前仿真模型和有限业务记录的结果，不是对芯片EVM或误码率的预测。工程的−42dB干净TX目标是对确定性atan非线性所做的标定，不是不可补偿的AWGN底噪，因此校正后可以优于该数值。真实芯片的频率相关非线性、其他记忆效应及观测误差可能限制收益；PPT第9页关于高波特率的实测结论仍应保留。
