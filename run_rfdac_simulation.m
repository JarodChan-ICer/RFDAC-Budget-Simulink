function results = run_rfdac_simulation(cfg)
%RUN_RFDAC_SIMULATION Simulate the actual SLX, measure, plot and save results.
% cfg=init_rfdac_model(); cfg.QAM_Order=1024; results=run_rfdac_simulation(cfg);
paths=setup_rfdac_project();
if nargin<1
    if evalin('base','exist(''cfg'',''var'')'), cfg=evalin('base','cfg');
    else, cfg=init_rfdac_model(); end
end
folder=paths.Root;
if ~isfile(fullfile(folder,[cfg.Model_Name '.slx'])), build_rfdac_model(cfg); end
[prepared,setupCfg]=rfdac_prepare(cfg);
setupCfg.Output_Directory=rfdac_output_directory(setupCfg.Output_Directory);
cfg.Output_Directory=setupCfg.Output_Directory;
comparison=[];
if setupCfg.Make_Plots && setupCfg.Plot_Constellation && setupCfg.Plot_DPD_Comparison && setupCfg.DPD_Enable
    off=setupCfg; off.DPD_Enable=false; off.Make_Plots=false; off.Save_Results=false;
    off.TX_Nonlinearity_Beta=prepared.TX_Beta; % freeze the same physical TX
    baseline=run_rfdac_simulation(off);
    comparison=struct('Before_Received_Symbols',baseline.Received_Symbols, ...
        'Before_Error_Vector',baseline.Error_Vector,'Before_Metrics',baseline.metrics, ...
        'Before_TX_Beta',baseline.TX_Beta,'Random_Seed',off.Random_Seed, ...
        'Before_TX_Jitter',baseline.TX_Jitter);
    clear baseline;
end
assignin('base','cfg',setupCfg); assignin('base','p',prepared);
load_system(fullfile(folder,[cfg.Model_Name '.slx']));
txblock=[cfg.Model_Name '/TX EVM Nonlinearity'];
if getSimulinkBlockHandle(txblock)<0 || ~strcmp(get_param(txblock,'Tag'),'rfdac_evm_v2')
    update_rfdac_evm_model(cfg.Model_Name);
end
dpdblock=[cfg.Model_Name '/Digital Predistortion'];
if getSimulinkBlockHandle(dpdblock)<0 || ~strcmp(get_param(dpdblock,'Tag'),'rfdac_dpd_v3')
    update_rfdac_dpd_model(cfg.Model_Name);
end
assignin('base','cfg',cfg);
tic; simout=sim(cfg.Model_Name); elapsed=toc;
p=evalin('base','p'); cfg=evalin('base','cfg');
results=rfdac_measure(simout,cfg,p);
if ~isempty(comparison)
    assert(abs(results.TX_Beta-comparison.Before_TX_Beta)<1e-12,'Comparison changed the analog TX.');
    assert(isequal(results.TX_Jitter,comparison.Before_TX_Jitter),'Comparison changed the jitter realization.');
    comparison=rmfield(comparison,'Before_TX_Jitter');
    results.DPD_Comparison=comparison;
end
clear simout;
results.Simulation_Seconds=elapsed;
if cfg.Save_Results
    if ~isfolder(cfg.Output_Directory), mkdir(cfg.Output_Directory); end
    save(fullfile(cfg.Output_Directory,[cfg.Run_Tag '_results.mat']),'results','-v7.3');
    writetable(struct2table(results.metrics),fullfile(cfg.Output_Directory,[cfg.Run_Tag '_metrics.csv']));
end
if cfg.Make_Plots, plot_rfdac_results(results); end
assignin('base','results',results);
fprintf('%4d-QAM | TX target %.2f dB | jitter %.1f fs | quadrature %.3f deg | EVM %.5f %% (%+.3f dB) | SNDR %.3f dB | SER %.5g | %.2f s\n', ...
    cfg.QAM_Order,cfg.TX_Target_EVM_dB,1e15*cfg.LO_RMS_Jitter*cfg.LO_Jitter_Enable, ...
    cfg.LO_Quadrature_Error_Deg*cfg.LO_Quadrature_Error_Enable, ...
    results.metrics.EVM_Percent,results.metrics.EVM_dB,results.metrics.Estimated_SNR_dB, ...
    results.metrics.Symbol_Error_Rate,elapsed);
fprintf('DPD %d (IQ %d, nonlinear %d): drive expansion %.3f dB, limited %d, full DAC clip I/Q %d/%d\n', ...
    p.DPD.Enabled,p.DPD.IQ_Enable,p.DPD.Nonlinearity_Enable,results.metrics.DPD_Drive_Power_Expansion_dB, ...
    results.metrics.DPD_Limited_Samples,results.metrics.DPD_DAC_I_Clipped_Full,results.metrics.DPD_DAC_Q_Clipped_Full);
if strcmp(p.DPD.Algorithm,'lut')
    l=p.DPD.LUT;
    fprintf('DPD LUT: %dx%d = %d entries, %s, %d bits/component (%d fractional), payload %.1f KiB, table-clipped nodes %d\n', ...
        l.Size,l.Points,l.Interpolation,l.Value_Bits,l.Fraction_Bits,l.Packed_Payload_Bytes/1024,l.Value_Clipped_Nodes);
end
end
