function capture=rfdac_capture_serpentine(cfg,p,drive,shape,options)
%RFDAC_CAPTURE_SERPENTINE Measure an explicitly supplied DAC-code snake in SLX.
% drive is in ndgrid order, with shape=[I points,Q points]. It may contain
% repeated words after inverse mapping. The raw source bypasses TX RRC and
% the DPD lookup: supplied drive words are the actual physical DAC inputs.
% Output contains point averages, not payload symbols or payload EVM.
if nargin<5, options=struct(); end
validateattributes(shape,{'numeric'},{'vector','numel',2,'integer','positive','finite'});
shape=reshape(shape,1,2);
validateattributes(drive,{'numeric'},{'vector','numel',prod(shape),'finite'});
drive=drive(:);
repeats=getoption(options,'Repeats',2);
dwell=getoption(options,'Dwell',25);
requestedPrefix=getoption(options,'Prefix',512);
seed=getoption(options,'Seed',cfg.Random_Seed);
validateattributes(repeats,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(dwell,{'numeric'},{'scalar','integer','>=',4,'finite'});
validateattributes(requestedPrefix,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative','<',2^32-2});
assert(isfield(p,'RX_Equalizer_FIR') && isfield(p,'RX_Equalizer'), ...
    'rfdac:SerpentinePreparation','Prepare the configured RX equalizer before capture.');

% The caller supplies mapped legal DAC words. Reject a fractional-code or
% over-rail request instead of silently changing the input/output pairs.
codes=drive/p.LSB;
assert(all(abs(real(codes)-round(real(codes)))<1e-9) && ...
    all(abs(imag(codes)-round(imag(codes)))<1e-9), ...
    'rfdac:SerpentineCodes','Serpentine drive must contain integer DAC-code voltages.');
assert(all(real(codes)>=p.Min_Code & real(codes)<=p.Max_Code) && ...
    all(imag(codes)>=p.Min_Code & imag(codes)<=p.Max_Code), ...
    'rfdac:SerpentineRange','Serpentine drive exceeds the legal DAC range.');

order=reshape(1:numel(drive),shape);
order(:,2:2:end)=flipud(order(:,2:2:end)); order=order(:);
% Both RF LPFs and the DAC-rate equalizer need quiet settling guards. Keep
% the requested prefix in the record and expose any necessary extension.
guard=ceil((numel(p.TX_FIR)+numel(p.RX_FIR)-2)/p.DAC_Hold)+ ...
    numel(p.RX_Equalizer_FIR)-1+8;
prefix=max(requestedPrefix,2*guard+16);
snake=repelem(drive(order),dwell);
frame=[complex(zeros(prefix,1));snake;complex(zeros(prefix,1))];
raw=repmat(frame,repeats,1);

c=cfg;
c.DPD_Enable=false; % the supplied inputs have already been mapped, if needed
c.DPD_LUT_Training_Observed=[]; c.DPD_LUT_Training_Metadata=struct();
c.DPD_LUT_Capture=struct('Mode','raw_serpentine','Samples',raw);
c.TX_Nonlinearity_Beta=p.TX_Beta; % freeze the same physical TX for every capture
% The mapper is a dummy in raw mode, but matching its label to a valid square
% grid keeps run diagnostics faithful for the 16384/4096-point experiments.
if numel(drive)>=4 && numel(drive)<=2^20 && mod(log2(numel(drive)),1)==0
    c.QAM_Order=numel(drive);
end
c.Num_Symbols=max(16,ceil(numel(raw)/p.DAC_Samples_Per_Symbol));
c.Random_Seed=seed;
c.Make_Plots=false; c.Save_Results=false; c.Plot_DPD_Comparison=false;
c.Waveform_Log_Frames=8; % the raw observation port still logs the full record
fprintf(['SLX snake capture: %dx%d = %d points, %d DAC samples/point, ' ...
    '%d repeats, prefix %d (requested %d), seed %d.\n'], ...
    shape,numel(drive),dwell,repeats,prefix,requestedPrefix,seed);

timer=tic; r=run_rfdac_simulation(c); elapsed=toc(timer);
assert(r.TX_Beta==p.TX_Beta && ~r.DPD.Enabled, ...
    'rfdac:SerpentinePlant','Capture changed the physical TX or applied DPD twice.');
assert(r.waveform_start_time.rx_envelope==0, ...
    'rfdac:SerpentineRecord','Capture does not contain the complete zero-prefixed record.');
assert(isequal(r.filters.RX_Equalizer_FIR,p.RX_Equalizer_FIR), ...
    'rfdac:SerpentineEqualizer','Prepared equalizer changed during the capture.');

% The logged envelope is immediately after RF LPF/decimation. Applying the
% identical causal equalizer here gives its pre-matched-RRC observation; no
% ideal plant, TX model inverse, or hidden RF reference is used in extraction.
delay=(r.cfg.LPF_Order+r.cfg.RX_LPF_Order)/(2*p.DAC_Hold)+ ...
    (p.DAC_Hold-1)/(2*p.DAC_Hold)+p.RX_Equalizer.Delay_DAC_Samples;
fraction=ceil(delay)+1-delay;
b=ones(1,4);
for k=0:3
    others=setdiff(0:3,k);
    b(k+1)=prod((fraction-others)./(k-others));
end
y=filter(p.RX_Equalizer_FIR,1,r.waveforms.rx_envelope);
y=filter(b,1,y);
[observed,alignment]=rfdac_align_ppt_training(y,drive,order,dwell,prefix,repeats,guard);

capture=struct();
capture.Output=observed;
capture.Drive=drive;
capture.Drive_Codes=complex(round(real(codes)),round(imag(codes)));
capture.Shape=shape; capture.Point_Count=numel(drive);
capture.Snake_Order=order;
capture.Alignment=alignment;
capture.Point_Observations_Before_Phase=alignment.Point_Observations_Before_Phase;
capture.Point_Observations_Aligned=alignment.Point_Observations_Aligned;
capture.Counts=alignment.Counts;
capture.Physical_Beta=r.TX_Beta;
capture.LO_Phase_Offsets_Deg=r.LO_Phase_Offsets_Deg;
capture.LO_Leg_Amplitudes=r.LO_Leg_Amplitudes;
capture.LO_Leg_Waveform_Max_Error=r.metrics.LO_Leg_Waveform_Max_Error;
capture.LO_Differential_Waveform_Max_Error=r.metrics.LO_Differential_Waveform_Max_Error;
capture.RX_Equalizer=p.RX_Equalizer;
capture.RX_Equalizer_FIR=p.RX_Equalizer_FIR;
capture.Observer_Fractional_FIR=b;
capture.Observer_Delay_DAC_Samples=ceil(delay)+1;
capture.Guard_DAC_Samples=guard;
capture.Requested_Prefix_Zero_Samples=requestedPrefix;
capture.Prefix_Zero_Samples=prefix;
capture.Prefix_Extended=prefix>requestedPrefix;
capture.Dwell_DAC_Samples=dwell;
capture.Repeats=repeats;
capture.Seed=seed;
capture.Jitter_Seed=seed+1;
capture.Simulation_Seconds=elapsed;
capture.Source=['Actual SLX supplied DAC-code serpentine -> physical RF -> coherent RX envelope ' ...
    '-> configured causal RX equalizer -> fractional timing -> frame/phase extraction'];
capture.Measurement_Domain='Per-point mean RX voltage before the matched RRC';
capture.DPD_Applied_In_Capture=false;
capture.DAC_I_Clipped_Full=r.metrics.Input_Code_I_Clipped_Full;
capture.DAC_Q_Clipped_Full=r.metrics.Input_Code_Q_Clipped_Full;
assert(capture.DAC_I_Clipped_Full==0 && capture.DAC_Q_Clipped_Full==0, ...
    'rfdac:SerpentineClipping','Physical capture clipped a supplied legal DAC word.');
capture.Configuration=r.cfg;
% Raw sample arrays and previous observations are recoverable from the
% explicit points/order/dwell/guards; avoid retaining a second long record.
capture.Configuration.DPD_LUT_Capture=[];
capture.Configuration.DPD_LUT_Training_Observed=[];
capture.Configuration.DPD_LUT_Training_Metadata=struct();
end

function value=getoption(options,name,fallback)
if isfield(options,name), value=options.(name); else, value=fallback; end
end
