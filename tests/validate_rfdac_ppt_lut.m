function report=validate_rfdac_ppt_lut(fullRun,iqDegrees)
% Verify the PPT flow, including real raw-code RF capture and interpolation.
if nargin<1, fullRun=false; end
paths=setup_rfdac_project(); c=init_rfdac_model();
if nargin>=2, c.LO_Quadrature_Error_Deg=iqDegrees; end
c.Num_Symbols=512; c.TX_Nonlinearity_Beta=.469191101183668;
c.DPD_LUT_Training_Order=64;
if fullRun, c.Num_Symbols=16384; c.DPD_LUT_Training_Order=16384; end
c.Make_Plots=false; c.Save_Results=false; c.Waveform_Log_Frames=16;
folder=fullfile(paths.Validation,'ppt_dpd_20261102');
if ~isfolder(folder), mkdir(folder); end

% Recover a deliberately delayed/rotated synthetic framed capture exactly.
pilot=complex([-1;-1;1;1],[-1;1;1;-1]); order=(1:4)';
frame=[complex(zeros(64,1));repelem(pilot,8);complex(zeros(64,1))];
y=[complex(zeros(37,1));.8*exp(.7i)*repmat(frame,2,1);complex(zeros(128,1))];
[z,a]=rfdac_align_ppt_training(y,pilot,order,8,64,2,8);
assert(a.Correlation_Lag_DAC==37 && max(abs(z-.8*pilot))<1e-12);
report.Synthetic_Frame_Phase_Passed=true;

r=run_rfdac_simulation(c); l=r.DPD.LUT; meta=l.Training_Metadata;
assert(strcmp(r.DPD.Placement,'waveform_after_rrc') && strcmp(meta.Pipeline,'ppt_serpentine_v1'));
assert(all(isnan([r.DPD.Beta r.DPD.Alpha r.DPD.Image])));
assert(l.Training_Order==c.DPD_LUT_Training_Order && l.Points==2^(2*c.DAC_Bits));
assert(isequal(l.Size,[1024 1024]) && all(meta.Counts==c.DPD_LUT_Training_Repeats));
assert(meta.Physical_Beta==r.TX_Beta && ~meta.DPD_Enabled && meta.Jitter_Enabled);
assert(all(meta.Zero_Prefix_RMS_V<1e-3));
% Interpolation must reproduce every actual measured grid node.
nodeIndex=double(l.Training_I(:))-double(l.Output_I(1,1))+1+ ...
    l.Size(1)*(double(l.Training_Q(:))-double(l.Output_Q(1,1)));
report.Interpolation_Node_Max_Error=max(abs(l.Dense_Output(nodeIndex)-l.Training_Output(:)));
assert(report.Interpolation_Node_Max_Error<1e-12);
% Independent exhaustive nearest-output check for held-out desired DAC words.
stream=RandStream('mt19937ar','Seed',20261102);
probe=complex(randi(stream,1024,32,1)-513,randi(stream,1024,32,1)-513)*r.DPD.LSB;
[v,~,indices]=rfdac_dpd_lut_lookup(probe,r.DPD);
for k=1:numel(probe)
    selected=abs(l.Dense_Output(indices(k))-probe(k))^2;
    assert(abs(selected-min(abs(l.Dense_Output(:)-probe(k)).^2))<1e-13);
end
poison=r.DPD; poison.Beta=NaN; poison.Alpha=NaN; poison.Image=NaN;
assert(isequal(v,rfdac_dpd_lut_lookup(probe,poison)));
usage=rfdac_lut_usage(r); assert(usage.Verified_Logged_Samples>0);
assert(r.metrics.Invalid_Output_Codeword_Pairs==0);
off=c; off.DPD_Enable=false;
baseline=run_rfdac_simulation(off);
assert(isequal(r.Reference_Symbols,baseline.Reference_Symbols) && isequal(r.TX_Jitter,baseline.TX_Jitter));
report.Before=baseline.metrics; report.After=r.metrics;
report.Training_Metadata=meta; report.All_Passed=true;
if fullRun, tag='full'; else, tag='smoke'; end
if nargin>=2, tag=sprintf('%s_iq_%g',tag,iqDegrees); end
save(fullfile(folder,[tag '_validation.mat']),'report','r','baseline','-v7.3');
metrics=struct2table([baseline.metrics;r.metrics]); metrics.Case={'DPD OFF';'PPT LUT DPD ON'};
writetable(metrics,fullfile(folder,[tag '_metrics.csv']));
r.DPD_Comparison=struct('Before_Received_Symbols',baseline.Received_Symbols,'Before_Metrics',baseline.metrics);
r.cfg.Output_Directory=folder; r.cfg.Run_Tag=tag; r.cfg.Figure_Visible='off';
f=plot_rfdac_dpd_pair(r); close(f);
fprintf('PPT FLOW %s PASS: OFF %.8f%%; ON %.8f%%; SER %.8g -> %.8g.\n', ...
    tag,baseline.metrics.EVM_Percent,r.metrics.EVM_Percent,baseline.metrics.Symbol_Error_Rate,r.metrics.Symbol_Error_Rate);
end
