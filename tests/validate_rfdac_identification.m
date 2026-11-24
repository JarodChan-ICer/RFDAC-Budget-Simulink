function validation=validate_rfdac_identification(report)
% Audit saved identification data/results only; never rerun or refit the TX.
paths=setup_rfdac_project();
if nargin<1
    data=load(fullfile(paths.Validation,'rx_identification','identification_report.mat'),'report');
    report=data.report;
end
assert(isstruct(report) && isscalar(report) && report.Completed,'Incomplete identification report.');
folder=report.Output_Directory;
observationFile=fullfile(folder,'training_observations.mat');
stored=who('-file',observationFile);
assert(isempty(setdiff(stored,{'captures','meta'})),'Training file contains undeclared variables.');
data=load(observationFile,'captures','meta');
captures=data.captures; meta=data.meta;
assert(iscell(captures) && numel(captures)>=3,'Missing small/large-swing observations.');
captureFields={'Codes';'RF';'Start_Time';'Amplitude'};
for k=1:numel(captures)
    capture=captures{k};
    assert(isequal(sort(fieldnames(capture)),sort(captureFields)), ...
        'Capture whitelist failed: hidden TX information entered estimator data.');
    assert(all(isfinite(capture.Codes)) && all(isfinite(capture.RF)));
    ci=real(capture.Codes); cq=imag(capture.Codes);
    assert(all(ci==round(ci) & cq==round(cq)),'Training input contains fractional DAC words.');
    assert(all(ci>=meta.Min_Code & ci<=meta.Max_Code & cq>=meta.Min_Code & cq<=meta.Max_Code));
    assert(numel(capture.RF)==numel(capture.Codes)*meta.DAC_Hold, ...
        'Input-code and RF observation windows have unequal duration.');
end
publicFields={'RF_Sample_Rate';'DAC_Sample_Rate';'LO_Frequency';'DAC_LSB'; ...
    'TX_FIR';'RX_FIR';'TX_RRC';'RX_RRC';'Fractional_FIR';'DAC_Hold'; ...
    'DAC_Samples_Per_Symbol';'Total_Delay';'Reference_Symbols';'Reference_Amplitude'; ...
    'Num_Frames';'Min_Code';'Max_Code';'Known_Jitter_RMS_s';'Jitter_Mode';'Jitter_Bandwidth'};
% The nominal RX equalizer is public linear-path data. Older captures omit it.
if isfield(meta,'RX_Equalizer_FIR'), publicFields{end+1,1}='RX_Equalizer_FIR'; end
assert(isequal(sort(fieldnames(meta)),sort(publicFields)), ...
    'Public metadata whitelist failed: unexpected TX parameter or actual phase information.');
assert(isequal(sort(report.Capture_Fields(:)),sort(captureFields)));
assert(isequal(sort(report.Public_Metadata_Fields(:)),sort(publicFields)));
assert(isfield(report,'Estimator_Options'),'Estimator argument whitelist was not recorded.');
assert(isfield(report.Estimator_Options,'Cluster_Symbols'));
assert(isempty(setdiff(fieldnames(report.Estimator_Options),{'Cluster_Symbols';'Max_Fit_Samples'})), ...
    'Simulator observer settings or other hidden inputs were passed to the estimator.');

est=report.Estimate; truth=report.Truth;
assert(isfinite(est.Beta) && est.Beta>=0 && isfinite(est.IQ_Error_Deg) && isfinite(est.TX_SNR_dB));
snrError=est.TX_SNR_dB-truth.TX_SNR_dB;
iqError=est.IQ_Error_Deg-truth.IQ_Error_Deg;
assert(abs(snrError)<.25,'TX SNR estimate missed the 0.25 dB validation tolerance.');
assert(abs(iqError)<.1,'Static IQ estimate missed the 0.1 degree validation tolerance.');

options=report.Options;
trainingSeeds=options.Training_Seed+(0:options.Monte_Carlo_Repeats)'*1000+(1:numel(captures))*31;
assert(numel(unique(trainingSeeds(:)))==numel(trainingSeeds),'Repeated training seeds.');
assert(all(trainingSeeds(:)~=options.Validation_Seed),'Training and validation seeds overlap.');
expected=[1 0;0 1;1 1;0 0]; evm=zeros(4,1);
for k=1:4
    saved=load(fullfile(folder,sprintf('identified_case_%d_results.mat',k)),'results');
    r=saved.results; c=r.cfg; m=r.metrics;
    assert(c.TX_Nonlinearity_Enable && c.LO_Quadrature_Error_Enable && c.LO_Jitter_Enable, ...
        'An impairment was disabled instead of being calibrated.');
    assert(abs(r.TX_Beta-truth.Beta)<1e-12 && abs(c.TX_Nonlinearity_Beta-truth.Beta)<1e-12, ...
        'Physical nonlinear TX changed across calibration cases.');
    assert(abs(c.LO_Quadrature_Error_Deg-truth.IQ_Error_Deg)<1e-12);
    assert(c.LO_Frequency==truth.LO_Frequency && c.LO_RMS_Jitter==truth.Jitter_RMS_s);
    assert(all(c.LO_Phase_Errors_Deg==0),'Unexpected extra LO phase impairments.');
    assert(~isempty(c.DPD_TX_Beta_Estimate) && abs(c.DPD_TX_Beta_Estimate-est.Beta)<1e-12, ...
        'DPD used oracle/default TX nonlinearity instead of the frozen receiver estimate.');
    assert(~isempty(c.DPD_Quadrature_Estimate_Deg) && abs(c.DPD_Quadrature_Estimate_Deg-est.IQ_Error_Deg)<1e-12, ...
        'DPD used oracle/default IQ angle instead of the frozen receiver estimate.');
    assert(isequal(logical([c.DPD_Nonlinearity_Enable c.DPD_IQ_Enable]),logical(expected(k,:))));
    assert(logical(c.DPD_Enable)==any(expected(k,:)));
    assert(logical(m.DPD_Nonlinearity_Enabled)==logical(expected(k,1)));
    assert(logical(m.DPD_IQ_Enabled)==logical(expected(k,2)));
    assert(c.Random_Seed==options.Validation_Seed && numel(r.Reference_Symbols)==options.Validation_Symbols);
    assert(c.DAC_Bits==10 && m.Invalid_Output_Codeword_Pairs==0);
    assert(m.DPD_DAC_I_Clipped_Full==0 && m.DPD_DAC_Q_Clipped_Full==0, ...
        'Validation DPD output clips the DAC.');
    assert(all(r.waveforms.codes_i==round(r.waveforms.codes_i)) && ...
        all(r.waveforms.codes_q==round(r.waveforms.codes_q)));
    assert(all(r.waveforms.codes_i>=meta.Min_Code & r.waveforms.codes_i<=meta.Max_Code));
    assert(all(r.waveforms.codes_q>=meta.Min_Code & r.waveforms.codes_q<=meta.Max_Code));
    if k==1
        reference=r.Reference_Symbols; jitter=r.TX_Jitter; identifiers=r.Transmitted_IDs;
    else
        assert(isequal(r.Reference_Symbols,reference) && isequal(r.Transmitted_IDs,identifiers), ...
            'Four calibration cases used different validation data.');
        assert(isequal(r.TX_Jitter,jitter),'Four calibration cases used different jitter realizations.');
    end
    evm(k)=m.EVM_Percent;
    assert(abs(evm(k)-report.Case_Table.EVM_Percent(k))<1e-10,'Saved case/report metrics differ.');
end
assert(evm(3)<min(evm([1 2 4])),'Joint calibration did not outperform each individual/uncalibrated case.');

% Coverage is an observation, never a promise or acceptance criterion.
validation.All_Passed=true;
validation.TX_SNR_Estimation_Error_dB=snrError;
validation.IQ_Estimation_Error_Deg=iqError;
validation.TX_SNR_CI_Covers_Truth=inside(truth.TX_SNR_dB,est.TX_SNR_CI95_dB);
validation.IQ_CI_Covers_Truth=inside(truth.IQ_Error_Deg,est.IQ_CI95_Deg);
validation.Empirical_TX_SNR_CI_Coverage=report.Reliability.TX_SNR_CI_Coverage;
validation.Empirical_IQ_CI_Coverage=report.Reliability.IQ_CI_Coverage;
validation.Independent_Training_Seeds=trainingSeeds;
validation.Held_Out_Validation_Seed=options.Validation_Seed;
validation.Four_Case_EVM_Percent=evm;
validation.Estimator_Data_Whitelist_Verified=true;
validation.Physical_TX_And_Jitter_Frozen=true;
validation.Note='Read-only saved-data audit; model-conditional interval coverage is reported, not guaranteed.';
save(fullfile(folder,'identification_validation.mat'),'validation');
fid=fopen(fullfile(folder,'identification_validation.txt'),'w'); assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'PASS: estimator capture, metadata and option whitelists; no hidden TX values or actual jitter trace.\n');
fprintf(fid,'PASS: frozen physical TX, frozen estimated DPD parameters, independent validation seed.\n');
fprintf(fid,'PASS: identical validation symbols/jitter in all four saved cases; valid unclipped 10-bit words.\n');
fprintf(fid,'PASS: joint calibration improves EVM over each single correction and no correction.\n');
fprintf(fid,'Estimation errors: TX equivalent SNR %+.6f dB; static IQ %+.6f degree.\n',snrError,iqError);
fprintf(fid,'Primary conditional CI includes truth: TX SNR %d, IQ %d. Coverage is not an acceptance requirement.\n', ...
    validation.TX_SNR_CI_Covers_Truth,validation.IQ_CI_Covers_Truth);
disp(validation); disp('SAVED-DATA RX IDENTIFICATION VALIDATION PASSED.');
end
function yes=inside(value,interval)
assert(isnumeric(interval) && numel(interval)==2 && all(isfinite(interval)) && interval(1)<=interval(2));
yes=value>=interval(1) && value<=interval(2);
end
