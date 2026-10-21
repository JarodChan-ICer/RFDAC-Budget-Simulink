function sweep=sweep_lo_jitter(cfg,jitter_values)
%SWEEP_LO_JITTER Same data and unit-jitter realization at every sweep point.
setup_rfdac_project();
if nargin<1, cfg=init_rfdac_model(); end
if nargin<2, jitter_values=[0 10e-15 30e-15 100e-15 300e-15 1e-12]; end
cfg.Output_Directory=rfdac_output_directory(cfg.Output_Directory);
validateattributes(jitter_values,{'numeric'},{'vector','nonnegative','finite'});
jitter_values=jitter_values(:);
base=cfg; cfg.Make_Plots=false; cfg.Save_Results=false; cfg.LO_Jitter_Enable=true;
n=numel(jitter_values); evm=zeros(n,1); snr=evm; measured=evm;
symbols=cell(n,1); errors=cell(n,1);
for k=1:n
    cfg.LO_RMS_Jitter=jitter_values(k);
    r=run_rfdac_simulation(cfg);
    evm(k)=r.metrics.EVM_Percent; snr(k)=r.metrics.Estimated_SNR_dB;
    measured(k)=r.metrics.Measured_TX_Jitter_fs;
    symbols{k}=r.Received_Symbols; errors{k}=r.Error_Vector;
end
sweep.cfg=base;
sweep.table=table(jitter_values*1e15,measured,evm,snr, ...
    'VariableNames',{'Configured_Jitter_fs','Measured_Jitter_fs','EVM_Percent','Estimated_SNR_dB'});
sweep.Received_Symbols=symbols; sweep.Error_Vectors=errors;
sweep.Reference_Constellation=r.Reference_Constellation;
sweep.Reference_Symbols=r.Reference_Symbols;
if ~isfolder(base.Output_Directory), mkdir(base.Output_Directory); end
save(fullfile(base.Output_Directory,'lo_jitter_sweep.mat'),'sweep');
writetable(sweep.table,fullfile(base.Output_Directory,'lo_jitter_sweep.csv'));
if base.Make_Plots
    fig=figure('Name','LO jitter sweep','Color','w','Position',[80 80 1300 520],'Visible',base.Figure_Visible);
    tiledlayout(1,2);
    nexttile; plot(jitter_values*1e15,evm,'o-','LineWidth',1.5); grid on;
    xlabel('Configured RMS timing jitter (fs)'); ylabel('RMS EVM (%)');
    title(sprintf('%d-QAM, TX %.1f dB, quadrature %.2f deg, RX %s', ...
        base.QAM_Order,base.TX_Target_EVM_dB,base.LO_Quadrature_Error_Deg,base.RX_LO_Mode));
    nexttile; plot(jitter_values*1e15,snr,'o-','LineWidth',1.5); grid on;
    xlabel('Configured RMS timing jitter (fs)'); ylabel('Estimated SNR / SNDR (dB)');
    title('Inverse normalized error power; includes distortion');
    rfdac_export_figure(fig,fullfile(base.Output_Directory,'lo_jitter_sweep.png'));
    [~,i0]=min(abs(jitter_values)); [~,i100]=min(abs(jitter_values-100e-15)); [~,imax]=max(jitter_values);
    chosen=unique([i0 i100 imax],'stable');
    fig=figure('Name','Constellation comparison','Color','w','Position',[80 40 1500 850],'Visible',base.Figure_Visible);
    tiledlayout(2,numel(chosen),'TileSpacing','compact','Padding','compact');
    lim=0;
    for k=chosen(:)'
        e=errors{k}.*exp(-1i*angle(sweep.Reference_Symbols)); lim=max(lim,max(abs([real(e);imag(e)])));
    end
    lim=max(lim*1.05,0.001);
    for j=1:numel(chosen)
        k=chosen(j); z=symbols{k};
        nexttile(j); plot(real(r.Reference_Constellation),imag(r.Reference_Constellation),'k+','MarkerSize',5); hold on;
        plot(real(z),imag(z),'.','Color',[.05 .4 .85],'MarkerSize',5); axis equal; grid on;
        xlabel('I'); ylabel('Q'); title(sprintf('%.0f fs: EVM %.3f %%',jitter_values(k)*1e15,evm(k)));
        e=errors{k}.*exp(-1i*angle(sweep.Reference_Symbols));
        nexttile(j+numel(chosen)); plot(real(e),imag(e),'.','Color',[.8 .2 .15]); axis equal; grid on;
        xlim([-lim lim]); ylim([-lim lim]); xlabel('Radial error'); ylabel('Tangential error');
        title('Same error-axis scale');
    end
    rfdac_export_figure(fig,fullfile(base.Output_Directory,'lo_jitter_constellation_comparison.png'));
end
disp(sweep.table);
assignin('base','sweep',sweep);
end
