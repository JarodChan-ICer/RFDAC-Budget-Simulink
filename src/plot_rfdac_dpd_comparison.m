function plot_rfdac_dpd_comparison(report)
c=report.Config; folder=c.Output_Directory;
f=figure('Color','w','Visible','off','Position',[80 60 1350 600]);
names={'Off','IQ only','Nonlinear only','Joint'};
values=[report.Table.EVM_Percent(1:4),report.Table.EVM_Percent(5:8)];
bar(categorical(names,names),values); grid on; ylabel('Full-record RMS EVM (%)');
legend('Jitter off',sprintf('%.0f fs jitter',c.LO_RMS_Jitter*1e15),'Location','best');
title(sprintf('%.1f GHz / %d-QAM / TX %.1f dB / static quadrature error 1 deg', ...
    c.LO_Frequency/1e9,c.QAM_Order,c.TX_Target_EVM_dB));
rfdac_export_figure(f,fullfile(folder,'dpd_evm_comparison.png')); close(f);

f=figure('Color','w','Visible','off','Position',[60 40 1450 850]);
tiledlayout(2,3,'TileSpacing','compact','Padding','compact');
selected=[1 1;1 4;2 4];
titles={'No DPD, jitter off','Joint DPD, jitter off','Joint DPD, jitter on'};
errorLimit=max(.01,1.05*max(abs([report.Error_Vectors{1,1}; ...
    report.Error_Vectors{1,4};report.Error_Vectors{2,4}])));
for j=1:3
    a=selected(j,1); b=selected(j,2); z=report.Received_Symbols{a,b};
    nexttile(j); plot(real(report.Reference_Constellation),imag(report.Reference_Constellation),'k+','MarkerSize',3); hold on;
    plot(real(z),imag(z),'.','MarkerSize',3); axis equal; grid on; xlim([-1.4 1.4]); ylim([-1.4 1.4]);
    xlabel('I'); ylabel('Q'); title(titles{j});
    nexttile(j+3); e=report.Error_Vectors{a,b}.*exp(-1i*angle(report.Reference_Symbols));
    plot(real(e),imag(e),'.','MarkerSize',3); axis equal; grid on;
    xlim([-errorLimit errorLimit]); ylim([-errorLimit errorLimit]);
    xlabel('Radial error'); ylabel('Tangential error');
    title(sprintf('EVM %.4f %%',report.Table.EVM_Percent((a-1)*4+b)));
end
rfdac_export_figure(f,fullfile(folder,'dpd_constellation_comparison.png')); close(f);
end
