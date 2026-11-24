function validation=validate_rfdac_iq_mismatch_sweep(report)
%VALIDATE_RFDAC_IQ_MISMATCH_SWEEP Audit saved measurements without simulation.
% No TX fitting, LUT retraining or synthetic RF responses are used here.
paths=setup_rfdac_project();
if nargin<1 || isempty(report)
    saved=load(fullfile(paths.Validation,'iq_mismatch_7GHz_45dB_16k', ...
        'iq_mismatch_report.mat'),'report');
    report=saved.report;
end
assert(isstruct(report) && isscalar(report) && report.Completed,'Incomplete sweep report.');
c=report.Configuration; contract(c);
assert(report.Training_Order==16384 && report.Validation_Order==4096);
assert(report.Target_EVM_dB==-40);
beta=report.Physical_Beta; cal=report.TX_Calibration;
assert(isfinite(beta) && beta>=0 && c.TX_Nonlinearity_Beta==beta);
assert(cal.Beta==beta && cal.Target_EVM_dB==c.TX_Target_EVM_dB && ...
    abs(cal.Achieved_EVM_dB-c.TX_Target_EVM_dB)<=c.TX_EVM_Fit_Tolerance_dB, ...
    'The frozen plant does not carry its requested clean-TX calibration.');

t=report.Table; n=height(t);
assert(istable(t) && n>0 && numel(report.Case_Files)==n);
angles=t.IQ_Mismatch_Deg;
assert(all(isfinite(angles)) && all(angles>=0) && all(diff(angles)>0));
% Accept any explicitly selected angle vector; the default 1:.25:3 has nine.
firstPayloadReference=[]; runPayload=[];
lsb=2*c.DAC_Full_Scale/2^c.DAC_Bits;
lo=-2^(c.DAC_Bits-1); hi=2^(c.DAC_Bits-1)-1;
constellation=qammod((0:4095)',4096,'gray','UnitAveragePower',true);
levels=unique(real(constellation)); [ii,qq]=ndgrid(levels,levels);
expectedTargets=complex(ii(:),qq(:))*c.Input_Amplitude;
maxEVMRecalculationError=0;
for k=1:n
    file=report.Case_Files{k};
    if ~isfile(file), file=fullfile(report.Output_Directory,file); end
    saved=load(file,'caseData'); d=saved.caseData;
    cc=d.Configuration; contract(cc);
    assert(d.IQ_Mismatch_Deg==angles(k) && cc.LO_Quadrature_Error_Deg==angles(k));
    assert(d.Physical_Beta==beta && cc.TX_Nonlinearity_Beta==beta && ...
        d.Signature.Configuration.TX_Nonlinearity_Beta==beta, ...
        'Physical TX changed between sweep cases.');
    fields={'DAC_Bits','DAC_Full_Scale','Input_Amplitude','Sample_Rate', ...
        'DAC_Sample_Rate','Symbol_Rate','RRC_Rolloff','RRC_Span','Num_Symbols', ...
        'LPF_Cutoff','LPF_Order','RX_LPF_Cutoff','RX_LPF_Order', ...
        'RX_Equalizer_Order','RX_Equalizer_Max_Boost_dB','RX_Equalizer_Regularization', ...
        'Random_Seed','DPD_LUT_Training_Seed','DPD_LUT_Training_Repeats', ...
        'DPD_LUT_Training_Dwell_Samples','DPD_LUT_Training_Prefix_Zeros', ...
        'LO_Frequency','LO_RMS_Jitter','LO_Phase_Errors_Deg','Jitter_Mode','Jitter_Bandwidth'};
    for j=1:numel(fields)
        assert(isequaln(cc.(fields{j}),c.(fields{j})), ...
            'A physical or measurement setting changed across the IQ sweep.');
    end
    if isempty(runPayload), runPayload=logical(d.Signature.Run_Payload); end
    assert(logical(d.Signature.Run_Payload)==runPayload);
    assert(cc.DPD_Nonlinearity_Enable==c.DPD_Nonlinearity_Enable);

    % Exactly 128x128 distinct measured, legal DAC coordinates, independent
    % of the larger numerical candidate grid derived by interpolation.
    assert(d.Training_Order==16384 && numel(d.Training_Drive)==16384 && ...
        numel(d.Training_Output)==16384 && numel(unique(d.Training_Drive))==16384);
    legalcodes(d.Training_Drive/lsb,lo,hi);
    trainingCodes=reshape(complex(round(real(d.Training_Drive/lsb)), ...
        round(imag(d.Training_Drive/lsb))),128,128);
    axisI=real(trainingCodes(:,1)); axisQ=imag(trainingCodes(1,:));
    assert(numel(unique(axisI))==128 && numel(unique(axisQ))==128);
    assert(isequal(real(trainingCodes),repmat(axisI,1,128)) && ...
        isequal(imag(trainingCodes),repmat(axisQ,128,1)));
    assert(all(diff(axisI)>0) && all(diff(axisQ)>0));
    assert(all(isfinite(d.Training_Output)));
    meta=d.Training_Metadata;
    assert(meta.Training_Order==16384 && isequal(meta.Training_Size,[128 128]));
    assert(isequal(meta.Training_Drive(:),d.Training_Drive(:)) && ...
        isequal(meta.Snake_Order(:),snakeorder([128 128])));
    assert(numel(meta.Counts)==16384 && all(meta.Counts==2) && ...
        cc.DPD_LUT_Training_Repeats==2);
    assert(isequal(size(meta.Point_Observations_Aligned),[16384 2]));
    closevalue(mean(meta.Point_Observations_Aligned,2),d.Training_Output(:),1e-12);
    assert(contains(meta.Source,'SLX') && strcmp(meta.Pipeline,'ppt_serpentine_v1'));
    assert(~meta.DPD_Enabled && meta.Jitter_Enabled && meta.Physical_Beta==beta);
    assert(meta.Key.Version>=3 && strcmp(meta.Key.Observation_Domain, ...
        'phase_aligned_equalized_RX_envelope_V'));
    assert(meta.Key.Physical_Beta==beta && ...
        meta.Key.LO_Quadrature_Error_Deg==angles(k) && meta.Key.RX_Equalizer_Enable && ...
        meta.Key.LO_Frequency==c.LO_Frequency && meta.Key.LO_RMS_Jitter==c.LO_RMS_Jitter);
    checkAdditionalMismatch(cc,c);
    checkAdditionalMismatch(meta.Key,c);
    checkSavedLegs(d,cc);
    checkSavedLegs(meta,cc);
    checkLoggedLOErrors(meta,cc);

    target=d.Target4096(:); mapped=d.Mapped4096(:); cap=d.Capture;
    assert(numel(target)==4096 && numel(mapped)==4096);
    closevalue(target,expectedTargets,1e-12);
    legalcodes(d.Input_Target_Codes(:),lo,hi);
    expectedCodes=complex(min(max(round(real(target)/lsb),lo),hi), ...
        min(max(round(imag(target)/lsb),lo),hi));
    assert(isequal(d.Input_Target_Codes(:),expectedCodes));
    legalcodes(d.Mapped_DAC_Codes(:),lo,hi);
    closevalue(mapped,d.Mapped_DAC_Codes(:)*lsb,1e-12);
    candidateShape=[max(axisI)-min(axisI)+1,max(axisQ)-min(axisQ)+1];
    assert(d.Interpolated_Candidate_Count==prod(candidateShape) && ...
        d.Interpolated_Candidate_Count>=16384);
    indices=d.Mapping_Indices(:);
    assert(numel(indices)==4096 && all(isfinite(indices)) && ...
        all(indices==round(indices)) && all(indices>=1 & indices<=prod(candidateShape)));
    [mi,mq]=ind2sub(candidateShape,double(indices));
    closevalue(d.Mapped_DAC_Codes(:), ...
        complex(min(axisI)+mi-1,min(axisQ)+mq-1),1e-9);
    assert(numel(d.Mapping_Predicted_Output)==4096 && ...
        all(isfinite(d.Mapping_Predicted_Output)), ...
        'Derived mapping predictions must not masquerade as measured training points.');
    mappingTraining=d.Training_Output;
    if ~c.DPD_Nonlinearity_Enable
        assert(strcmp(d.Calibration_Mode,'iq_only'));
        if isfield(d.IQ_Estimate,'Scale_Reference')
            iq=rfdac_fit_measured_iq(d.Training_Drive,d.Training_Output,d.IQ_Estimate.Scale_Reference);
        else
            iq=rfdac_fit_measured_iq(d.Training_Drive,d.Training_Output);
        end
        closevalue(iq.Matrix,d.IQ_Estimate.Matrix,1e-12);
        M=iq.Matrix; u=d.Training_Drive;
        mappingTraining=complex(M(1,1)*real(u)+M(1,2)*imag(u), ...
            M(2,1)*real(u)+M(2,2)*imag(u));
        closevalue(mappingTraining(:),d.Mapping_Training_Output(:),1e-12);
        z=mapped; linearOutput=complex(M(1,1)*real(z)+M(1,2)*imag(z), ...
            M(2,1)*real(z)+M(2,2)*imag(z));
        % IQ-only words invert one fixed linear map within DAC rounding;
        % an extra radius-dependent TX inverse would violate this bound.
        assert(max(abs(linearOutput-d.Input_Target_Codes(:)*lsb))<=sqrt(2)*lsb*norm(M,2));
        if runPayload, assert(~d.Payload_Metrics.DPD_Nonlinearity_Enabled); end
    end
    forward=griddedInterpolant({axisI,axisQ(:)}, ...
        reshape(mappingTraining,128,128),'linear','none');
    reconstructed=forward(real(d.Mapped_DAC_Codes(:)),imag(d.Mapped_DAC_Codes(:)));
    closevalue(reconstructed,d.Mapping_Predicted_Output(:),1e-12);

    % The second experiment must contain a fresh 4096-point physical capture
    % of these mapped words, with the native DPD bypassed to avoid a second map.
    assert(cap.Point_Count==4096 && isequal(cap.Shape,[64 64]) && ...
        numel(cap.Output)==4096 && isequal(cap.Snake_Order(:),snakeorder([64 64])));
    assert(contains(cap.Source,'Actual SLX') && contains(cap.Source,'physical RF'));
    assert(~cap.DPD_Applied_In_Capture && ~cap.Configuration.DPD_Enable);
    assert(cap.Physical_Beta==beta && cap.Configuration.TX_Nonlinearity_Beta==beta);
    assert(cap.Configuration.LO_Frequency==c.LO_Frequency && ...
        cap.Configuration.LO_RMS_Jitter==c.LO_RMS_Jitter && cap.Configuration.LO_Jitter_Enable && ...
        cap.Configuration.LO_Quadrature_Error_Deg==angles(k) && ...
        isequal(cap.Configuration.LO_Phase_Errors_Deg,cc.LO_Phase_Errors_Deg) && ...
        strcmp(cap.Configuration.Jitter_Mode,cc.Jitter_Mode));
    checkAdditionalMismatch(cap.Configuration,cc);
    checkSavedLegs(cap,cc);
    checkLoggedLOErrors(cap,cc);
    closevalue(cap.Drive(:),mapped,1e-12);
    closevalue(cap.Drive_Codes(:),d.Mapped_DAC_Codes(:),1e-9);
    assert(cap.DAC_I_Clipped_Full==0 && cap.DAC_Q_Clipped_Full==0);
    assert(isequal(meta.RX_Equalizer_FIR,cap.RX_Equalizer_FIR) && ...
        numel(meta.RX_Equalizer_FIR)==cc.RX_Equalizer_Order+1);
    assert(isequal(meta.Observer_Fractional_FIR,cap.Observer_Fractional_FIR) && ...
        meta.Observer_Delay_DAC_Samples==cap.Observer_Delay_DAC_Samples);
    assert(cap.RX_Equalizer.Enabled && cap.RX_Equalizer.Delay_DAC_Samples==cc.RX_Equalizer_Order/2);
    assert(meta.Training_Seed==cc.DPD_LUT_Training_Seed && ...
        meta.Training_Seed~=cap.Seed && meta.Training_Seed~=cc.Random_Seed && ...
        cap.Seed~=cc.Random_Seed && cap.Configuration.Random_Seed==cap.Seed && ...
        cap.Jitter_Seed==cap.Seed+1);
    assert(cap.Repeats==2 && numel(cap.Counts)==4096 && all(cap.Counts==2));
    assert(isequal(size(cap.Alignment.Point_Observations_Aligned),[4096 2]));
    closevalue(cap.Output(:),mean(cap.Alignment.Point_Observations_Aligned,2),1e-12);
    assert(cap.Prefix_Zero_Samples>=2*cap.Guard_DAC_Samples+16 && ...
        meta.Prefix_Zero_Samples>=2*meta.Guard_DAC_Samples+16);

    [snake,z,g]=pointmetrics(cap.Output,target,c.Input_Amplitude);
    closevalue(z,d.Snake_Received_Normalized(:),1e-12);
    closevalue(g,d.Snake_Fitted_Complex_Gain,1e-12);
    comparemetrics(snake,d.Snake_Metrics);
    closevalue(t.Snake_EVM_dB(k),snake.EVM_dB,1e-9);
    closevalue(t.Snake_EVM_Percent(k),snake.EVM_Percent,1e-10);
    closevalue(t.Snake_SER(k),snake.Symbol_Error_Rate,1e-12);
    assert(logical(t.Pass_Snake_40dB(k))==(snake.EVM_dB<=-40));
    assert(numel(d.Snake_Repeat_EVM_dB)==2);
    for j=1:2
        repeated=pointmetrics(cap.Alignment.Point_Observations_Aligned(:,j),target,c.Input_Amplitude);
        closevalue(repeated.EVM_dB,d.Snake_Repeat_EVM_dB(j),1e-9);
    end
    maxEVMRecalculationError=max(maxEVMRecalculationError, ...
        abs(t.Snake_EVM_dB(k)-snake.EVM_dB));

    if runPayload
        received=d.Payload_Received(:); reference=d.Payload_Reference(:);
        assert(numel(received)==c.Num_Symbols && numel(reference)==c.Num_Symbols && ...
            all(isfinite(received)) && all(isfinite(reference)));
        if isempty(firstPayloadReference), firstPayloadReference=reference; end
        assert(isequal(reference,firstPayloadReference),'Payload data changed across IQ cases.');
        % These saved symbols already have their one fitted complex gain
        % removed. Refitting here would hide an inconsistent saved result.
        payload=normalizedmetrics(received,reference,1);
        comparemetrics(payload,d.Payload_Metrics);
        closevalue(t.Payload_EVM_dB(k),payload.EVM_dB,1e-9);
        closevalue(t.Payload_EVM_Percent(k),payload.EVM_Percent,1e-10);
        closevalue(t.Payload_SER(k),payload.Symbol_Error_Rate,1e-12);
        maxEVMRecalculationError=max(maxEVMRecalculationError, ...
            abs(t.Payload_EVM_dB(k)-payload.EVM_dB));
        assert(d.Payload_Metrics.TX_Nonlinearity_Beta==beta && ...
            d.Payload_Metrics.DPD_LUT_Training_Order==16384 && ...
            d.Payload_Metrics.RX_Equalizer_Enabled);
        checkLOMetrics(d.Payload_Metrics,cc);
        assert(logical(t.Pass_Payload_40dB(k))==(payload.EVM_dB<=-40));
    else
        assert(isempty(d.Payload_Received) && isempty(d.Payload_Reference) && ...
            isnan(t.Payload_EVM_dB(k)) && ~t.Pass_Payload_40dB(k));
    end
    row=table2struct(t(k,:)); names=fieldnames(row);
    for j=1:numel(names), assert(isequaln(row.(names{j}),d.Row.(names{j}))); end
    clear saved d cap meta;
end
checkthreshold(report.Snake_Threshold,angles,t.Snake_EVM_dB,-40);
checkthreshold(report.Payload_Threshold,angles,t.Payload_EVM_dB,-40);
validation=struct('All_Passed',true,'AllPassed',true,'Num_Cases',n, ...
    'Training_Order',16384,'Validation_Order',4096,'Physical_Beta',beta, ...
    'Worst_Snake_EVM_dB',max(t.Snake_EVM_dB), ...
    'Worst_Payload_EVM_dB',report.Payload_Threshold.Worst_EVM_dB, ...
    'Maximum_EVM_Recalculation_Error_dB',maxEVMRecalculationError, ...
    'No_Simulation_Or_Refit',true);
disp(validation);
fprintf('Saved 16384-training -> mapped4096 -> actual RF4096 sweep audit passed (%d cases).\n',n);
end

function contract(c)
assert(isfinite(c.LO_Frequency) && c.LO_Frequency>0 && ...
    isfinite(c.LO_RMS_Jitter) && c.LO_RMS_Jitter>=0 && ...
    isfinite(c.TX_Target_EVM_dB) && c.TX_Target_EVM_dB<0);
assert(c.QAM_Order==4096 && c.LO_Jitter_Enable && c.LO_Quadrature_Error_Enable && ...
    c.TX_Nonlinearity_Enable && c.RX_Equalizer_Enable && strcmp(c.RX_LO_Mode,'ideal'));
assert(numel(c.LO_Phase_Errors_Deg)==4 && all(isfinite(c.LO_Phase_Errors_Deg)) && ...
    ismember(c.Jitter_Mode,{'white','bandlimited'}));
assert(c.DPD_Enable && c.DPD_IQ_Enable && ...
    strcmp(c.DPD_Algorithm,'lut') && strcmp(c.DPD_LUT_Training_Mode,'link') && ...
    c.DPD_LUT_Training_Order==16384 && strcmp(c.DPD_LUT_Interpolation,'linear') && ...
    c.DPD_LUT_Fraction_Bits==0);
end

function checkAdditionalMismatch(record,expected)
assert(zeroByDefault(record,'LO_Differential_Phase_Error_Deg')== ...
    zeroByDefault(expected,'LO_Differential_Phase_Error_Deg') && ...
    zeroByDefault(record,'LO_Quadrature_Amplitude_Mismatch')== ...
    zeroByDefault(expected,'LO_Quadrature_Amplitude_Mismatch'), ...
    'Additional LO mismatch changed across the saved records.');
end

function checkSavedLegs(record,c)
phaseDifference=zeroByDefault(c,'LO_Differential_Phase_Error_Deg');
amplitudeMismatch=zeroByDefault(c,'LO_Quadrature_Amplitude_Mismatch');
if isfield(record,'LO_Phase_Offsets_Deg') || phaseDifference~=0 || amplitudeMismatch~=0
    q=c.LO_Quadrature_Error_Deg;
    expectedPhase=[0 90+q 180+phaseDifference 270+q+phaseDifference]+reshape(c.LO_Phase_Errors_Deg,1,4);
    expectedAmplitude=[1 1+amplitudeMismatch 1 1+amplitudeMismatch];
    closevalue(record.LO_Phase_Offsets_Deg,expectedPhase,1e-12);
    closevalue(record.LO_Leg_Amplitudes,expectedAmplitude,1e-12);
end
end

function checkLOMetrics(metrics,c)
checkAdditionalMismatch(metrics,c);
closevalue(metrics.Configured_TX_Jitter_fs,1e15*c.LO_RMS_Jitter,1e-9);
checkLoggedLOErrors(metrics,c);
if isfield(metrics,'LO_Static_IQ_Theoretical_EVM_Percent') && all(c.LO_Phase_Errors_Deg==0)
    % Both opposite pairs have the same phase separation, so their common
    % differential phase cancels from the image-to-desired ratio.
    gain=1+zeroByDefault(c,'LO_Quadrature_Amplitude_Mismatch');
    phase=c.LO_Quadrature_Error_Deg;
    image=abs((1-gain*exp(1i*deg2rad(phase)))/(1+gain*exp(1i*deg2rad(phase))));
    closevalue(metrics.LO_Static_IQ_Theoretical_EVM_Percent,100*image,1e-9);
    closevalue(metrics.LO_Effective_Q_to_I_Gain,gain,1e-12);
    closevalue(metrics.LO_Effective_Quadrature_Phase_Error_Deg,atan2d(sind(phase),cosd(phase)),1e-9);
end
end

function checkLoggedLOErrors(record,c)
if isfield(record,'LO_Leg_Waveform_Max_Error') || ...
        zeroByDefault(c,'LO_Differential_Phase_Error_Deg')~=0 || ...
        zeroByDefault(c,'LO_Quadrature_Amplitude_Mismatch')~=0
    bound=1e-9*max(1,1+zeroByDefault(c,'LO_Quadrature_Amplitude_Mismatch'));
    assert(abs(record.LO_Leg_Waveform_Max_Error)<bound && ...
        abs(record.LO_Differential_Waveform_Max_Error)<bound);
end
end

function value=zeroByDefault(s,field)
value=0;
if isfield(s,field), value=s.(field); end
end

function order=snakeorder(shape)
order=reshape(1:prod(shape),shape);
order(:,2:2:end)=flipud(order(:,2:2:end)); order=order(:);
end

function legalcodes(x,lo,hi)
assert(all(isfinite(x)) && all(abs(real(x)-round(real(x)))<1e-8) && ...
    all(abs(imag(x)-round(imag(x)))<1e-8) && ...
    all(real(x)>=lo & real(x)<=hi & imag(x)>=lo & imag(x)<=hi), ...
    'Saved input contains fractional or out-of-range DAC words.');
end

function [m,z,g]=pointmetrics(y,target,amplitude)
y=y(:); target=target(:); g=(target'*y)/(target'*target);
assert(isfinite(g) && abs(g)>eps);
z=y/g; m=normalizedmetrics(z,target,amplitude);
end

function m=normalizedmetrics(z,reference,amplitude)
evm=norm(z-reference)/norm(reference);
ids=qamdemod(reference/amplitude,4096,'gray','UnitAveragePower',true);
dec=qamdemod(z/amplitude,4096,'gray','UnitAveragePower',true);
m=struct('EVM_dB',20*log10(max(evm,realmin)),'EVM_Percent',100*evm, ...
    'Symbol_Error_Rate',mean(ids~=dec),'Symbol_Errors',sum(ids~=dec));
end

function comparemetrics(actual,saved)
names={'EVM_dB','EVM_Percent','Symbol_Error_Rate','Symbol_Errors'};
for j=1:numel(names), closevalue(actual.(names{j}),saved.(names{j}),1e-9); end
end

function closevalue(a,b,tolerance)
assert(isequal(size(a),size(b)) && all(isfinite(a(:))) && all(isfinite(b(:))) && ...
    all(abs(a(:)-b(:))<=tolerance),'Saved values disagree with independently recomputed measurements.');
end

function checkthreshold(saved,angles,evm,target)
valid=isfinite(evm); fail=valid & evm>target;
assert(isequal(saved.Tested_Angles_Deg(:),angles(:)) && ...
    isequal(saved.Tested_Range_Deg,[min(angles) max(angles)]) && ...
    logical(saved.Any_Failure)==any(fail));
first=find(fail,1);
if isempty(first)
    assert(isnan(saved.First_Failing_Tested_Angle_Deg) && ...
        isnan(saved.Last_Passing_Tested_Angle_Before_Failure_Deg));
else
    assert(saved.First_Failing_Tested_Angle_Deg==angles(first));
    previous=find(valid(1:first-1) & ~fail(1:first-1),1,'last');
    if isempty(previous)
        assert(isnan(saved.Last_Passing_Tested_Angle_Before_Failure_Deg));
    else
        assert(saved.Last_Passing_Tested_Angle_Before_Failure_Deg==angles(previous));
    end
end
if any(valid)
    ids=find(valid); [worst,index]=max(evm(valid));
    closevalue(saved.Worst_EVM_dB,worst,1e-9);
    assert(saved.Worst_Angle_Deg==angles(ids(index)));
    closevalue(saved.Worst_Margin_dB,target-worst,1e-9);
else
    assert(isnan(saved.Worst_EVM_dB) && isnan(saved.Worst_Angle_Deg) && isnan(saved.Worst_Margin_dB));
end
end
