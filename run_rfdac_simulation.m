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
if strcmp(prepared.DPD.Algorithm,'lut') && strcmp(setupCfg.DPD_LUT_Training_Mode,'link') && ...
        prepared.DPD.Enabled && (prepared.DPD.IQ_Enable || prepared.DPD.Nonlinearity_Enable)
    meta=setupCfg.DPD_LUT_Training_Metadata;
    if isfield(meta,'Key') && ~isequal(meta.Key,rfdac_lut_training_key(setupCfg,prepared))
        setupCfg.DPD_LUT_Training_Observed=[]; setupCfg.DPD_LUT_Training_Metadata=struct();
        [prepared,setupCfg]=rfdac_prepare(setupCfg);
    end
    if isempty(setupCfg.DPD_LUT_Training_Observed)
        [setupCfg.DPD_LUT_Training_Observed,setupCfg.DPD_LUT_Training_Metadata]= ...
            rfdac_train_link_lut(setupCfg,prepared);
        [prepared,setupCfg]=rfdac_prepare(setupCfg);
    end
end
setupCfg.Output_Directory=rfdac_output_directory(setupCfg.Output_Directory);
cfg=setupCfg;
comparison=[];
if setupCfg.Make_Plots && setupCfg.Plot_Constellation && setupCfg.Plot_DPD_Comparison && setupCfg.DPD_Enable
    off=setupCfg; off.DPD_Enable=false; off.Make_Plots=false; off.Save_Results=false;
    off.TX_Nonlinearity_Beta=prepared.TX_Beta; % freeze the same physical TX
    baseline=run_rfdac_simulation(off);
    comparison=struct('Before_Received_Symbols',baseline.Received_Symbols, ...
        'Before_Error_Vector',baseline.Error_Vector,'Before_Metrics',baseline.metrics, ...
        'Before_Fitted_Complex_Gain',baseline.Fitted_Complex_Gain, ...
        'Before_TX_Beta',baseline.TX_Beta,'Random_Seed',off.Random_Seed, ...
        'Before_TX_Jitter',baseline.TX_Jitter);
    clear baseline;
end
assignin('base','cfg',setupCfg); assignin('base','p',prepared);
load_system(fullfile(folder,[cfg.Model_Name '.slx']));
update_rfdac_rx_equalizer_model(cfg.Model_Name);
txblock=[cfg.Model_Name '/TX EVM Nonlinearity'];
if getSimulinkBlockHandle(txblock)<0 || ~strcmp(get_param(txblock,'Tag'),'rfdac_evm_v2')
    update_rfdac_evm_model(cfg.Model_Name);
end
update_rfdac_lo_amplitude_model(cfg.Model_Name);
dpdblock=[cfg.Model_Name '/Digital Predistortion'];
if getSimulinkBlockHandle(dpdblock)<0 || ~strcmp(get_param(dpdblock,'Tag'),'rfdac_dpd_v7')
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
if p.Raw_Training_Enable
    fprintf('Raw snake RF capture | %d training points | IQ %.3f deg | jitter %.1f fs | %.2f s\n', ...
        cfg.QAM_Order,cfg.LO_Quadrature_Error_Deg*cfg.LO_Quadrature_Error_Enable, ...
        1e15*cfg.LO_RMS_Jitter*cfg.LO_Jitter_Enable,elapsed);
else
fprintf('%4d-QAM | TX target %.2f dB | jitter %.1f fs | quadrature %.3f deg | EVM %.5f %% (%+.3f dB) | SNDR %.3f dB | SER %.5g | %.2f s\n', ...
    cfg.QAM_Order,cfg.TX_Target_EVM_dB,1e15*cfg.LO_RMS_Jitter*cfg.LO_Jitter_Enable, ...
    cfg.LO_Quadrature_Error_Deg*cfg.LO_Quadrature_Error_Enable, ...
    results.metrics.EVM_Percent,results.metrics.EVM_dB,results.metrics.Estimated_SNR_dB, ...
    results.metrics.Symbol_Error_Rate,elapsed);
end
fprintf('DPD %d (IQ %d, nonlinear %d): drive expansion %.3f dB, limited %d, full DAC clip I/Q %d/%d\n', ...
    p.DPD.Enabled,p.DPD.IQ_Enable,p.DPD.Nonlinearity_Enable,results.metrics.DPD_Drive_Power_Expansion_dB, ...
    results.metrics.DPD_Limited_Samples,results.metrics.DPD_DAC_I_Clipped_Full,results.metrics.DPD_DAC_Q_Clipped_Full);
fprintf('RX EQ %d: nominal in-band ripple %.4f -> %.4f dB, peak gain %.3f dB (ceiling %.1f dB, limited %d)\n', ...
    p.RX_Equalizer.Enabled,p.RX_Equalizer.Ripple_Before_dB,p.RX_Equalizer.Ripple_After_dB, ...
    p.RX_Equalizer.Peak_Gain_dB,p.RX_Equalizer.Max_Boost_dB,p.RX_Equalizer.Boost_Limited);
if strcmp(p.DPD.Algorithm,'lut')
    l=p.DPD.LUT;
    fprintf('DPD candidate grid: %dx%d = %d legal inputs, %s, %d bits/component (%d fractional), word payload %.1f KiB, table-clipped nodes %d\n', ...
        l.Size,l.Points,l.Interpolation,l.Value_Bits,l.Fraction_Bits,l.Packed_Payload_Bytes/1024,l.Value_Clipped_Nodes);
    if strcmp(l.Format,'ppt_measured_2d_lut_v1') && isfield(l,'Inverse_Index')
        fprintf('Measured snake: %d points; dense responses are interpolated from this actual capture.\n',l.Training_Order);
    end
    if cfg.Save_Results && isfield(l,'Training_Metadata')
        meta=l.Training_Metadata;
        save(fullfile(cfg.Output_Directory,[cfg.Run_Tag '_dpd_link_training.mat']),'l','meta','-v7.3');
    end
end
end
