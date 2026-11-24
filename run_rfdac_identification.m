function report=run_rfdac_identification(cfg,opt)
% RX-side unknown-parameter identification, followed by frozen four-way DPD.
% Truth belongs to simulator/grader only. Estimator receives a whitelist packet.
% No arguments: use init_rfdac_identification, ignoring any workspace cfg/opt.
% Explicit cfg/opt: use those values. opt.Figure_Visible controls these plots.
setup_rfdac_project();
if nargin<1 || isempty(cfg)
    [cfg,defaultOpt]=init_rfdac_identification();
    configurationSource='init_rfdac_identification';
else
    configurationSource='explicit cfg argument';
end
if nargin<2 || isempty(opt)
    if ~exist('defaultOpt','var'), [~,defaultOpt]=init_rfdac_identification(); end
    opt=defaultOpt;
end
validateattributes(opt.Monte_Carlo_Repeats,{'numeric'},{'scalar','integer','nonnegative','finite'});
opt.Figure_Visible=validatestring(opt.Figure_Visible,{'on','off'});
if ~isfolder(opt.Output_Directory), mkdir(opt.Output_Directory); end
userCfg=cfg;
cfg.Make_Plots=false; cfg.Save_Results=false; cfg.Plot_DPD_Comparison=false;
cfg.RX_LO_Mode='ideal'; cfg.DPD_Enable=false;
cfg.Num_Symbols=opt.Validation_Symbols; cfg.Oversampling_Ratio=[];
[p,cfg]=rfdac_prepare(cfg);
truthBeta=p.TX_Beta; cfg.TX_Nonlinearity_Beta=truthBeta;
meta=rfdac_public_identification_metadata(cfg,p); clear p;
report.Truth=struct('TX_SNR_dB',-cfg.TX_Target_EVM_dB, ...
    'IQ_Error_Deg',cfg.LO_Quadrature_Error_Deg,'LO_Frequency',cfg.LO_Frequency, ...
    'Jitter_RMS_s',cfg.LO_RMS_Jitter,'Beta',truthBeta);
report.Output_Directory=opt.Output_Directory;
report.Figure_Visible=opt.Figure_Visible;
report.Config=userCfg; report.Options=opt;
report.Configuration_Source=configurationSource;
report.Figure_Files=struct( ...
    'Four_Cases',fullfile(opt.Output_Directory,'identification_four_cases.png'), ...
    'Estimates',fullfile(opt.Output_Directory,'identification_estimates.png'), ...
    'Reliability',fullfile(opt.Output_Directory,'identification_reliability.png'));
report.Assumptions={ ...
    'Positive TX SNR means whole clean-TX MER with RRC/DAC/LPFs and ideal IQ/jitter; no AWGN is added.', ...
    'RX observation path is linear/coherent and calibrated; its gain/DC are unknown nuisances.', ...
    'Known model family: static IQ plus monotonic RF atan compression; numeric parameters unknown.', ...
    'Nominal linear TX/RX filters, timing, known pilots, DAC resolution and scaling are public.', ...
    'Known Gaussian jitter RMS; no estimator access to actual phase-error sequence.', ...
    'Confidence intervals are conditional on this model/linear-path assumption, not arbitrary-hardware guarantees.'};

fprintf('\nRX identification configuration: %s\n',configurationSource);
fprintf('Clean TX %.2f dB equivalent SNR | LO %.3f GHz | jitter %.1f fs (%s) | IQ %.3f deg | %d-QAM\n', ...
    -cfg.TX_Target_EVM_dB,cfg.LO_Frequency/1e9,cfg.LO_RMS_Jitter*1e15, ...
    cfg.Jitter_Mode,cfg.LO_Quadrature_Error_Deg,cfg.QAM_Order);
fprintf('Training: %d small amplitudes + working amplitude. Primary fit + %d optional independent repeats.\n', ...
    numel(opt.Training_Amplitudes),opt.Monte_Carlo_Repeats);
fprintf('Plots: %s | Output: %s\n',opt.Figure_Visible,opt.Output_Directory);
captures=collect(cfg,opt,0);
save(fullfile(opt.Output_Directory,'training_observations.mat'),'captures','meta','-v7.3');
fitOptions=struct('Cluster_Symbols',opt.Cluster_Symbols);
if isfield(opt,'Max_Fit_Samples'), fitOptions.Max_Fit_Samples=opt.Max_Fit_Samples; end
est=rfdac_identify_tx(captures,meta,fitOptions); clear captures;
est=performance(est,meta);
report.Estimate=est;
fprintf('RX estimated IQ %.6f deg; clean TX equivalent SNR %.6f dB.\n',est.IQ_Error_Deg,est.TX_SNR_dB);

% Repeat complete training, not just noisy evaluations of the same fitted model.
rows=cell(opt.Monte_Carlo_Repeats+1,1);
rows{1}=estimate_row(0,est,report.Truth);
for trial=1:opt.Monte_Carlo_Repeats
    fprintf('\nIndependent identification trial %d / %d\n',trial,opt.Monte_Carlo_Repeats);
    captures=collect(cfg,opt,trial);
    sample=rfdac_identify_tx(captures,meta,fitOptions); clear captures;
    sample=performance(sample,meta);
    rows{trial+1}=estimate_row(trial,sample,report.Truth);
end
report.Identification_Trials=vertcat(rows{:});
trials=report.Identification_Trials;
report.Reliability=struct('Trials',height(trials), ...
    'IQ_Bias_Deg',mean(trials.IQ_Error_Deg-report.Truth.IQ_Error_Deg), ...
    'IQ_RMSE_Deg',sqrt(mean((trials.IQ_Error_Deg-report.Truth.IQ_Error_Deg).^2)), ...
    'TX_SNR_Bias_dB',mean(trials.TX_SNR_dB-report.Truth.TX_SNR_dB), ...
    'TX_SNR_RMSE_dB',sqrt(mean((trials.TX_SNR_dB-report.Truth.TX_SNR_dB).^2)), ...
    'IQ_CI_Coverage',mean(trials.IQ_CI_Low<=report.Truth.IQ_Error_Deg & trials.IQ_CI_High>=report.Truth.IQ_Error_Deg), ...
    'TX_SNR_CI_Coverage',mean(trials.SNR_CI_Low<=report.Truth.TX_SNR_dB & trials.SNR_CI_High>=report.Truth.TX_SNR_dB));
report.Reliability.Repeatability_Evaluated=height(trials)>1;
if ~report.Reliability.Repeatability_Evaluated
    % A single fit cannot establish repeatability or empirical CI coverage.
    scores={'IQ_Bias_Deg','IQ_RMSE_Deg','TX_SNR_Bias_dB','TX_SNR_RMSE_dB', ...
        'IQ_CI_Coverage','TX_SNR_CI_Coverage'};
    for k=1:numel(scores), report.Reliability.(scores{k})=NaN; end
end

% Same impaired physical TX, same held-out pilots and same jitter in all cases.
flags=[1 0;0 1;1 1;0 0];
labels={'TX nonlinearity only','Static IQ only','TX + static IQ','No calibration'};
caseRows=cell(4,1); cases=cell(4,1);
for k=1:4
    c=cfg; c.Num_Symbols=opt.Validation_Symbols; c.Random_Seed=opt.Validation_Seed;
    c.DPD_Enable=any(flags(k,:)); c.DPD_Nonlinearity_Enable=logical(flags(k,1));
    c.DPD_IQ_Enable=logical(flags(k,2));
    c.DPD_TX_Beta_Estimate=est.Beta;
    c.DPD_Quadrature_Estimate_Deg=est.IQ_Error_Deg;
    c.DPD_Phase_Errors_Estimate_Deg=zeros(1,4);
    c.Run_Tag=sprintf('identified_case_%d',k); c.Output_Directory=opt.Output_Directory;
    c.Save_Results=true;
    r=run_rfdac_simulation(c); m=r.metrics;
    assert(abs(r.TX_Beta-truthBeta)<1e-12,'Physical TX changed across calibration cases.');
    assert(m.Invalid_Output_Codeword_Pairs==0,'Noninteger/out-of-range DAC words.');
    if k==1, validationJitter=r.TX_Jitter; validationReference=r.Reference_Symbols;
    else
        assert(isequal(r.TX_Jitter,validationJitter) && isequal(r.Reference_Symbols,validationReference), ...
            'Four-way validation changed data or jitter realization.');
    end
    cases{k}=struct('Label',labels{k},'Received_Symbols',r.Received_Symbols, ...
        'Reference_Symbols',r.Reference_Symbols,'Reference_Constellation',r.Reference_Constellation, ...
        'EVM_Percent',m.EVM_Percent,'EVM_dB',m.EVM_dB,'MER_dB',-m.EVM_dB);
    caseRows{k}=table(string(labels{k}),m.EVM_Percent,m.EVM_dB,-m.EVM_dB, ...
        m.Symbol_Error_Rate,m.DPD_DAC_I_Clipped_Full+m.DPD_DAC_Q_Clipped_Full, ...
        'VariableNames',{'Calibration','EVM_Percent','EVM_dB','MER_dB','SER','Output_Clipped_Samples'});
    clear r;
end
report.Cases=cases; report.Case_Table=vertcat(caseRows{:});
% Deliberately naive subtraction, shown only as a counterexample, not fitted.
rawJitterEVM=2*pi*meta.LO_Frequency*meta.Known_Jitter_RMS_s;
iqEVM=tan(abs(est.IQ_Error_Deg)*pi/360);
naiveVariance=(cases{4}.EVM_Percent/100)^2-rawJitterEVM^2-iqEVM^2;
report.Reliability.Raw_Jitter_EVM_Percent=100*rawJitterEVM;
report.Reliability.Naive_Power_Subtraction_SNR_dB=NaN;
if naiveVariance>0
    report.Reliability.Naive_Power_Subtraction_SNR_dB=-10*log10(naiveVariance);
end
report.Reliability.Naive_Subtraction_Warning='Raw phase-jitter RMS is not post-filter symbol EVM; error sources can be correlated.';

% Grader-only clean TX run AFTER the estimator is frozen. Never used to fit.
grade=cfg; grade.LO_Jitter_Enable=false; grade.LO_Quadrature_Error_Enable=false;
grade.DPD_Enable=false; grade.Num_Symbols=opt.Validation_Symbols;
clean=run_rfdac_simulation(grade);
report.Truth.Clean_Grader_SNR_dB=-clean.metrics.EVM_dB;
report.Truth.Clean_Grader_EVM_Percent=clean.metrics.EVM_Percent; clear clean;
report.Capture_Fields={'Codes','RF','Start_Time','Amplitude'};
report.Public_Metadata_Fields=fieldnames(meta);
report.Estimator_Options=fitOptions;
report.Completed=true;
writetable(report.Case_Table,fullfile(opt.Output_Directory,'four_calibration_cases.csv'));
writetable(trials,fullfile(opt.Output_Directory,'identification_trials.csv'));
save(fullfile(opt.Output_Directory,'identification_report.mat'),'report','-v7.3');
plot_rfdac_identification(report);
plot_rfdac_identification_reliability(report);
write_report(report);
assignin('base','identification_report',report);
disp(report.Case_Table); disp(report.Reliability);
fprintf('RX IDENTIFICATION AND FOUR-CASE VALIDATION COMPLETE: %s\n',opt.Output_Directory);
fprintf('Four-case constellation: %s\n',report.Figure_Files.Four_Cases);
fprintf('Replay without simulating: show_rfdac_identification(identification_report)\n');
if bdIsLoaded(cfg.Model_Name), close_system(cfg.Model_Name,0); end
end

function captures=collect(cfg,opt,trial)
amplitudes=[opt.Training_Amplitudes cfg.Input_Amplitude];
captures=cell(numel(amplitudes),1);
for k=1:numel(amplitudes)
    c=cfg; c.Num_Symbols=opt.Training_Symbols; c.Input_Amplitude=amplitudes(k);
    c.Random_Seed=opt.Training_Seed+trial*1000+k*31;
    captures{k}=rfdac_capture_tx_observation(c,opt);
end
end
function est=performance(est,meta)
prediction=rfdac_predict_clean_tx(est.Beta,meta);
est.TX_SNR_dB=prediction.TX_SNR_dB;
est.TX_EVM_Percent=prediction.EVM_Percent;
lo=rfdac_predict_clean_tx(est.Beta_CI95(1),meta);
hi=rfdac_predict_clean_tx(est.Beta_CI95(2),meta);
est.TX_SNR_CI95_dB=sort([lo.TX_SNR_dB hi.TX_SNR_dB]);
end
function row=estimate_row(trial,est,truth)
row=table(trial,est.IQ_Error_Deg,est.IQ_CI95_Deg(1),est.IQ_CI95_Deg(2), ...
    est.TX_SNR_dB,est.TX_SNR_CI95_dB(1),est.TX_SNR_CI95_dB(2),est.Beta, ...
    est.IQ_Error_Deg-truth.IQ_Error_Deg,est.TX_SNR_dB-truth.TX_SNR_dB, ...
    'VariableNames',{'Trial','IQ_Error_Deg','IQ_CI_Low','IQ_CI_High','TX_SNR_dB', ...
    'SNR_CI_Low','SNR_CI_High','Estimated_Beta','IQ_Estimation_Error_Deg','SNR_Estimation_Error_dB'});
end
function write_report(r)
fid=fopen(fullfile(r.Output_Directory,'identification_summary.txt'),'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'UNKNOWN-NUMERIC-PARAMETER RX IDENTIFICATION (known atan family / nominal linear paths)\n');
fprintf(fid,'Truth / estimated clean TX EVM-equivalent SNR: %.6f / %.6f dB\n',r.Truth.TX_SNR_dB,r.Estimate.TX_SNR_dB);
fprintf(fid,'Truth / estimated static IQ: %.6f / %.6f degree\n',r.Truth.IQ_Error_Deg,r.Estimate.IQ_Error_Deg);
fprintf(fid,'Conditional 95%% intervals: SNR [%.6f %.6f] dB; IQ [%.6f %.6f] degree\n',r.Estimate.TX_SNR_CI95_dB,r.Estimate.IQ_CI95_Deg);
fprintf(fid,'Primary estimate is frozen for all four calibration cases; repeated fits are not averaged or selected.\n');
if r.Reliability.Repeatability_Evaluated
    fprintf(fid,'Independent training trials: %d; SNR RMSE %.6f dB; IQ RMSE %.6f degree\n',r.Reliability.Trials,r.Reliability.TX_SNR_RMSE_dB,r.Reliability.IQ_RMSE_Deg);
    fprintf(fid,'Empirical interval coverage: SNR %.3f; IQ %.3f (small trial count, not a general guarantee).\n',r.Reliability.TX_SNR_CI_Coverage,r.Reliability.IQ_CI_Coverage);
else
    fprintf(fid,'Repeated identification disabled: no repeated-trial RMSE or empirical coverage is reported.\n');
end
for k=1:numel(r.Assumptions), fprintf(fid,'ASSUMPTION: %s\n',r.Assumptions{k}); end
fprintf(fid,'Estimator data excludes actual beta, IQ angle, target SNR and actual jitter realization.\n');
fprintf(fid,'No calibration of irreducible random AWGN SNR is claimed.\n');
end
