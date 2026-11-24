function report=validate_rfdac_rx_equalizer()
% Validate fitted response, gain protection, timing and actual native SLX.
% A/B uses an unchanged linear TX: no beta fitting can mask filter effects.
paths=setup_rfdac_project();
c=init_rfdac_model();
c.Num_Symbols=2048; c.Make_Plots=false; c.Save_Results=false;
c.Waveform_Log_Frames=inf;
c.DPD_Enable=false; c.DPD_Algorithm='analytic';
c.TX_Nonlinearity_Enable=false; c.TX_Nonlinearity_Beta=0;
c.LO_Jitter_Enable=false; c.LO_Quadrature_Error_Enable=false;
c.RX_LO_Mode='ideal'; c.RX_LO_Frequency=[];
c.RX_Equalizer_Enable=true;
c.RX_Equalizer_Order=256; c.RX_Equalizer_Max_Boost_dB=6;
c.RX_Equalizer_Regularization=1e-6;
% Intentionally broad transitions produce measurable loss in the 400 MHz
% total occupied band while satisfying the project's LPF passband guard.
c.LPF_Cutoff=300e6; c.LPF_Order=256;
c.RX_LPF_Cutoff=300e6; c.RX_LPF_Order=256;
c.LPF_Transition_Bandwidth=200e6;

[p,c]=rfdac_prepare(c);
assert(numel(p.RX_Equalizer_FIR)==c.RX_Equalizer_Order+1);
assert(max(abs(p.RX_Equalizer_FIR-fliplr(p.RX_Equalizer_FIR)))<1e-12);
assert(abs(sum(p.RX_Equalizer_FIR)-1)<1e-12);
assert(p.RX_Equalizer.Delay_DAC_Samples==c.RX_Equalizer_Order/2);
assert(p.RX_Equalizer.Bandwidth_Hz==c.Baseband_Frequency/2);
assert(p.RX_Equalizer.Ripple_Before_dB>0.1,'Droop fixture is ineffective.');
assert(p.RX_Equalizer.Ripple_After_dB<p.RX_Equalizer.Ripple_Before_dB/4, ...
    'Fitted equalizer did not materially flatten the occupied band.');
assert(p.RX_Equalizer.Peak_Gain_dB<=c.RX_Equalizer_Max_Boost_dB+1e-8);

% Coefficients depend on the linear path, never the random payload or hidden
% static IQ/nonlinear errors. A changed LPF must produce a new fit.
other=c; other.Random_Seed=c.Random_Seed+7;
other.LO_Quadrature_Error_Deg=23; other.TX_Nonlinearity_Beta=0.8;
[same,~]=rfdac_prepare(other);
assert(isequal(p.RX_Equalizer_FIR,same.RX_Equalizer_FIR));
changed=c; changed.RX_LPF_Cutoff=360e6;
[different,~]=rfdac_prepare(changed);
assert(norm(p.RX_Equalizer_FIR-different.RX_Equalizer_FIR)>1e-7, ...
    'Changed LPF did not trigger a new equalizer fit.');

off=c; off.RX_Equalizer_Enable=false;
[bypass,~]=rfdac_prepare(off);
assert(isequal(bypass.RX_Equalizer_FIR,1));
assert(bypass.RX_Equalizer.Delay_DAC_Samples==0);
assert(p.Total_Delay-bypass.Total_Delay==c.RX_Equalizer_Order/2);
assert(abs(bypass.RX_Equalizer.Ripple_Before_dB- ...
    bypass.RX_Equalizer.Ripple_After_dB)<1e-12);
before=run_rfdac_simulation(off);
after=run_rfdac_simulation(c);
assert(before.TX_Beta==0 && after.TX_Beta==0);
assert(isequal(before.Reference_Symbols,after.Reference_Symbols));
payload=c.Num_Symbols*p.DAC_Samples_Per_Symbol;
assert(isequal(before.waveforms.codes_i(1:payload),after.waveforms.codes_i(1:payload)));
assert(isequal(before.waveforms.codes_q(1:payload),after.waveforms.codes_q(1:payload)));
assert(after.metrics.EVM_Percent<before.metrics.EVM_Percent/2, ...
    'Actual SLX EVM did not improve with the fitted RX equalizer.');

% Independent sample-stream filtering proves the block runs once per DAC
% sample across frame boundaries and that all selected symbols are aligned.
reference=after.waveforms.rx_baseband(1:p.DAC_Hold:end);
reference=filter(p.RX_Equalizer_FIR,1,reference);
reference=filter(p.RX_RRC,1,reference);
reference=filter(p.Fractional_FIR,1,reference);
indices=p.Total_Delay+1+(0:c.Num_Symbols-1)*p.DAC_Samples_Per_Symbol;
reference=reference(indices);
sampleError=max(abs(reference(:)-after.Received_Symbols_Raw(:)));
assert(sampleError<1e-10,'SLX equalizer/timing differs from sample-stream reference.');
assert(abs(after.metrics.RX_Inband_Ripple_After_dB-p.RX_Equalizer.Ripple_After_dB)<1e-12);

% A deliberately tight gain ceiling leaves residual droop instead of
% attempting an unbounded inverse of strongly attenuated frequencies.
limited=c; limited.RX_Equalizer_Max_Boost_dB=1;
[cap,~]=rfdac_prepare(limited);
assert(cap.RX_Equalizer.Boost_Limited);
assert(cap.RX_Equalizer.Peak_Gain_dB<=limited.RX_Equalizer_Max_Boost_dB+1e-8);
assert(cap.RX_Equalizer.Ripple_After_dB>p.RX_Equalizer.Ripple_After_dB);

% RF auto-sampling changes RF LPF orders, while EQ remains at DAC rate.
automatic=c; automatic.LO_Frequency=24e9;
automatic.RX_LO_Frequency=[]; automatic.Oversampling_Ratio=[];
automatic.Num_Symbols=256; automatic.Waveform_Log_Frames=8;
[pa,resolved]=rfdac_prepare(automatic);
assert(resolved.Sample_Rate>c.Sample_Rate);
assert(pa.RX_Equalizer.Sample_Rate_Hz==resolved.DAC_Sample_Rate);
assert(pa.RX_Equalizer.Delay_DAC_Samples==p.RX_Equalizer.Delay_DAC_Samples);
manual=resolved; manual.Sample_Rate_Auto=false;
[pm,~]=rfdac_prepare(manual);
assert(isequal(pa.RX_Equalizer_FIR,pm.RX_Equalizer_FIR));
highLO=run_rfdac_simulation(automatic);
assert(isfinite(highLO.metrics.EVM_Percent));
assert(highLO.metrics.RX_Inband_Ripple_After_dB<highLO.metrics.RX_Inband_Ripple_Before_dB);

% Invalid design requests must fail during preparation, before simulation.
bad=c; bad.RX_Equalizer_Order=255; mustreject(bad);
bad=c; bad.RX_Equalizer_Max_Boost_dB=NaN; mustreject(bad);
bad=c; bad.RX_Equalizer_Regularization=0; mustreject(bad);
bad=c; bad.RX_Equalizer_Enable=2; mustreject(bad);

report=struct('All_Passed',true, ...
    'Ripple_Before_dB',p.RX_Equalizer.Ripple_Before_dB, ...
    'Ripple_After_dB',p.RX_Equalizer.Ripple_After_dB, ...
    'EVM_Before_Percent',before.metrics.EVM_Percent, ...
    'EVM_After_Percent',after.metrics.EVM_Percent, ...
    'EVM_Improvement_dB',before.metrics.EVM_dB-after.metrics.EVM_dB, ...
    'Peak_Gain_dB',p.RX_Equalizer.Peak_Gain_dB, ...
    'Sample_Stream_Max_Error',sampleError, ...
    'Auto_Sample_Rate_Hz',resolved.Sample_Rate, ...
    'Auto_Sampling_EVM_Percent',highLO.metrics.EVM_Percent, ...
    'Payload_Independent',true,'LPF_Change_Refitted',true, ...
    'Bypass_Zero_Delay',true,'Boost_Limit_Checked',true, ...
    'Invalid_Configuration_Rejected',true);
folder=fullfile(paths.Validation,'rx_equalizer');
if ~isfolder(folder), mkdir(folder); end
save(fullfile(folder,'rx_equalizer_validation.mat'),'report');
writetable(struct2table(report),fullfile(folder,'rx_equalizer_validation.csv'));
disp(report);
end

function mustreject(c)
rejected=false;
try
    rfdac_prepare(c);
catch
    rejected=true;
end
assert(rejected,'Invalid equalizer configuration was accepted.');
end
