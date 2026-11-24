function report=run_rfdac_iq_mismatch_sweep(cfg,angles,options)
%RUN_RFDAC_IQ_MISMATCH_SWEEP Measured 16384-snake -> mapped 4096 -> RF snake.
% report=run_rfdac_iq_mismatch_sweep(); % [1 2 3] deg, -40 dB target
% Interpolation uses ONLY the 16384 actual measured forward responses.
% The derived dense numerical search grid is not extra measured training.
paths=setup_rfdac_project();
if nargin<1 || isempty(cfg), cfg=init_rfdac_model(); end
if nargin<2 || isempty(angles), angles=[1 2 3]; end
if nargin<3, options=struct(); end
validateattributes(angles,{'numeric'},{'vector','real','finite','nonnegative','nonempty'});
angles=unique(angles(:));
validateattributes(cfg.TX_Target_EVM_dB,{'numeric'},{'scalar','real','finite','<',0});
folder=getoption(options,'Output_Directory',fullfile(paths.Validation, ...
    sprintf('iq_mismatch_%gGHz_%gdB_16k',cfg.LO_Frequency/1e9,-cfg.TX_Target_EVM_dB)));
defaultMode='joint';
if ~cfg.DPD_Nonlinearity_Enable, defaultMode='iq_only'; end
mode=validatestring(getoption(options,'Calibration_Mode',defaultMode),{'joint','iq_only'});
if strcmp(mode,'iq_only') && ~isfield(options,'Output_Directory'), folder=[folder '_iq_only']; end
runPayload=getoption(options,'Run_Payload',true);
resume=getoption(options,'Resume',true);
target=-40;
if ~isfolder(folder), mkdir(folder); end
% Explicit settings form this experiment's contract; keep all other analog,
% DAC, LPF, equalizer, hold and pulse-shaping settings visible in saved cfg.
cfg.Jitter_Mode='white'; cfg.RX_Equalizer_Enable=true;
cfg.LO_Jitter_Enable=true; cfg.LO_Quadrature_Error_Enable=true;
cfg.RX_LO_Mode='ideal';
cfg.RX_LO_Frequency=[]; cfg.RX_LO_RMS_Jitter=[];
cfg.TX_Nonlinearity_Enable=true;
cfg.QAM_Order=4096; cfg.DPD_Enable=true;
cfg.DPD_IQ_Enable=true; cfg.DPD_Nonlinearity_Enable=strcmp(mode,'joint');
cfg.DPD_Algorithm='lut'; cfg.DPD_LUT_Training_Mode='link';
cfg.DPD_LUT_Size_Mode='training_order'; cfg.DPD_LUT_Training_Order=16384;
cfg.DPD_LUT_Points=16384; cfg.DPD_LUT_Address_Bits=[7 7];
cfg.DPD_LUT_Interpolation='linear'; cfg.DPD_LUT_Fraction_Bits=0;
cfg.DPD_LUT_Training_Observed=[]; cfg.DPD_LUT_Training_Metadata=struct();
cfg.DPD_LUT_Capture=[]; cfg.Make_Plots=false; cfg.Save_Results=false;
cfg.Waveform_Log_Frames=8; cfg.Figure_Visible='off';
if isfield(options,'Plant_Calibration')
    calibration=options.Plant_Calibration;
    assert(~isempty(cfg.TX_Nonlinearity_Beta) && isscalar(cfg.TX_Nonlinearity_Beta) && ...
        calibration.Target_EVM_dB==cfg.TX_Target_EVM_dB && ...
        abs(calibration.Achieved_EVM_dB-cfg.TX_Target_EVM_dB)<cfg.TX_EVM_Fit_Tolerance_dB ...
        && calibration.Beta==cfg.TX_Nonlinearity_Beta, ...
        'A frozen plant must carry calibration at the requested clean-TX EVM.');
else
    cfg.TX_Nonlinearity_Beta=[];
end
% Calibrate once on the ordinary random-RRC reference, then freeze beta for
% training, all IQ angles and both validation waveforms. No per-case refit.
[plant,cfg]=rfdac_prepare(cfg);
cfg.TX_Nonlinearity_Beta=plant.TX_Beta;
if ~isfield(options,'Plant_Calibration'), calibration=plant.TX_Calibration; end
clear plant;
signature=struct('Version',1,'Configuration',cfg,'Run_Payload',logical(runPayload));
if strcmp(mode,'iq_only'), signature.Version=2; end
rows=cell(numel(angles),1); files=cell(numel(angles),1);
for k=1:numel(angles)
    angle=angles(k); tag=strrep(sprintf('iq_%05.2f',angle),'.','p');
    file=fullfile(folder,[tag '.mat']); files{k}=file;
    if resume && isfile(file)
        saved=load(file,'caseData');
        previousSignature=saved.caseData.Signature;
        addedFields={'LO_Differential_Phase_Error_Deg','LO_Quadrature_Amplitude_Mismatch'};
        for fieldIndex=1:numel(addedFields)
            field=addedFields{fieldIndex};
            if ~isfield(previousSignature.Configuration,field)
                previousSignature.Configuration.(field)=0;
            end
        end
        if isequaln(previousSignature,signature) && saved.caseData.IQ_Mismatch_Deg==angle
            rows{k}=saved.caseData.Row;
            fprintf('Reuse IQ %.2f deg: snake %.4f dB, payload %.4f dB\n', ...
                angle,rows{k}.Snake_EVM_dB,rows{k}.Payload_EVM_dB);
            clear saved; continue;
        end
        clear saved;
    end
    fprintf('\nIQ sweep %d/%d: %.2f deg; exactly 16384 measured training coordinates.\n',k,numel(angles),angle);
    c=cfg; c.LO_Quadrature_Error_Deg=angle; c.Run_Tag=tag;
    [p,c]=rfdac_prepare(c);
    reused=false;
    if isfield(options,'Training_Directory')
        trainingFile=fullfile(options.Training_Directory,[tag '.mat']);
        if isfile(trainingFile)
            training=load(trainingFile,'caseData');
            assert(isequaln(training.caseData.Training_Metadata.Key,rfdac_lut_training_key(c,p)), ...
                'rfdac:TrainingReuse','Saved training does not match this physical configuration.');
            observed=training.caseData.Training_Output; meta=training.caseData.Training_Metadata;
            reused=true; clear training;
            fprintf('Reusing actual 16384-point RF capture with identical physical/stimulus fingerprint.\n');
        end
    end
    if ~reused, [observed,meta]=rfdac_train_link_lut(c,p); end
    assert(numel(observed)==16384 && p.DPD.LUT.Training_Order==16384);
    c.DPD_LUT_Training_Observed=observed; c.DPD_LUT_Training_Metadata=meta;
    [p,c]=rfdac_prepare(c); lut=p.DPD.LUT;
    assert(isequal(lut.Training_Size,[128 128]) && numel(lut.Training_Output)==16384);
    assert(strcmp(lut.Format,'ppt_measured_2d_lut_v1') && all(isnan([p.DPD.Beta p.DPD.Alpha p.DPD.Image])));
    % Every point of the square 4096QAM constellation is visited in snake
    % order, rather than using 4096 randomly selected QAM symbols.
    levels=unique(real(p.Constellation)); [i,q]=ndgrid(levels,levels);
    targets=complex(i(:),q(:))*c.Input_Amplitude;
    [mapped,~,inputCodes]=rfdac_dpd_codewords(targets,p.DPD);
    [lookup,~,indices]=rfdac_dpd_lut_lookup(inputCodes*p.LSB,p.DPD);
    assert(numel(targets)==4096 && isequal(mapped,lookup));
    assert(all(real(mapped/p.LSB)==round(real(mapped/p.LSB))) && ...
        all(imag(mapped/p.LSB)==round(imag(mapped/p.LSB))));
    % Mapped inputs are already predistorted: inject them into actual DACs
    % once, with native DPD bypassed, and capture a fresh physical output.
    opt=struct('Repeats',c.DPD_LUT_Training_Repeats, ...
        'Dwell',c.DPD_LUT_Training_Dwell_Samples, ...
        'Prefix',c.DPD_LUT_Training_Prefix_Zeros,'Seed',c.Random_Seed+2000);
    capture=rfdac_capture_serpentine(c,p,mapped,[64 64],opt);
    assert(numel(capture.Output)==4096 && capture.Physical_Beta==cfg.TX_Nonlinearity_Beta);
    [snake,z,gain]=measurepoints(capture.Output,targets,c.QAM_Order,c.Input_Amplitude);
    perRepeat=zeros(size(capture.Alignment.Point_Observations_Aligned,2),1);
    for j=1:numel(perRepeat)
        m=measurepoints(capture.Alignment.Point_Observations_Aligned(:,j),targets,c.QAM_Order,c.Input_Amplitude);
        perRepeat(j)=m.EVM_dB;
    end
    payload=struct('EVM_dB',NaN,'EVM_Percent',NaN,'Symbol_Error_Rate',NaN);
    payloadSymbols=[]; payloadReference=[];
    if runPayload
        payloadResult=run_rfdac_simulation(c);
        assert(payloadResult.TX_Beta==cfg.TX_Nonlinearity_Beta && payloadResult.DPD.LUT.Training_Order==16384);
        assert(isequal(payloadResult.DPD.LUT.Training_Output(:),observed(:)));
        payload=payloadResult.metrics;
        payloadSymbols=payloadResult.Received_Symbols;
        payloadReference=payloadResult.Reference_Symbols;
        clear payloadResult;
    end
    row=struct('IQ_Mismatch_Deg',angle,'Snake_EVM_dB',snake.EVM_dB, ...
        'Snake_EVM_Percent',snake.EVM_Percent,'Snake_SER',snake.Symbol_Error_Rate, ...
        'Payload_EVM_dB',payload.EVM_dB,'Payload_EVM_Percent',payload.EVM_Percent, ...
        'Payload_SER',payload.Symbol_Error_Rate,'Pass_Snake_40dB',snake.EVM_dB<=target, ...
        'Pass_Payload_40dB',runPayload && payload.EVM_dB<=target);
    rows{k}=row;
    % Keep the actual paired training observations and mapped/received 4096
    % points. Dense derived search arrays can be reconstructed from these.
    if isfield(meta,'Captured_Envelope_DAC'), meta=rmfield(meta,'Captured_Envelope_DAC'); end
    storedCfg=c; storedCfg.DPD_LUT_Training_Metadata=meta;
    caseData=struct('Signature',signature,'Configuration',storedCfg, ...
        'IQ_Mismatch_Deg',angle,'Physical_Beta',p.TX_Beta,'Training_Order',16384, ...
        'LO_Phase_Offsets_Deg',p.LO_Phase_Offsets*180/pi,'LO_Leg_Amplitudes',p.LO_Leg_Amplitudes, ...
        'Training_Drive',lut.Training_Drive(:),'Training_Output',observed(:), ...
        'Training_Metadata',meta,'Interpolated_Candidate_Count',lut.Points, ...
        'Calibration_Mode',mode,'Mapping_Training_Output',lut.Mapping_Training_Output(:), ...
        'Target4096',targets,'Mapped4096',mapped,'Input_Target_Codes',inputCodes, ...
        'Mapped_DAC_Codes',mapped/p.LSB,'Mapping_Indices',indices, ...
        'Mapping_Predicted_Output',lut.Dense_Output(indices), ...
        'Capture',capture,'Snake_Received_Normalized',z,'Snake_Fitted_Complex_Gain',gain, ...
        'Snake_Metrics',snake,'Snake_Repeat_EVM_dB',perRepeat, ...
        'Payload_Metrics',payload,'Payload_Received',payloadSymbols, ...
        'Payload_Reference',payloadReference,'Row',row, ...
        'Verification','Actual SLX capture of precomputed LUT-mapped words; native DPD bypassed to prevent a second mapping');
    if isfield(lut,'IQ_Estimate'), caseData.IQ_Estimate=lut.IQ_Estimate; end
    save(file,'caseData','-v7.3');
    fprintf('IQ %.2f deg: 4096-snake %.5f dB (%.5f%%); random-RRC payload %.5f dB; target %.1f dB.\n', ...
        angle,snake.EVM_dB,snake.EVM_Percent,payload.EVM_dB,target);
    clear caseData capture p lut c;
    % Persist completed rows after every case so long sweeps are recoverable.
    partial=vertcat(rows{1:k});
    writetable(struct2table(partial),fullfile(folder,'iq_mismatch_progress.csv'));
end
table=struct2table(vertcat(rows{:}));
report=struct('Completed',true,'Configuration',cfg,'Physical_Beta',cfg.TX_Nonlinearity_Beta, ...
    'Calibration_Mode',mode, ...
    'TX_Calibration',calibration,'Training_Order',16384,'Validation_Order',4096, ...
    'Interpolation','Linear interpolation from exactly 16384 measured forward points', ...
    'Target_EVM_dB',target,'Table',table,'Case_Files',{files},'Output_Directory',folder, ...
    'Snake_Threshold',threshold(table.IQ_Mismatch_Deg,table.Snake_EVM_dB,target), ...
    'Payload_Threshold',threshold(table.IQ_Mismatch_Deg,table.Payload_EVM_dB,target));
if strcmp(mode,'iq_only')
    report.Interpolation='Linear IQ geometry fitted from directions of exactly 16384 measured responses; no radial inverse';
end
save(fullfile(folder,'iq_mismatch_report.mat'),'report','-v7.3');
writetable(table,fullfile(folder,'iq_mismatch_metrics.csv'));
figs=plot_rfdac_iq_mismatch_sweep(report); close(figs);
disp(table); disp(report.Snake_Threshold); disp(report.Payload_Threshold);
fprintf('Finished measured 16384 -> mapped 4096 -> actual RF 4096 sweep.\n');
end

function [m,z,g]=measurepoints(y,target,order,amplitude)
y=y(:); target=target(:); g=(target'*y)/(target'*target);
assert(isfinite(g) && abs(g)>eps,'rfdac:SnakeGain','Invalid received snake gain.');
z=y/g; evm=norm(z-target)/norm(target);
ids=qamdemod(target/amplitude,order,'gray','UnitAveragePower',true);
dec=qamdemod(z/amplitude,order,'gray','UnitAveragePower',true);
m=struct('EVM_dB',20*log10(max(evm,realmin)),'EVM_Percent',100*evm, ...
    'Symbol_Error_Rate',mean(ids~=dec),'Symbol_Errors',sum(ids~=dec), ...
    'Num_Points',numel(target),'Fitted_Complex_Gain',g, ...
    'Definition','EVM of measured point-center means over all 4096 target points, one fitted complex gain');
end

function result=threshold(angles,evm,target)
valid=isfinite(evm); fail=valid & evm>target;
result=struct('Tested_Range_Deg',[min(angles) max(angles)], ...
    'Tested_Angles_Deg',angles,'First_Failing_Tested_Angle_Deg',NaN, ...
    'Last_Passing_Tested_Angle_Before_Failure_Deg',NaN, ...
    'Worst_EVM_dB',NaN,'Worst_Angle_Deg',NaN,'Worst_Margin_dB',NaN, ...
    'Any_Failure',any(fail),'Description','No finite results');
if ~any(valid), return; end
ids=find(valid); [worst,i]=max(evm(valid)); result.Worst_EVM_dB=worst;
result.Worst_Angle_Deg=angles(ids(i)); result.Worst_Margin_dB=target-worst;
if any(fail)
    first=find(fail,1); result.First_Failing_Tested_Angle_Deg=angles(first);
    previous=find(valid(1:first-1) & ~fail(1:first-1),1,'last');
    if ~isempty(previous), result.Last_Passing_Tested_Angle_Before_Failure_Deg=angles(previous); end
    result.Description='Failure observed at a tested angle; bracket is sampled, not a monotonic or noise-free guarantee';
else
    result.Description='No failure crossing in the tested range; no threshold outside this range is inferred';
end
end

function value=getoption(options,name,fallback)
if isfield(options,name), value=options.(name); else, value=fallback; end
end
