function report=evaluate_24g_tx_budget()
% Full-record calibration and impairment ablations for the user's 24 GHz TX.
c=init_rfdac_model(); c.LO_Frequency=24e9; c.RX_LO_Frequency=[];
c.DPD_Enable=false; % original impairment budget is intentionally uncorrected
c.TX_Target_EVM_dB=-43; c.LO_Quadrature_Error_Deg=1;
c.LO_Differential_Phase_Error_Deg=0; c.LO_Quadrature_Amplitude_Mismatch=0;
paths=setup_rfdac_project(); c.Output_Directory=fullfile(paths.Validation,'tx_evm_24g');
c.Figure_Visible='off'; c.Make_Plots=false; c.Save_Results=false;
if ~isfolder(c.Output_Directory), mkdir(c.Output_Directory); end
% [TX nonlinear model, quadrature error, timing jitter]
flags=[0 0 0;1 0 0;0 1 0;0 0 1;1 1 0;1 0 1;1 1 1];
names={'Linear floor','TX calibrated','Quadrature only + floor','Jitter only + floor', ...
    'TX + quadrature','TX + jitter','All impairments'};
rows=cell(size(flags,1),1); symbols=cell(size(flags,1),1); errors=symbols;
for k=1:size(flags,1)
    cfg=c; cfg.TX_Nonlinearity_Enable=logical(flags(k,1));
    cfg.LO_Quadrature_Error_Enable=logical(flags(k,2));
    cfg.LO_Jitter_Enable=logical(flags(k,3));
    cfg.Run_Tag=sprintf('case_%d',k);
    cfg.Make_Plots=ismember(k,[2 7]); cfg.Save_Results=cfg.Make_Plots;
    r=run_rfdac_simulation(cfg);
    rows{k}=table(string(names{k}),r.metrics.EVM_Percent,r.metrics.EVM_dB, ...
        r.metrics.Estimated_SNR_dB,r.metrics.Symbol_Error_Rate,r.metrics.Measured_TX_Jitter_fs, ...
        'VariableNames',{'Case','EVM_Percent','EVM_dB','SNDR_dB','SER','Measured_Jitter_fs'});
    symbols{k}=r.Received_Symbols; errors{k}=r.Error_Vector;
    if k==2
        assert(abs(r.metrics.EVM_dB-c.TX_Target_EVM_dB)<0.02,'SLX clean-TX EVM does not match target.');
        calibration=r.TX_Calibration; beta=r.TX_Beta;
    end
    if k==3
        assert(abs(r.metrics.LO_Quadrature_Only_Theoretical_EVM_Percent-100*tand(.5))<1e-9);
    end
    if k==7, final=r; end
end
report.Table=vertcat(rows{:}); report.Calibration=calibration;
report.Config=final.cfg;
assert(report.Table.EVM_Percent(7)>report.Table.EVM_Percent(2));
assert(report.Table.EVM_Percent(5)>report.Table.EVM_Percent(2));
assert(report.Table.EVM_Percent(6)>report.Table.EVM_Percent(2));
writetable(report.Table,fullfile(c.Output_Directory,'impairment_budget.csv'));
report.Quadrature_Theory_EVM_Percent=100*tand(.5);
report.Jitter_Small_Phase_EVM_Percent=100*2*pi*c.LO_Frequency*c.LO_RMS_Jitter;
report.RSS_Approximation_EVM_Percent=sqrt((100*10^(-43/20))^2+ ...
    report.Quadrature_Theory_EVM_Percent^2+report.Jitter_Small_Phase_EVM_Percent^2);
report.Received_Symbols=symbols; report.Error_Vectors=errors;
report.Reference_Symbols=final.Reference_Symbols;
report.Reference_Constellation=final.Reference_Constellation;

fig=figure('Color','w','Visible','off','Position',[70 60 1500 850]);
tiledlayout(2,3,'TileSpacing','compact','Padding','compact');
chosen=[2 5 7];
for j=1:3
    k=chosen(j); nexttile(j);
    plot(real(report.Reference_Constellation),imag(report.Reference_Constellation),'k+','MarkerSize',3); hold on;
    plot(real(symbols{k}),imag(symbols{k}),'.','MarkerSize',3); grid on; axis equal;
    xlim([-1.4 1.4]); ylim([-1.4 1.4]); xlabel('I'); ylabel('Q');
    title(sprintf('%s: EVM %.3f%% (%.2f dB)',names{k},report.Table.EVM_Percent(k),report.Table.EVM_dB(k)));
    nexttile(j+3); e=errors{k}.*exp(-1i*angle(report.Reference_Symbols));
    plot(real(e),imag(e),'.','MarkerSize',3); grid on; axis equal;
    xlim([-.10 .10]); ylim([-.10 .10]); xlabel('Radial error'); ylabel('Tangential error');
    title('One fixed gain/phase correction; same error axes');
end
rfdac_export_figure(fig,fullfile(c.Output_Directory,'impairment_constellation_comparison.png')); close(fig);
fig=figure('Color','w','Visible','off','Position',[80 70 1300 600]);
bar(categorical(names,names),report.Table.EVM_Percent); grid on; ylabel('RMS EVM (%)'); xtickangle(20);
title(sprintf('24 GHz / %d-QAM / %d symbols: TX -43 dB, quadrature 1 deg, jitter %.0f fs',c.QAM_Order,c.Num_Symbols,c.LO_RMS_Jitter*1e15));
rfdac_export_figure(fig,fullfile(c.Output_Directory,'impairment_budget.png')); close(fig);

% Fixed-beta numerical convergence; do not refit and hide sampling changes.
cfg=c; cfg.Num_Symbols=512; cfg.Make_Plots=false; cfg.Save_Results=false;
cfg.LO_Jitter_Enable=false; cfg.LO_Quadrature_Error_Enable=false;
cfg.TX_Nonlinearity_Beta=beta;
low=run_rfdac_simulation(cfg);
cfg.Sample_Rate=2*low.cfg.Sample_Rate;
cfg.LPF_Order=2*low.cfg.LPF_Order; cfg.RX_LPF_Order=2*low.cfg.RX_LPF_Order;
cfg.Oversampling_Ratio=[];
high=run_rfdac_simulation(cfg);
report.Sampling_Convergence_Delta_dB=abs(low.metrics.EVM_dB-high.metrics.EVM_dB);
assert(report.Sampling_Convergence_Delta_dB<0.05,'RF sampling convergence failed.');

% Demonstrate changing target and all supported QAM mappings remain runnable.
cfg=c; cfg.Num_Symbols=256; cfg.Make_Plots=false; cfg.Save_Results=false;
cfg.LO_Jitter_Enable=false; cfg.LO_Quadrature_Error_Enable=false;
for M=[16 64 256 1024 4096]
    cfg.QAM_Order=M; q=run_rfdac_simulation(cfg);
    assert(abs(q.metrics.EVM_dB+43)<0.02,'%d-QAM TX fit failed.',M);
end
cfg.QAM_Order=c.QAM_Order; cfg.TX_Target_EVM_dB=-38;
q=run_rfdac_simulation(cfg); assert(abs(q.metrics.EVM_dB+38)<0.02);
report.Target_Change_Passed=true; report.All_QAM_Modes_Passed=true;
cfg.TX_Target_EVM_dB=-80;
try
    rfdac_prepare(cfg); error('rfdac:MissingFloorGuard','Impossible EVM target was accepted.');
catch err
    assert(strcmp(err.identifier,'rfdac:TargetBelowFloor'),'%s',err.message);
end
report.Below_Floor_Guard_Passed=true;
report.All_Passed=true;
save(fullfile(c.Output_Directory,'evaluation_report.mat'),'report');
fid=fopen(fullfile(c.Output_Directory,'evaluation_report.txt'),'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'24 GHz TX target-EVM + four-phase LO evaluation: ALL CHECKS PASSED\n');
fprintf(fid,'%d-QAM; %d symbols; calibrated beta %.10g V^-2\n',c.QAM_Order,c.Num_Symbols,beta);
fprintf(fid,'Clean target %.6f dB; achieved %.6f dB; linear floor %.6f dB\n', ...
    calibration.Target_EVM_dB,calibration.Achieved_EVM_dB,calibration.Linear_Floor_EVM_dB);
fprintf(fid,'All impairments: %.6f %% EVM, %.6f dB EVM, %.6f dB SNDR, SER %.8g\n', ...
    report.Table.EVM_Percent(7),report.Table.EVM_dB(7),report.Table.SNDR_dB(7),report.Table.SER(7));
fprintf(fid,'Ideal small-error RSS estimate: %.6f %% EVM (not exact simulation)\n',report.RSS_Approximation_EVM_Percent);
fprintf(fid,'Fixed-beta RF sampling convergence: %.8f dB EVM difference\n',report.Sampling_Convergence_Delta_dB);
disp(report.Table); disp('ALL 24 GHz TX EVM / FOUR-PHASE LO CHECKS PASSED.');
assignin('base','cfg',c); assignin('base','results',final); close all;
end
