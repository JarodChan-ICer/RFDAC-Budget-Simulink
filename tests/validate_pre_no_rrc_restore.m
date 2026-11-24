function report=validate_pre_no_rrc_restore()
% Verify the restored pre-no-RRC model against its saved actual SLX record.
root=fileparts(fileparts(mfilename('fullpath')));
folder=fullfile(root,'outputs','validation','rollback_verified');
if ~isfolder(folder), mkdir(folder); end
diary(fullfile(root,'outputs','logs','rollback_pre_no_rrc_validation.log'));
cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
report.All_Passed=false;
try
    setup_rfdac_project();
    saved=load(fullfile(root,'outputs','validation','symbol_mapping','before_no_rrc_results.mat'),'results');
    original=saved.results; clear saved;
    c=init_rfdac_model();
    c.RX_Equalizer_Enable=false; % reproduce the historical pre-equalizer RX
    if bdIsLoaded(c.Model_Name), close_system(c.Model_Name,0); end
    [p,resolved]=rfdac_prepare(c);
    assert(~isfield(c,'RRC_Enable') && ~isfield(p.DPD,'Symbol_LUT_Indices'));
    assert(resolved.LO_Quadrature_Error_Deg==original.cfg.LO_Quadrature_Error_Deg);
    assert(resolved.LPF_Cutoff==original.cfg.LPF_Cutoff && resolved.RX_LPF_Cutoff==original.cfg.RX_LPF_Cutoff);
    assert(isequal(p.RRC,original.filters.RRC));
    assert(isequal(p.TX_FIR,original.filters.TX_FIR) && isequal(p.RX_FIR,original.filters.RX_FIR));
    assert(p.Total_Delay==original.timing.Total_Delay_DAC_Samples);
    report.Calibration_Beta_Difference=abs(p.TX_Beta-original.TX_Beta);
    assert(report.Calibration_Beta_Difference<1e-7);
    meta=rfdac_public_identification_metadata(resolved,p);
    prediction=rfdac_predict_clean_tx(p.TX_Beta,meta);
    report.Clean_Prediction_EVM_dB=prediction.EVM_dB;
    assert(abs(prediction.EVM_dB-c.TX_Target_EVM_dB)<c.TX_EVM_Fit_Tolerance_dB);
    clear prediction meta p;
    results=run_rfdac_simulation(c);
    report.Received_Max_Difference=max(abs(results.Received_Symbols-original.Received_Symbols));
    report.Baseline_Max_Difference=max(abs(results.DPD_Comparison.Before_Received_Symbols- ...
        original.DPD_Comparison.Before_Received_Symbols));
    assert(report.Received_Max_Difference<1e-7 && report.Baseline_Max_Difference<1e-7);
    assert(isequal(results.DPD.LUT.Output_I,original.DPD.LUT.Output_I));
    assert(isequal(results.DPD.LUT.Output_Q,original.DPD.LUT.Output_Q));
    usage=rfdac_lut_usage(results);
    assert(usage.Verified_Logged_Samples>0 && strcmp(usage.Count_Unit,'DAC samples'));
    assert(getSimulinkBlockHandle([c.Model_Name '/QAM Source/TX RRC pulse shaping'])>0);
    assert(getSimulinkBlockHandle([c.Model_Name '/Receiver Downconversion/RRC matched filter'])>0);
    assert(getSimulinkBlockHandle([c.Model_Name '/TX Pulse Shaping'])<0);
    report.Metrics=results.metrics;
    report.Before_Metrics=results.DPD_Comparison.Before_Metrics;
    report.Selected_Training_Points=usage.Used_Points;
    report.Verified_DAC_Samples=usage.Verified_Logged_Samples;
    report.All_Passed=true;
    save(fullfile(folder,'validation.mat'),'report');
    fid=fopen(fullfile(folder,'completed.txt'),'w');
    fprintf(fid,'Pre-no-RRC model, calibration, sampled LUT and full DPD pair reproduced.\n');
    fprintf(fid,'DPD OFF %.9f dB, ON %.9f dB, EVM %.9f%%, SER %.9f.\n', ...
        report.Before_Metrics.Estimated_SNR_dB,report.Metrics.Estimated_SNR_dB, ...
        report.Metrics.EVM_Percent,report.Metrics.Symbol_Error_Rate);
    fprintf(fid,'Max received-symbol differences OFF %.9g, ON %.9g; selected %d training points.\n', ...
        report.Baseline_Max_Difference,report.Received_Max_Difference,report.Selected_Training_Points);
    fclose(fid);
    disp(report); fprintf('PRE-NO-RRC RESTORE CHECKS PASSED.\n');
catch err
    fprintf(2,'%s\n',getReport(err,'extended','hyperlinks','off'));
    save(fullfile(folder,'validation.mat'),'report');
end
end
