function [beta,info]=rfdac_fit_tx_evm(c,p)
% Fit a monotonic RF atan compressor against WHOLE clean-TX EVM.
% Uses the identical causal DAC/FIR/RRC/receiver math as the SLX. Jitter and
% quadrature errors are deliberately absent. Full reference record is used.
persistent cacheKey cacheBeta cacheInfo
fields={'LO_Frequency','Sample_Rate','DAC_Sample_Rate','Symbol_Rate','RRC_Rolloff', ...
    'RRC_Span','QAM_Order','DAC_Bits','DAC_Full_Scale','Input_Amplitude','Num_Symbols', ...
    'LPF_Cutoff','LPF_Order','RX_LPF_Cutoff','RX_LPF_Order','Random_Seed', ...
    'TX_Target_EVM_dB','TX_EVM_Fit_Tolerance_dB','RX_Equalizer_Enable', ...
    'RX_Equalizer_Order','RX_Equalizer_Max_Boost_dB','RX_Equalizer_Regularization'};
key=cellfun(@(f)c.(f),fields,'UniformOutput',false);
if isequal(key,cacheKey), beta=cacheBeta; info=cacheInfo; return; end
fprintf('Fitting clean TX EVM to %.3f dB using %d symbols...\n',c.TX_Target_EVM_dB,c.Num_Symbols);
L=p.DAC_Samples_Per_Symbol;
stim=complex(zeros(p.Num_Frames*L,1));
stim(1:L:c.Num_Symbols*L)=p.Reference*sqrt(L)*c.Input_Amplitude;
bb=filter(p.RRC,1,stim); clear stim;
bb=p.LSB*(min(max(round(real(bb)/p.LSB),p.Min_Code),p.Max_Code)+ ...
    1i*min(max(round(imag(bb)/p.LSB),p.Min_Code),p.Max_Code));
bb=repelem(bb,p.DAC_Hold);
filtered=fftfilt(p.TX_FIR,bb); clear bb;
carrier=exp(1i*(2*pi*c.LO_Frequency/c.Sample_Rate)*(0:p.Num_RF_Samples-1)');
rf=real(filtered.*carrier); clear filtered;
floorEvm=measure(0);
target=10^(c.TX_Target_EVM_dB/20);
if target<floorEvm*10^(-c.TX_EVM_Fit_Tolerance_dB/20)
    error('rfdac:TargetBelowFloor', ...
        'Requested TX EVM %.3f dB is below the DAC/filter floor %.3f dB. Improve the linear chain first.', ...
        c.TX_Target_EVM_dB,20*log10(floorEvm));
end
if abs(20*log10(floorEvm)-c.TX_Target_EVM_dB)<=c.TX_EVM_Fit_Tolerance_dB
    beta=0;
else
    upper=1/max(max(abs(rf))^2,eps);
    while measure(upper)<target
        upper=4*upper;
        assert(upper<1e8,'Target EVM is unreachable for the selected atan model.');
    end
    beta=fzero(@(b)measure(b)-target,[0 upper],optimset('TolX',1e-9,'Display','off'));
end
achieved=20*log10(measure(beta));
assert(abs(achieved-c.TX_Target_EVM_dB)<=c.TX_EVM_Fit_Tolerance_dB,'TX EVM fit failed tolerance.');
info=struct('Method','RF atan soft compression, full clean-TX calibration', ...
    'Target_EVM_dB',c.TX_Target_EVM_dB,'Achieved_EVM_dB',achieved, ...
    'Linear_Floor_EVM_dB',20*log10(floorEvm),'Beta',beta, ...
    'Num_Calibration_Symbols',c.Num_Symbols);
cacheKey=key; cacheBeta=beta; cacheInfo=info;
fprintf('TX fit: beta %.9g V^-2, clean EVM %.6f dB; linear floor %.3f dB.\n',beta,achieved,info.Linear_Floor_EVM_dB);

    function evm=measure(b)
        if b==0, v=rf; else, k=sqrt(b); v=atan(k*rf)/k; end
        down=2*v.*conj(carrier); clear v;
        y=fftfilt(p.RX_FIR,down); clear down;
        y=y(1:p.DAC_Hold:end);
        y=filter(p.RX_Equalizer_FIR,1,y);
        y=filter(p.RX_RRC,1,y);
        y=filter(p.Fractional_FIR,1,y);
        y=y(p.Total_Delay+1:L:p.Total_Delay+1+(c.Num_Symbols-1)*L);
        r=p.Reference; g=(r'*y)/(r'*r);
        evm=sqrt(mean(abs(y/g-r).^2)/mean(abs(r).^2));
    end
end
