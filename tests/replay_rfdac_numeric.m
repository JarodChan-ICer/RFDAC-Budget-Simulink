function result=replay_rfdac_numeric(c,original)
% Independent numerical passband replay; no Simulink runtime is loaded.
% Uses the exact saved causal filters/timing, new source symbols, and stored
% finite absolute training words (rebuilt when a case changes DPD configuration).
L=original.timing.DAC_Samples_Per_Symbol;
hold=round(c.Sample_Rate/c.DAC_Sample_Rate);
physicalBeta=c.TX_Nonlinearity_Beta;
if isempty(physicalBeta), physicalBeta=original.TX_Beta; end
if ~c.TX_Nonlinearity_Enable, physicalBeta=0; end
frames=c.Num_Symbols+original.timing.Decision_Frame_Delay+2;
stream=RandStream('mt19937ar','Seed',c.Random_Seed);
ids=randi(stream,c.QAM_Order,c.Num_Symbols,1)-1;
r=original.Reference_Constellation(ids+1);
d=original.DPD;
d.Enabled=logical(c.DPD_Enable);
d.IQ_Enable=d.Enabled && c.DPD_IQ_Enable;
d.Nonlinearity_Enable=d.Enabled && c.DPD_Nonlinearity_Enable;
d.Algorithm=c.DPD_Algorithm;
phase=original.LO_Phase_Offsets_Deg*pi/180;
legAmplitude=ones(1,4);
if isfield(original,'LO_Leg_Amplitudes'), legAmplitude=original.LO_Leg_Amplitudes; end
if ~isempty(c.DPD_Quadrature_Estimate_Deg) && ...
        ~(strcmp(d.Algorithm,'lut') && strcmp(c.DPD_LUT_Training_Mode,'link'))
    physicalQ=original.cfg.LO_Quadrature_Error_Enable*original.cfg.LO_Quadrature_Error_Deg;
    estimatePhase=phase+[0 1 0 1]*(c.DPD_Quadrature_Estimate_Deg-physicalQ)*pi/180;
    phasors=legAmplitude.*exp(1i*estimatePhase);
    ip=(phasors(1)-phasors(3))/2;
    qp=(phasors(4)-phasors(2))/2;
    d.Alpha=(ip+1i*qp)/2; d.Image=(ip-1i*qp)/2;
    d.Determinant=abs(d.Alpha)^2-abs(d.Image)^2;
end
if strcmp(d.Algorithm,'lut')
    cached=intersect(fieldnames(d),{'Symbol_Input_Codes','Symbol_LUT_Indices','Idle_LUT_Index', ...
        'Symbol_Targets','Symbol_Unique_Drives'});
    if ~isempty(cached), d=rmfield(d,cached); end
    d.LUT=rfdac_build_dpd_lut(c,d);
end
jstream=RandStream('mt19937ar','Seed',c.Random_Seed+1);
a=exp(-2*pi*c.Jitter_Bandwidth/c.Sample_Rate);
jstate=a*randn(jstream);
assert(strcmp(c.RX_LO_Mode,'ideal'),'Numeric audit currently supports the original ideal RX LO.');
index=original.timing.Total_Delay_DAC_Samples+1+(0:c.Num_Symbols-1)*L;
% Bounded-memory overlap-add convolution, also on the original full record.
blockFrames=64; maxRF=blockFrames*L*hold;
nfft=2^nextpow2(maxRF+max(numel(original.filters.TX_FIR),numel(original.filters.RX_FIR))-1);
txFFT=fft(original.filters.TX_FIR(:),nfft);
rxFFT=fft(original.filters.RX_FIR(:),nfft);
txTail=complex(zeros(numel(original.filters.TX_FIR)-1,1));
rxTail=complex(zeros(numel(original.filters.RX_FIR)-1,1));
legacyPulse=isfield(original.filters,'RRC');
postMapPulse=isfield(original.filters,'TX_Pulse_FIR');
if postMapPulse
    txPulseState=complex(zeros(numel(original.filters.TX_Pulse_FIR)-1,1));
    rxPulseState=complex(zeros(numel(original.filters.RX_Pulse_FIR)-1,1));
end
if legacyPulse
    rrcState=complex(zeros(numel(original.filters.RRC)-1,1));
    matchState=rrcState;
end
fracState=complex(zeros(numel(original.filters.Fractional_FIR)-1,1));
eqB=1;
if isfield(original.filters,'RX_Equalizer_FIR'), eqB=original.filters.RX_Equalizer_FIR; end
eqState=complex(zeros(numel(eqB)-1,1));
y=complex(zeros(c.Num_Symbols,1)); stats=zeros(16,1); untrained=0;
for first=1:blockFrames:frames
    nf=min(blockFrames,frames-first+1);
    last=min(first+nf-1,c.Num_Symbols);
    if legacyPulse
        x=complex(zeros(nf*L,1));
        if last>=first, x(1:L:(last-first+1)*L)=r(first:last)*sqrt(L)*c.Input_Amplitude; end
        [x,rrcState]=filter(original.filters.RRC,1,x,rrcState);
    else
        frameSymbols=complex(zeros(nf,1));
        if last>=first, frameSymbols(1:last-first+1)=r(first:last); end
        x=repelem(frameSymbols*c.Input_Amplitude,L);
    end
    [x,~,~,st]=rfdac_dpd_codewords(x,d);
    if strcmp(d.Algorithm,'lut') && (d.IQ_Enable || d.Nonlinearity_Enable)
        words=complex(double(d.LUT.Output_I(:)),double(d.LUT.Output_Q(:)));
        untrained=untrained+sum(~ismember(x/d.LSB,words));
    end
    stats=stats+st;
    if first==1, maxima=st([4 8 16]); else, maxima=max(maxima,st([4 8 16])); end
    if postMapPulse
        x=x.*repmat(original.filters.TX_Pulse_Mask(:),nf,1);
        [x,txPulseState]=filter(original.filters.TX_Pulse_FIR,1,x,txPulseState);
        codes=complex(min(max(round(real(x)/d.LSB),d.Min_Code),d.Max_Code), ...
            min(max(round(imag(x)/d.LSB),d.Min_Code),d.Max_Code));
        x=codes*d.LSB;
    end
    [x,txTail]=fft_block(repelem(x,hold),txFFT,txTail,nfft);
    N=numel(x); t=((first-1)*L*hold+(0:N-1)')/c.Sample_Rate;
    j=randn(jstream,N,1);
    if strcmp(c.Jitter_Mode,'bandlimited')
        [j,jstate]=filter(sqrt(1-a*a),[1 -a],j,jstate);
    end
    theta=2*pi*c.LO_Frequency*t+2*pi*c.LO_Frequency*c.LO_RMS_Jitter*c.LO_Jitter_Enable*j;
    loI=(legAmplitude(1)*cos(theta+phase(1))-legAmplitude(3)*cos(theta+phase(3)))/2;
    loQ=(legAmplitude(4)*cos(theta+phase(4))-legAmplitude(2)*cos(theta+phase(2)))/2;
    rf=real(x).*loI-imag(x).*loQ;
    if physicalBeta>0
        k=sqrt(physicalBeta); rf=atan(k*rf)/k;
    end
    down=2*rf.*exp(-1i*(2*pi*c.RX_LO_Frequency*t+c.RX_LO_Phase));
    [bb,rxTail]=fft_block(down,rxFFT,rxTail,nfft);
    bb=bb(1:hold:end);
    [bb,eqState]=filter(eqB,1,bb,eqState);
    if legacyPulse, [bb,matchState]=filter(original.filters.RRC/sqrt(L),1,bb,matchState); end
    if postMapPulse, [bb,rxPulseState]=filter(original.filters.RX_Pulse_FIR,1,bb,rxPulseState); end
    [bb,fracState]=filter(original.filters.Fractional_FIR,1,bb,fracState);
    firstDAC=(first-1)*L+1;
    selected=find(index>=firstDAC & index<firstDAC+numel(bb));
    y(selected)=bb(index(selected)-firstDAC+1);
end
stats([4 8 16])=maxima;
g=(r'*y)/(r'*r); z=y/g;
evm=norm(z-r)/norm(r);
% Nearest square-QAM points, with independently computed decisions.
levels=unique(real(original.Reference_Constellation));
[~,ix]=min(abs(real(z)-levels.'),[],2);
[~,iy]=min(abs(imag(z)-levels.'),[],2);
decided=complex(levels(ix),levels(iy));
m.EVM_Percent=100*evm; m.Estimated_SNR_dB=-20*log10(evm);
m.Symbol_Errors=sum(abs(decided-r)>1e-10);
m.Symbol_Error_Rate=m.Symbol_Errors/c.Num_Symbols;
m.DPD_Drive_Power_Expansion_dB=10*log10(stats(2)/stats(1));
m.DPD_DAC_I_Clipped_Full=stats(6); m.DPD_DAC_Q_Clipped_Full=stats(7);
m.DPD_Limited_Samples=stats(5); m.Invalid_Output_Codeword_Pairs=stats(15);
m.DPD_Untrained_Output_Samples=untrained; assert(untrained==0); m.DPD_LUT_Value_Clipped_Nodes=0;
if strcmp(d.Algorithm,'lut'), m.DPD_LUT_Value_Clipped_Nodes=d.LUT.Value_Clipped_Nodes; end
result.metrics=m; result.TX_Beta=physicalBeta; result.DPD=d;
result.Fitted_Complex_Gain=g;
result.Reference_Symbols=r; result.Received_Symbols=z;
fprintf('Numeric RF replay: EVM %.8f%% | MER %.6f dB | SER %.7g\n', ...
    m.EVM_Percent,m.Estimated_SNR_dB,m.Symbol_Error_Rate);
end

function [y,tail]=fft_block(x,B,tail,nfft)
n=numel(x); m=numel(tail);
full=ifft(fft(x,nfft).*B);
full(1:m)=full(1:m)+tail;
y=full(1:n); tail=full(n+1:n+m);
end

