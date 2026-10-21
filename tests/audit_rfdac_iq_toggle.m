function report=audit_rfdac_iq_toggle()
% Separate automatic re-calibration from a fixed correction and stale cfg.
paths=setup_rfdac_project();
data=load(rfdac_find_result(fullfile('dpd_codewords','jitter_1_results.mat')),'results');
r=data.results; c=r.cfg; c.Make_Plots=false; c.Save_Results=false;
c.TX_Nonlinearity_Beta=r.TX_Beta;
c.LO_Quadrature_Error_Enable=false; c.DPD_Quadrature_Estimate_Deg=[];
off=run_rfdac_simulation(c);
c.DPD_Quadrature_Estimate_Deg=1;
fixed=run_rfdac_simulation(c);
labels=["IQ on, automatic exact compensation";"IQ off, automatic zero compensation"; ...
    "IQ off, frozen 1-degree compensation";"IQ on, no compensation"];
evm=[r.metrics.EVM_Percent;off.metrics.EVM_Percent;fixed.metrics.EVM_Percent;r.DPD_Comparison.Before_Metrics.EVM_Percent];
report.Table=table(labels,evm,-20*log10(evm/100),'VariableNames',{'Case','EVM_Percent','EVM_Equivalent_SNDR_dB'});
report.On_Config=r.cfg; report.Off_Config=off.cfg;
report.On_Estimated_Phases=r.DPD.Estimated_Phases_Deg;
report.Off_Estimated_Phases=off.DPD.Estimated_Phases_Deg;
report.Frozen_Estimated_Phases=fixed.DPD.Estimated_Phases_Deg;
report.Same_Jitter=isequal(r.TX_Jitter,off.TX_Jitter) && isequal(off.TX_Jitter,fixed.TX_Jitter);
assert(report.Same_Jitter);
folder=fullfile(paths.Validation,'iq_toggle_audit'); if ~isfolder(folder), mkdir(folder); end
writetable(report.Table,fullfile(folder,'iq_toggle.csv')); save(fullfile(folder,'iq_toggle.mat'),'report');
disp(report.Table); disp(report);
latest=fullfile(paths.Results,'single_results.mat');
if isfile(latest)
    data=load(latest,'results'); last=data.results;
    fprintf('Latest saved single run: IQ enabled %d; configured degree %.6f; DPD estimate %s; EVM %.9f%%; equivalent SNDR %.9f dB\n', ...
        last.cfg.LO_Quadrature_Error_Enable,last.cfg.LO_Quadrature_Error_Deg, ...
        mat2str(last.cfg.DPD_Quadrature_Estimate_Deg),last.metrics.EVM_Percent,last.metrics.Estimated_SNR_dB);
end
bdclose('all');
end
