function [f,usage]=plot_rfdac_lut_selection(results)
% Show the finite training codebook and its actually selected subset in red.
usage=rfdac_lut_usage(results);
c=results.cfg; lut=results.DPD.LUT;
drive=complex(double(lut.Output_I(:)),double(lut.Output_Q(:)))*results.DPD.LSB;
response=lut.Training_Output(:);
if strcmp(lut.Format,'ppt_measured_2d_lut_v1'), response=lut.Dense_Output(:); end
f=figure('Name','LUT 训练点与实际选点','Color','w','Position',[60 70 1330 680], ...
    'Visible',c.Figure_Visible,'Renderer','painters');
layout=tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
values={drive,response}; names={'训练输入点','对应的训练解调输出'};
if isfield(lut,'Calibration_Mode') && strcmp(lut.Calibration_Mode,'iq_only')
    names{2}='仅 IQ 拟合映射响应（TX 非线性保持）';
end
for k=1:2
    ax=nexttile(layout);
    z=values{k};
    plot(ax,real(z),imag(z),'.','Color',[.76 .79 .82],'MarkerSize',5); hold(ax,'on');
    plot(ax,real(z(usage.Mapped)),imag(z(usage.Mapped)),'.','Color',[.87 .12 .14],'MarkerSize',6);
    axis(ax,'equal'); grid(ax,'on'); box(ax,'on');
    ax.GridAlpha=.12;
    xlabel(ax,'I / V'); ylabel(ax,'Q / V');
    title(ax,names{k},'FontWeight','bold');
    legend(ax,sprintf('全部 %d 个训练点',usage.Total_Points), ...
        sprintf('实际选用 %d 个点',usage.Used_Points),'Location','southoutside');
end
title(layout,sprintf('%dQAM 在 %d 点 LUT 中的实际选点',c.QAM_Order,usage.Total_Points), ...
    'FontSize',18,'FontWeight','bold');
subtitle(layout,sprintf('红色：%d 个实际选点 | 灰色：全部训练点 | 计数单位：%s，发送 %d 个符号', ...
    usage.Mapped_Points,usage.Count_Unit,usage.Payload_Symbols), ...
    'FontSize',11);
set(findall(f,'-property','FontName'),'FontName','Microsoft YaHei');
if ~isfolder(c.Output_Directory), mkdir(c.Output_Directory); end
prefix=fullfile(c.Output_Directory,[c.Run_Tag '_dpd_lut_selection']);
rfdac_export_figure(f,[prefix '.png']);
save([prefix '_usage.mat'],'usage');
points=table((1:lut.Points)',double(lut.Output_I(:)),double(lut.Output_Q(:)), ...
    real(response),imag(response),usage.Counts,usage.Used,usage.Mapped, ...
    'VariableNames',{'Index','DAC_I_Code','DAC_Q_Code','TX_I_V','TX_Q_V','Use_Count','Used_In_Record','Selected'});
writetable(points,[prefix '_points.csv']);
fprintf('LUT selection: %d / %d training points used over %d DAC samples; %d actual logged words verified.\n', ...
    usage.Used_Points,usage.Total_Points,usage.Total_DAC_Samples,usage.Verified_Logged_Samples);
end
