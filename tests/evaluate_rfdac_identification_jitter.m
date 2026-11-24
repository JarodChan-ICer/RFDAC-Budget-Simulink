function extra=evaluate_rfdac_identification_jitter(report)
% One alternate jitter PSD, not a rerun of the complete identification study.
% Equal timing RMS alone does not determine post-filter symbol EVM.
paths=setup_rfdac_project();
if nargin<1
    saved=load(fullfile(paths.Validation,'rx_identification','identification_report.mat'),'report');
    report=saved.report;
end
assert(report.Completed,'Primary identification report is incomplete.');
c=report.Config; opt=report.Options;
c.TX_Nonlinearity_Beta=report.Truth.Beta; % simulator state only, hidden from estimator
c.TX_Nonlinearity_Enable=true; c.LO_Quadrature_Error_Enable=true; c.LO_Jitter_Enable=true;
c.Make_Plots=false; c.Save_Results=false; c.Plot_DPD_Comparison=false;
c.DPD_Enable=false; c.RX_LO_Mode='ideal'; c.Oversampling_Ratio=[];
if strcmp(c.Jitter_Mode,'white'), c.Jitter_Mode='bandlimited'; c.Jitter_Bandwidth=5e6;
else, c.Jitter_Mode='white'; end
c.Num_Symbols=opt.Validation_Symbols;
[p,c]=rfdac_prepare(c);
meta=rfdac_public_identification_metadata(c,p); clear p;

captureOptions=opt; captureOptions.Capture_Frames=2048;
amplitudes=[opt.Training_Amplitudes c.Input_Amplitude];
captures=cell(numel(amplitudes),1); trainingSeeds=zeros(numel(amplitudes),1);
for k=1:numel(amplitudes)
    training=c; training.Num_Symbols=2048; training.Input_Amplitude=amplitudes(k);
    training.Random_Seed=opt.Training_Seed+10000+k*31;
    trainingSeeds(k)=training.Random_Seed;
    captures{k}=rfdac_capture_tx_observation(training,captureOptions);
end
assert(all(trainingSeeds~=opt.Validation_Seed));
fitOptions=struct('Cluster_Symbols',opt.Cluster_Symbols);
est=rfdac_identify_tx(captures,meta,fitOptions); clear captures;
prediction=rfdac_predict_clean_tx(est.Beta,meta);
est.TX_SNR_dB=prediction.TX_SNR_dB; est.TX_EVM_Percent=prediction.EVM_Percent;
low=rfdac_predict_clean_tx(est.Beta_CI95(1),meta);
high=rfdac_predict_clean_tx(est.Beta_CI95(2),meta);
est.TX_SNR_CI95_dB=sort([low.TX_SNR_dB high.TX_SNR_dB]);
clear prediction low high;

evm=zeros(2,1);
for k=1:2
    validation=c; validation.Num_Symbols=4096; validation.Random_Seed=opt.Validation_Seed;
    validation.DPD_Enable=k==2;
    validation.DPD_Nonlinearity_Enable=k==2; validation.DPD_IQ_Enable=k==2;
    validation.DPD_TX_Beta_Estimate=est.Beta;
    validation.DPD_Quadrature_Estimate_Deg=est.IQ_Error_Deg;
    validation.DPD_Phase_Errors_Estimate_Deg=zeros(1,4);
    r=run_rfdac_simulation(validation);
    assert(abs(r.TX_Beta-report.Truth.Beta)<1e-12,'Alternate-PSD test changed physical TX.');
    assert(r.cfg.LO_Quadrature_Error_Deg==report.Truth.IQ_Error_Deg);
    assert(r.cfg.LO_RMS_Jitter==report.Truth.Jitter_RMS_s);
    assert(r.metrics.Invalid_Output_Codeword_Pairs==0);
    assert(r.metrics.DPD_DAC_I_Clipped_Full+r.metrics.DPD_DAC_Q_Clipped_Full==0);
    if k==1, reference=r.Reference_Symbols; jitter=r.TX_Jitter;
    else
        assert(isequal(r.Reference_Symbols,reference) && isequal(r.TX_Jitter,jitter), ...
            'Alternate-PSD before/after comparison changed pilots or jitter realization.');
    end
    evm(k)=r.metrics.EVM_Percent;
end
assert(evm(2)<evm(1),'Frozen estimated calibration did not improve alternate-PSD EVM.');
primary=row(report.Config,report.Estimate,report.Case_Table.EVM_Percent(4), ...
    report.Case_Table.EVM_Percent(3),opt.Validation_Symbols,opt.Training_Symbols);
alternate=row(c,est,evm(1),evm(2),4096,2048);
extra.Table=[primary;alternate];
extra.Alternate_Estimate=est;
extra.Estimator_Options=fitOptions;
extra.Alternate_Training_Seeds=trainingSeeds;
extra.Alternate_Validation_Seed=opt.Validation_Seed;
extra.Same_Physical_TX_Beta=report.Truth.Beta;
extra.Capture_Fields={'Codes','RF','Start_Time','Amplitude'};
extra.Public_Metadata_Fields=fieldnames(meta);
extra.Note=['Same configured timing-jitter RMS, different PSD/correlation and therefore different in-band residual EVM. ' ...
    'White mode is independent at RF sample rate; its correlation bandwidth is reported as NaN. ' ...
    'Primary and alternate records contain different symbol counts shown in the table; each before/after pair uses identical pilots/jitter. ' ...
    'Intervals are conditional on the same known static model/nominal linear-path assumptions, not a universal hardware guarantee.'];
extra.Completed=true;
writetable(extra.Table,fullfile(report.Output_Directory,'jitter_sensitivity.csv'));
save(fullfile(report.Output_Directory,'jitter_sensitivity.mat'),'extra');
disp(extra.Table); disp('SAME-RMS / DIFFERENT-PSD IDENTIFICATION CHECK COMPLETE.');
if bdIsLoaded(c.Model_Name), close_system(c.Model_Name,0); end
end
function t=row(c,est,none,both,validationSymbols,trainingSymbols)
bandwidth=NaN;
if strcmp(c.Jitter_Mode,'bandlimited'), bandwidth=c.Jitter_Bandwidth/1e6; end
t=table(string(c.Jitter_Mode),c.LO_RMS_Jitter*1e15,bandwidth,c.Sample_Rate/1e9, ...
    trainingSymbols,validationSymbols,est.TX_SNR_dB,est.TX_SNR_CI95_dB(1),est.TX_SNR_CI95_dB(2), ...
    est.IQ_Error_Deg,est.IQ_CI95_Deg(1),est.IQ_CI95_Deg(2),none,both, ...
    'VariableNames',{'Jitter_Mode','Known_Jitter_RMS_fs','Correlation_Bandwidth_MHz','RF_Sample_Rate_GHz', ...
    'Training_Symbols_Per_Capture','Validation_Symbols','Estimated_TX_SNR_dB','SNR_CI_Low_dB','SNR_CI_High_dB', ...
    'Estimated_IQ_Deg','IQ_CI_Low_Deg','IQ_CI_High_Deg','No_Calibration_EVM_Percent','Joint_Calibration_EVM_Percent'});
end
