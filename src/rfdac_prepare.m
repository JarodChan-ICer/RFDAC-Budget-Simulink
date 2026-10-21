function [p,cfg] = rfdac_prepare(cfg)
%RFDAC_PREPARE Validate configuration and prepare reproducible frame stimuli.
required = {'Simulink','Signal_Toolbox','Communication_Toolbox','Signal_Blocks'};
defaults=init_rfdac_model();
newfields={'TX_Nonlinearity_Enable','TX_Target_EVM_dB','TX_Nonlinearity_Beta', ...
    'TX_EVM_Fit_Tolerance_dB','LO_Quadrature_Error_Enable', ...
    'LO_Quadrature_Error_Deg','LO_Phase_Errors_Deg','Waveform_Log_Frames', ...
    'DPD_Enable','DPD_IQ_Enable','DPD_Nonlinearity_Enable','DPD_TX_Beta_Estimate', ...
    'DPD_Quadrature_Estimate_Deg','DPD_Phase_Errors_Estimate_Deg','DPD_Max_Gain', ...
    'Plot_Constellation','Plot_DPD_Comparison','Plot_LPF_Response', ...
    'Plot_Waveforms','Plot_Spectra','Plot_Diagnostics', ...
    'DPD_Algorithm','DPD_LUT_Size_Mode','DPD_LUT_Points','DPD_LUT_Address_Bits', ...
    'DPD_LUT_Points_Per_QAM_Symbol','DPD_LUT_Value_Bits','DPD_LUT_Fraction_Bits', ...
    'DPD_LUT_Interpolation','DPD_LUT_Max_Penalty_dB'};
for k=1:numel(newfields)
    if ~isfield(cfg,newfields{k}), cfg.(newfields{k})=defaults.(newfields{k}); end
end
for k=1:numel(required)
    assert(license('test',required{k}), 'RF DAC requires license: %s',required{k});
end
assert(ismember(cfg.QAM_Order,[16 64 256 1024 4096]),'Unsupported QAM order.');
positive = {'LO_Frequency','Sample_Rate','DAC_Sample_Rate','Symbol_Rate', ...
    'DAC_Full_Scale','Input_Amplitude'};
validateattributes(cfg.RRC_Rolloff,{'numeric'},{'scalar','>',0,'<=',1});
validateattributes(cfg.RRC_Span,{'numeric'},{'scalar','integer','even','>=',4});
if isempty(cfg.Symbol_Rate), cfg.Symbol_Rate=cfg.Baseband_Frequency/(1+cfg.RRC_Rolloff); end
assert(abs(cfg.Symbol_Rate*(1+cfg.RRC_Rolloff)-cfg.Baseband_Frequency)<1, ...
    'Baseband_Frequency is total RRC bandwidth: set it to Symbol_Rate*(1+RRC_Rolloff).');
for k=1:numel(positive)
    validateattributes(cfg.(positive{k}),{'numeric'},{'scalar','real','finite','positive'});
end
validateattributes(cfg.Num_Symbols,{'numeric'},{'scalar','integer','>=',16});
validateattributes(cfg.DAC_Bits,{'numeric'},{'scalar','integer','>=',2,'<=',24});
validateattributes(cfg.Random_Seed,{'numeric'},{'scalar','integer','nonnegative','<',2^32-2});
validateattributes(cfg.LO_RMS_Jitter,{'numeric'},{'scalar','finite','nonnegative'});
validateattributes(cfg.TX_Target_EVM_dB,{'numeric'},{'scalar','real','finite','<',0});
validateattributes(cfg.TX_EVM_Fit_Tolerance_dB,{'numeric'},{'scalar','positive','finite'});
validateattributes(cfg.LO_Quadrature_Error_Deg,{'numeric'},{'scalar','real','finite'});
validateattributes(cfg.LO_Phase_Errors_Deg,{'numeric'},{'vector','numel',4,'real','finite'});
validateattributes(cfg.Waveform_Log_Frames,{'numeric'},{'scalar','positive'});
assert(isinf(cfg.Waveform_Log_Frames) || cfg.Waveform_Log_Frames==floor(cfg.Waveform_Log_Frames), ...
    'Waveform_Log_Frames must be a positive integer or Inf.');
if isempty(cfg.RX_LO_Frequency), cfg.RX_LO_Frequency=cfg.LO_Frequency; end
if isempty(cfg.RX_LO_RMS_Jitter), cfg.RX_LO_RMS_Jitter=cfg.LO_RMS_Jitter; end
validateattributes(cfg.RX_LO_Frequency,{'numeric'},{'scalar','finite','positive'});
validateattributes(cfg.RX_LO_RMS_Jitter,{'numeric'},{'scalar','finite','nonnegative'});
validateattributes(cfg.Baseband_Frequency,{'numeric'},{'scalar','finite','real'});
assert(ismember(cfg.Jitter_Mode,{'bandlimited','white'}),'Unknown jitter mode.');
assert(ismember(cfg.RX_LO_Mode,{'ideal','shared','independent'}),'Unknown RX LO mode.');
[cfg,p.Sampling]=rfdac_resolve_sampling(cfg);
if strcmp(cfg.Jitter_Mode,'bandlimited')
    validateattributes(cfg.Jitter_Bandwidth,{'numeric'},{'scalar','finite','positive','<',cfg.Sample_Rate/2});
end
p.Samples_Per_Symbol=round(cfg.Sample_Rate/cfg.Symbol_Rate);
assert(abs(p.Samples_Per_Symbol-cfg.Sample_Rate/cfg.Symbol_Rate)<1e-8, ...
    'Sample_Rate/Symbol_Rate must be an integer.');
if ~isempty(cfg.Oversampling_Ratio)
    assert(cfg.Oversampling_Ratio==p.Samples_Per_Symbol, ...
        'Oversampling_Ratio must equal Sample_Rate/Symbol_Rate (or be []).');
end
cfg.Oversampling_Ratio=p.Samples_Per_Symbol;
p.DAC_Hold=round(cfg.Sample_Rate/cfg.DAC_Sample_Rate);
assert(p.DAC_Hold>=1 && abs(p.DAC_Hold-cfg.Sample_Rate/cfg.DAC_Sample_Rate)<1e-8, ...
    'Sample_Rate/DAC_Sample_Rate must be a positive integer.');
assert(mod(p.Samples_Per_Symbol,p.DAC_Hold)==0,'A symbol must contain whole DAC updates.');
assert(cfg.Baseband_Frequency<cfg.DAC_Sample_Rate,'Signal exceeds DAC Nyquist frequency.');
p.TX_FIR=make_fir(cfg.LPF_Order,cfg.LPF_Cutoff,cfg.Sample_Rate);
p.RX_FIR=make_fir(cfg.RX_LPF_Order,cfg.RX_LPF_Cutoff,cfg.Sample_Rate);
assert(cfg.LPF_Transition_Bandwidth>0 && ...
    cfg.LPF_Cutoff-cfg.LPF_Transition_Bandwidth/2>=cfg.Baseband_Frequency/2, ...
    'Requested passband must include half the TOTAL baseband bandwidth.');
p.DAC_Samples_Per_Symbol=p.Samples_Per_Symbol/p.DAC_Hold;
assert(p.DAC_Samples_Per_Symbol>=4,'At least four DAC samples per symbol are required.');
p.RRC=rcosdesign(cfg.RRC_Rolloff,cfg.RRC_Span,p.DAC_Samples_Per_Symbol,'sqrt');
p.TX_Impulse=[sqrt(p.DAC_Samples_Per_Symbol)*cfg.Input_Amplitude; zeros(p.DAC_Samples_Per_Symbol-1,1)];
p.RX_RRC=p.RRC/sqrt(p.DAC_Samples_Per_Symbol);
p.Uncorrected_Delay=cfg.RRC_Span*p.DAC_Samples_Per_Symbol+ ...
    (cfg.LPF_Order+cfg.RX_LPF_Order)/(2*p.DAC_Hold)+(p.DAC_Hold-1)/(2*p.DAC_Hold);
% Cubic Lagrange fractional delay adds 1..2 DAC samples for integer timing.
target=ceil(p.Uncorrected_Delay)+1;
frac=target-p.Uncorrected_Delay;
p.Fractional_FIR=ones(1,4);
for k=0:3
    others=setdiff(0:3,k);
    p.Fractional_FIR(k+1)=prod((frac-others)./(k-others));
end
p.Total_Delay=target;
p.Decision_Frame_Delay=floor(target/p.DAC_Samples_Per_Symbol);
p.Decision_Index=mod(target,p.DAC_Samples_Per_Symbol)+1;
p.Num_Frames=cfg.Num_Symbols+p.Decision_Frame_Delay+2;
p.Frame_Period=1/cfg.Symbol_Rate;
p.Stop_Time=(p.Num_Frames-1)*p.Frame_Period;
p.LSB=2*cfg.DAC_Full_Scale/2^cfg.DAC_Bits;
p.Min_Code=-2^(cfg.DAC_Bits-1);
p.Max_Code=2^(cfg.DAC_Bits-1)-1;
p.DAC_Hold_Indices=floor((0:p.Samples_Per_Symbol-1)'/p.DAC_Hold)+1;
p.RX_Decimation_Indices=(1:p.DAC_Hold:p.Samples_Per_Symbol)';
p.Constellation=qammod((0:cfg.QAM_Order-1)',cfg.QAM_Order,'gray','UnitAveragePower',true);
stream=RandStream('mt19937ar','Seed',cfg.Random_Seed);
p.Symbol_IDs=randi(stream,cfg.QAM_Order,cfg.Num_Symbols,1)-1;
p.Reference=p.Constellation(p.Symbol_IDs+1);
p.Num_RF_Samples=p.Samples_Per_Symbol*p.Num_Frames;
p.Symbol_Data.time=(0:p.Num_Frames-1)'*p.Frame_Period;
p.Symbol_Data.signals.values=[p.Symbol_IDs; -ones(p.Num_Frames-cfg.Num_Symbols,1)];
p.Symbol_Data.signals.dimensions=1;
p.Linear_Gain=cfg.Input_Amplitude;
p.LO_Phase_Offsets=pi/180*([0 90 180 270]+double(cfg.LO_Quadrature_Error_Enable)* ...
    ([0 cfg.LO_Quadrature_Error_Deg 0 cfg.LO_Quadrature_Error_Deg]+reshape(cfg.LO_Phase_Errors_Deg,1,4)));
if cfg.TX_Nonlinearity_Enable
    if isempty(cfg.TX_Nonlinearity_Beta)
        [p.TX_Beta,p.TX_Calibration]=rfdac_fit_tx_evm(cfg,p);
    else
        validateattributes(cfg.TX_Nonlinearity_Beta,{'numeric'},{'scalar','finite','nonnegative'});
        p.TX_Beta=cfg.TX_Nonlinearity_Beta;
        p.TX_Calibration=struct('Method','manual beta','Target_EVM_dB',cfg.TX_Target_EVM_dB, ...
            'Achieved_EVM_dB',NaN,'Linear_Floor_EVM_dB',NaN,'Beta',p.TX_Beta);
    end
else
    p.TX_Beta=0;
    p.TX_Calibration=struct('Method','disabled','Target_EVM_dB',cfg.TX_Target_EVM_dB, ...
        'Achieved_EVM_dB',NaN,'Linear_Floor_EVM_dB',NaN,'Beta',0);
end
p.TX_K=max(sqrt(p.TX_Beta),eps);
p.DPD=rfdac_prepare_dpd(cfg,p);
p.Filter_Frequency=linspace(0,cfg.Sample_Rate/2,32769)';
p.Filter_Response=freqz(p.TX_FIR,1,p.Filter_Frequency,cfg.Sample_Rate);
pb=p.Filter_Frequency<=cfg.LPF_Cutoff-cfg.LPF_Transition_Bandwidth/2;
sb=p.Filter_Frequency>=cfg.LPF_Cutoff+cfg.LPF_Transition_Bandwidth/2;
p.Filter_Passband_Ripple_dB=max(20*log10(abs(p.Filter_Response(pb))))-min(20*log10(abs(p.Filter_Response(pb))));
p.Filter_Stopband_Attenuation_dB=-max(20*log10(max(abs(p.Filter_Response(sb)),eps)));
end

function b=make_fir(order,fc,fs)
validateattributes(order,{'numeric'},{'scalar','integer','positive','even'});
assert(fc>0 && fc<fs/2,'FIR cutoff outside Nyquist interval.');
b=fir1(order,fc/(fs/2),'low',blackman(order+1),'scale');
end
