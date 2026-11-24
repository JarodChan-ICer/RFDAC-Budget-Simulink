function results=rfdac_measure(simout,cfg,p)
%RF DAC measurements; only one constant training gain/phase is removed.
results.cfg=cfg;
results.sampling=p.Sampling;
results.Reference_Constellation=p.Constellation;
results.Reference_Symbols=p.Reference;
results.Transmitted_IDs=p.Symbol_IDs;
names={'input_i','input_q','codes_i','codes_q','dac_i','dac_q', ...
    'filtered_i','filtered_q','lo_i','lo_q','lo_phase_error', ...
    'rf_before_gm','rf_output','rx_baseband','rx_matched','rx_symbol', ...
    'online_decisions','online_symbols','lo_0','lo_90','lo_180','lo_270', ...
    'rx_phase_error','lo_statistics','dpd_i','dpd_q','dpd_statistics', ...
    'dpd_ideal_i','dpd_ideal_q','input_codes_i','input_codes_q','rx_envelope'};
for k=1:numel(names)
    d=simout.get(['log_' names{k}]);
    results.waveforms.(names{k})=unframe(d);
    results.waveform_start_time.(names{k})=d.time(1);
    results.waveform_num_frames.(names{k})=numel(d.time);
end
w=results.waveforms;
idx=p.Decision_Frame_Delay+(1:cfg.Num_Symbols);
assert(numel(w.rx_symbol)>=max(idx),'Incomplete receiver data.');
r=p.Reference; y=w.rx_symbol(idx);
assert(all(isfinite(y)),'Nonfinite receiver symbols.');
gain=(r'*y)/(r'*r);
if p.Raw_Training_Enable, gain=1; end % raw snake is not the dummy QAM reference
assert(abs(gain)>eps,'Receiver signal is zero.');
z=y/gain; e=z-r;
raw=y/p.Linear_Gain;
refpower=mean(abs(r).^2);
evm=sqrt(mean(abs(e).^2)/refpower);
if isempty(cfg.DPD_LUT_Capture)
    dec=qamdemod(z,cfg.QAM_Order,'gray','UnitAveragePower',true);
else
    % Training IDs label ndgrid drives, not Gray hard decisions. Preserve the
    % soft RX samples for pairing; do not invent a training SER from qamdemod.
    dec=nan(size(p.Symbol_IDs));
end
results.Received_Symbols_Raw=y;
results.Received_Symbols=z;
results.Error_Vector=e;
results.Demodulated_IDs=dec;
results.Fitted_Complex_Gain=gain;
results.Symbol_Time=(0:cfg.Num_Symbols-1)'/cfg.Symbol_Rate;
m.EVM_Percent=100*evm;
m.EVM_dB=20*log10(max(evm,realmin));
m.Estimated_SNR_dB=-m.EVM_dB; % includes noise, distortion, ISI and residual jitter
m.RMS_Error_Vector=sqrt(mean(abs(e).^2));
m.Reference_RMS=sqrt(refpower);
m.Raw_EVM_Percent=100*sqrt(mean(abs(raw-r).^2)/refpower);
m.Symbol_Error_Rate=mean(dec~=p.Symbol_IDs);
m.Symbol_Errors=sum(dec~=p.Symbol_IDs);
if ~isempty(cfg.DPD_LUT_Capture), m.Symbol_Error_Rate=NaN; m.Symbol_Errors=NaN; end
if p.Raw_Training_Enable, m.EVM_Percent=NaN; m.EVM_dB=NaN; m.Estimated_SNR_dB=NaN; end
m.Num_Symbols=cfg.Num_Symbols;
m.Configured_TX_Jitter_fs=1e15*cfg.LO_RMS_Jitter*double(cfg.LO_Jitter_Enable);
stats=reshape(w.lo_statistics,3,[])';
m.Measured_TX_Jitter_fs=1e15*sqrt(mean(stats(:,1)));
m.Measured_RX_Jitter_fs=1e15*sqrt(mean(stats(:,2)));
m.Measured_Differential_Phase_RMS_rad=sqrt(mean(stats(:,3)));
m.TX_Target_EVM_dB=cfg.TX_Target_EVM_dB;
m.TX_Calibrated_EVM_dB=p.TX_Calibration.Achieved_EVM_dB;
m.TX_Nonlinearity_Beta=p.TX_Beta;
m.LO_Quadrature_Error_Deg=cfg.LO_Quadrature_Error_Deg*cfg.LO_Quadrature_Error_Enable;
m.LO_Differential_Phase_Error_Deg=cfg.LO_Differential_Phase_Error_Deg*cfg.LO_Quadrature_Error_Enable;
m.LO_Quadrature_Amplitude_Mismatch=cfg.LO_Quadrature_Amplitude_Mismatch*cfg.LO_Quadrature_Error_Enable;
phaseLegs=exp(1i*p.LO_Phase_Offsets);
legs=p.LO_Leg_Amplitudes.*phaseLegs;
ip=(legs(1)-legs(3))/2;
qp=(legs(4)-legs(2))/2;
m.LO_Image_to_Desired_Ratio=abs((ip-1i*qp)/(ip+1i*qp));
m.LO_Static_IQ_Theoretical_EVM_Percent=100*m.LO_Image_to_Desired_Ratio;
m.LO_Effective_Q_to_I_Gain=abs(qp)/abs(ip);
m.LO_Effective_Quadrature_Phase_Error_Deg=angle(1i*qp*conj(ip))*180/pi;
ipPhaseOnly=(phaseLegs(1)-phaseLegs(3))/2;
qpPhaseOnly=(phaseLegs(4)-phaseLegs(2))/2;
m.LO_Quadrature_Only_Theoretical_EVM_Percent=100*abs( ...
    (ipPhaseOnly-1i*qpPhaseOnly)/(ipPhaseOnly+1i*qpPhaseOnly));
[m.LO_Leg_Waveform_Max_Error,m.LO_Differential_Waveform_Max_Error] = ...
    verifyLOWaveforms(w,results.waveform_start_time,cfg,p);
m.Filter_Passband_Ripple_dB=p.Filter_Passband_Ripple_dB;
m.Filter_Stopband_Attenuation_dB=p.Filter_Stopband_Attenuation_dB;
m.RX_Equalizer_Enabled=p.RX_Equalizer.Enabled;
m.RX_Inband_Ripple_Before_dB=p.RX_Equalizer.Ripple_Before_dB;
m.RX_Inband_Ripple_After_dB=p.RX_Equalizer.Ripple_After_dB;
m.RX_Equalizer_Peak_Gain_dB=p.RX_Equalizer.Peak_Gain_dB;
m.RX_Equalizer_Boost_Limited=p.RX_Equalizer.Boost_Limited;
ci=round(w.dpd_ideal_i/p.LSB); cq=round(w.dpd_ideal_q/p.LSB);
m.I_Clipped_Samples=sum(ci<p.Min_Code | ci>p.Max_Code);
m.Q_Clipped_Samples=sum(cq<p.Min_Code | cq>p.Max_Code);
if cfg.Measure_DAC_Noise
    idealI=w.dpd_ideal_i; idealQ=w.dpd_ideal_q;
    if isfield(p.DPD,'Placement') && strcmp(p.DPD.Placement,'symbol_before_rrc')
        idealI=w.input_i; idealQ=w.input_q; % actual unquantized TX RRC output
    end
    ei=w.codes_i*p.LSB-idealI; eq=w.codes_q*p.LSB-idealQ;
    m.DAC_I_Error_RMS=sqrt(mean(ei.^2)); m.DAC_Q_Error_RMS=sqrt(mean(eq.^2));
    m.DAC_SQNR_dB=10*log10(mean(idealI.^2+idealQ.^2)/max(mean(ei.^2+eq.^2),realmin));
else
    m.DAC_I_Error_RMS=NaN; m.DAC_Q_Error_RMS=NaN; m.DAC_SQNR_dB=NaN;
end
m.Maximum_RF_Input=max(abs(w.rf_before_gm));
m.Maximum_RF_Output=max(abs(w.rf_output));
m.Diagnostics_Cover_Full_Record=results.waveform_num_frames.input_i==p.Num_Frames;
ds=reshape(w.dpd_statistics,16,[])';
m.DPD_Enabled=p.DPD.Enabled;
m.DPD_IQ_Enabled=p.DPD.IQ_Enable;
m.DPD_Nonlinearity_Enabled=p.DPD.Nonlinearity_Enable;
m.DPD_Drive_Power_Expansion_dB=10*log10(sum(ds(:,2))/max(sum(ds(:,1)),realmin));
m.DPD_Max_Actual_Gain=max(ds(:,4));
m.DPD_Limited_Samples=sum(ds(:,5));
m.DPD_DAC_I_Clipped_Full=sum(ds(:,6));
m.DPD_DAC_Q_Clipped_Full=sum(ds(:,7));
m.DPD_Max_Digital_Envelope=max(ds(:,8));
m.Digital_Code_Bits=cfg.DAC_Bits;
m.DPD_Output_Quantization_Error_RMS=sqrt(sum(ds(:,10))/sum(ds(:,3)));
m.DPD_Output_Quantization_SQNR_dB=10*log10(max(sum(ds(:,9)),realmin)/max(sum(ds(:,10)),realmin));
m.Input_Code_Quantization_Error_RMS=sqrt(sum(ds(:,11))/sum(ds(:,3)));
m.DPD_Modified_Codeword_Pairs=sum(ds(:,12));
m.Input_Code_I_Clipped_Full=sum(ds(:,13)); m.Input_Code_Q_Clipped_Full=sum(ds(:,14));
m.Invalid_Output_Codeword_Pairs=sum(ds(:,15));
m.Maximum_Absolute_Codeword=max(ds(:,16));
m.DPD_Algorithm=string(p.DPD.Algorithm);
m.DPD_Placement="sample_after_rrc";
if isfield(p.DPD,'Placement'), m.DPD_Placement=string(p.DPD.Placement); end
m.DPD_Modified_Symbols=0; m.DPD_Selected_Training_Points=0;
if isfield(p.DPD,'Placement') && strcmp(p.DPD.Placement,'symbol_before_rrc')
    m.DPD_Placement="symbol_before_rrc";
    % RRC overshoot is physical DAC clipping, even though the sample-format
    % stage has already saturated these words before the downstream DAC.
    m.DPD_DAC_I_Clipped_Full=m.Input_Code_I_Clipped_Full;
    m.DPD_DAC_Q_Clipped_Full=m.Input_Code_Q_Clipped_Full;
    if isfield(p.DPD,'Symbol_LUT_Indices')
        selected=p.DPD.Symbol_LUT_Indices(p.Symbol_IDs+1);
        m.DPD_Selected_Training_Points=numel(unique(selected));
        emitted=p.Source_Constellation(p.Symbol_IDs+1)*cfg.Input_Amplitude;
        m.DPD_Modified_Symbols=sum(abs(emitted-p.Reference*cfg.Input_Amplitude)>1e-12);
        m.DPD_Drive_Power_Expansion_dB=10*log10(sum(abs(emitted).^2)/sum(abs(p.Reference*cfg.Input_Amplitude).^2));
        m.DPD_Max_Actual_Gain=max(abs(emitted)./abs(p.Reference*cfg.Input_Amplitude));
    end
end
m.DPD_LUT_Points=0; m.DPD_LUT_I_Nodes=0; m.DPD_LUT_Q_Nodes=0;
m.DPD_LUT_Value_Bits=0; m.DPD_LUT_Fraction_Bits=0;
m.DPD_LUT_Packed_Payload_Bytes=0; m.DPD_LUT_Value_Clipped_Nodes=0;
m.DPD_LUT_Interpolation="none";
m.DPD_LUT_Node_Quantization_RMS_Code=0;
m.DPD_LUT_Training_Order=0; m.DPD_LUT_Storage="none"; m.DPD_LUT_Generation="none";
if isfield(p.DPD,'LUT')
    lut=p.DPD.LUT;
    m.DPD_LUT_Points=lut.Points; m.DPD_LUT_I_Nodes=lut.Size(1); m.DPD_LUT_Q_Nodes=lut.Size(2);
    m.DPD_LUT_Value_Bits=lut.Value_Bits; m.DPD_LUT_Fraction_Bits=lut.Fraction_Bits;
    m.DPD_LUT_Packed_Payload_Bytes=lut.Packed_Payload_Bytes;
    m.DPD_LUT_Value_Clipped_Nodes=lut.Value_Clipped_Nodes;
    m.DPD_LUT_Interpolation=string(lut.Interpolation);
    m.DPD_LUT_Node_Quantization_RMS_Code=lut.Node_Quantization_Error_RMS_Code;
    m.DPD_LUT_Training_Order=lut.Training_Order;
    m.DPD_LUT_Storage=string(lut.Storage); m.DPD_LUT_Generation=string(lut.Generation);
end
assert(m.Invalid_Output_Codeword_Pairs==0,'Digital output contains invalid N-bit codewords.');
assert(isequal(w.codes_i,round(w.dpd_i/p.LSB)) && isequal(w.codes_q,round(w.dpd_q/p.LSB)), ...
    'DAC input codewords differ from the quantized DPD output.');
results.metrics=m;
results.filters.TX_FIR=p.TX_FIR;
results.filters.RX_FIR=p.RX_FIR;
results.filters.RX_Equalizer_FIR=p.RX_Equalizer_FIR;
results.RX_Equalizer=p.RX_Equalizer;
results.filters.RRC=p.RRC;
results.filters.Fractional_FIR=p.Fractional_FIR;
results.filters.Frequency=p.Filter_Frequency;
results.filters.Response=p.Filter_Response;
results.timing.Samples_Per_Symbol=p.Samples_Per_Symbol;
results.timing.DAC_Samples_Per_Symbol=p.DAC_Samples_Per_Symbol;
results.timing.Decision_Frame_Delay=p.Decision_Frame_Delay;
results.timing.Decision_Index=p.Decision_Index;
results.timing.Total_Delay_DAC_Samples=p.Total_Delay;
results.TX_Beta=p.TX_Beta;
results.TX_Calibration=p.TX_Calibration;
results.DPD=p.DPD;
results.LO_Phase_Offsets_Deg=p.LO_Phase_Offsets*180/pi;
results.LO_Leg_Amplitudes=p.LO_Leg_Amplitudes;
results.TX_Jitter=w.lo_phase_error/(2*pi*cfg.LO_Frequency);
results.RX_Jitter=w.rx_phase_error/(2*pi*cfg.RX_LO_Frequency);
results.Model_Name=cfg.Model_Name;
results.MATLAB_Version=version;
end

function [legError,pairError]=verifyLOWaveforms(w,startTime,c,p)
% Check one RF frame using the actual logged jitter, phases and leg outputs.
tags={'lo_0','lo_90','lo_180','lo_270','lo_i','lo_q'};
N=p.Samples_Per_Symbol;
frame=round(startTime.lo_phase_error*c.Symbol_Rate);
t=(frame*N+(0:N-1)')/c.Sample_Rate;
theta=2*pi*c.LO_Frequency*t+w.lo_phase_error(1:N);
expected=cos(theta+p.LO_Phase_Offsets).*p.LO_Leg_Amplitudes;
actual=zeros(N,numel(tags));
for k=1:numel(tags)
    tag=tags{k};
    assert(round(startTime.(tag)*c.Symbol_Rate)==frame,'LO logs do not share an RF frame.');
    samples=w.(tag);
    actual(:,k)=samples(1:N);
end
legError=max(abs(actual(:,1:4)-expected),[],'all');
pairs=[actual(:,1)-actual(:,3),actual(:,4)-actual(:,2)]/2;
pairError=max(abs(actual(:,5:6)-pairs),[],'all');
assert(max(legError,pairError)<1e-9*max(p.LO_Leg_Amplitudes), ...
    'rfdac:LOVerification','SLX LO legs or differential pairs differ from the configured LO.');
end

function x=unframe(d)
v=d.signals.values;
if ndims(v)>=3
    % Matrix frames: [samples, channels=1, frames].
    x=v(:);
elseif size(v,1)==numel(d.time) && size(v,2)>1
    % Vector frames: [frames, samples].
    x=reshape(v.',[],1);
else
    x=v(:);
end
end
