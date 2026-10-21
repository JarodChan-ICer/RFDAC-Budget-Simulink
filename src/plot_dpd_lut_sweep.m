function f=plot_dpd_lut_sweep(report,folder)
% Show corrected EVM, small precision penalty and memory on separate scales.
c=report.Config; t=report.Table; rows=3:height(t); points=t.LUT_Points(rows);
f=figure('Color','w','Renderer','painters','Visible',c.Figure_Visible,'Position',[80 60 1050 900]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
nexttile; semilogx(points,t.EVM_Percent(rows),'o-','LineWidth',1.3); hold on;
yline(t.EVM_Percent(2),':','Analytic reference'); grid on;
xlabel('Total complex LUT entries'); ylabel('Final RMS EVM (%)');
title(sprintf('%d-QAM / %s / table %d bits, F=%d / DPD off EVM %.4f%%', ...
    c.QAM_Order,c.DPD_LUT_Interpolation,c.DPD_LUT_Value_Bits,c.DPD_LUT_Fraction_Bits,t.EVM_Percent(1)));
nexttile; semilogx(points,t.EVM_Penalty_vs_Analytic_dB(rows),'o-','LineWidth',1.3); hold on;
yline(0,':','Analytic reference'); yline(c.DPD_LUT_Max_Penalty_dB,'--','Allowed penalty');
grid on; xlabel('Total complex LUT entries'); ylabel('EVM penalty (dB)');
nexttile; semilogx(points,t.Payload_KiB(rows),'o-'); grid on;
xlabel('Total complex LUT entries'); ylabel('Packed payload (KiB)');
if ~isempty(report.Recommended_Points)
    title(sprintf('Minimum tested size meeting criterion: %d entries / %.1f KiB', ...
        report.Recommended_Points,report.Recommended_Payload_KiB));
else
    title('No tested LUT meets the configured precision criterion');
end
rfdac_export_figure(f,fullfile(folder,'lut_precision_sweep.png'));
end
