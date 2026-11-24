function [b,info]=rfdac_fit_rx_equalizer(c,p)
%RFDAC_FIT_RX_EQUALIZER Bounded, model-fitted linear-phase RX FIR at DAC rate.
% Fit the actual TX/RX LPF and DAC-hold magnitude, excluding the intentional
% RRC response. Refit on preparation, never from payload symbols or TX errors.
validateattributes(c.RX_Equalizer_Enable,{'logical','numeric'},{'scalar','binary'});
validateattributes(c.RX_Equalizer_Order,{'numeric'},{'scalar','integer','even','>=',2,'<=',2048});
validateattributes(c.RX_Equalizer_Max_Boost_dB,{'numeric'},{'scalar','real','finite','>',0,'<=',30});
validateattributes(c.RX_Equalizer_Regularization,{'numeric'},{'scalar','real','finite','positive'});
fs=c.DAC_Sample_Rate; edge=c.Baseband_Frequency/2;
assert(edge>0 && edge<fs/2,'rfdac:EqualizerBandwidth','Equalizer band must lie inside DAC Nyquist.');
persistent cachedKey cachedB cachedInfo
key={logical(c.RX_Equalizer_Enable),c.RX_Equalizer_Order,c.RX_Equalizer_Max_Boost_dB, ...
    c.RX_Equalizer_Regularization,fs,c.Sample_Rate,edge,p.TX_FIR,p.RX_FIR,p.DAC_Hold};
if isequal(key,cachedKey), b=cachedB; info=cachedInfo; return; end

% The LPFs run at RF rate. Evaluate them at the same physical frequencies
% as the DAC-rate equalizer; do not reinterpret their coefficients at DAC Fs.
f=unique([linspace(0,fs/2,4097)';linspace(0,edge,1025)']);
path=freqz(p.TX_FIR,1,f,c.Sample_Rate).*freqz(p.RX_FIR,1,f,c.Sample_Rate).* ...
    freqz(ones(1,p.DAC_Hold)/p.DAC_Hold,1,f,c.Sample_Rate);
path=path/path(1); mag=abs(path); band=f<=edge;
limit=10^(c.RX_Equalizer_Max_Boost_dB/20);
limited=any(mag(band)<1/limit);
if c.RX_Equalizer_Enable
    n=c.RX_Equalizer_Order; half=n/2;
    target=ones(size(f));
    target(band)=min(1./max(mag(band),eps),limit);
    % Return smoothly to unity outside the occupied band. Never invert the
    % LPF stopband, where the information is lost and noise would be boosted.
    stop=min(fs/2,edge+max(edge/2,4*fs/n));
    transition=f>edge & f<stop;
    edgeGain=target(find(band,1,'last'));
    target(transition)=1+(edgeGain-1)*.5.*(1+cos(pi*(f(transition)-edge)/(stop-edge)));
    A=cos((2*pi*f/fs)*(0:half)); A(:,2:end)=2*A(:,2:end);
    weight=ones(size(f)); weight(band)=100;
    penalty=diag([1 2*ones(1,half)]);
    q=(A'*(weight.*A)+c.RX_Equalizer_Regularization*sum(weight)*penalty)\ ...
        (A'*(weight.*target));
    b=[flipud(q(2:end));q(1);q(2:end)].';
    b=b/sum(b); % retain unity DC gain; demodulator still fits scalar phase/gain
    % Enforce the configured ceiling on the realized filter, not just target.
    % Convexly blend toward a pure delay; this preserves symmetry and DC.
    checkF=linspace(0,fs/2,32769)';
    peak=max(abs(freqz(b,1,checkF,fs)));
    if peak>limit
        limited=true;
        mix=(limit-1)/(peak-1);
        identity=zeros(size(b)); identity(half+1)=1;
        b=mix*b+(1-mix)*identity;
    end
    delay=half;
else
    b=1; delay=0;
end
response=freqz(b,1,f,fs);
combined=path.*response;
before=20*log10(max(abs(path(band)),realmin));
after=20*log10(max(abs(combined(band)),realmin));
info=struct('Enabled',logical(c.RX_Equalizer_Enable),'Method', ...
    'Regularized symmetric FIR fit to nominal TX/RX LPFs and DAC hold', ...
    'Sample_Rate_Hz',fs,'Bandwidth_Hz',edge,'Order',numel(b)-1, ...
    'Delay_DAC_Samples',delay,'Max_Boost_dB',c.RX_Equalizer_Max_Boost_dB, ...
    'Frequency_Hz',f,'Path_Response',path,'Response',response, ...
    'Combined_Response',combined,'Ripple_Before_dB',max(before)-min(before), ...
    'Ripple_After_dB',max(after)-min(after), ...
    'Peak_Gain_dB',20*log10(max(abs(freqz(b,1,linspace(0,fs/2,32769)',fs)))), ...
    'Required_Boost_dB',-min(before), ...
    'Boost_Limited',logical(c.RX_Equalizer_Enable) && limited);
cachedKey=key; cachedB=b; cachedInfo=info;
end
