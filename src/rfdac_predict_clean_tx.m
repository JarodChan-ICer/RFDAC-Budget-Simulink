function prediction=rfdac_predict_clean_tx(beta,meta)
% Predict whole clean-TX MER from estimated beta and public linear-path data.
% Same TX RRC/DAC/ZOH/LPFs/RX RRC timing as calibration; no true beta/target.
validateattributes(beta,{'numeric'},{'scalar','real','finite','nonnegative'});
r=meta.Reference_Symbols(:);
if isfield(meta,'Min_Code'), lo=meta.Min_Code; hi=meta.Max_Code;
else, lo=meta.DAC_Min_Code; hi=meta.DAC_Max_Code; end
L=meta.DAC_Samples_Per_Symbol;
u=complex(zeros(meta.Num_Frames*L,1));
u(1:L:numel(r)*L)=r*sqrt(L)*meta.Reference_Amplitude;
u=filter(meta.TX_RRC,1,u);
drive=meta.DAC_LSB*complex(min(max(round(real(u)/meta.DAC_LSB),lo),hi), ...
    min(max(round(imag(u)/meta.DAC_LSB),lo),hi));
filtered=fftfilt(meta.TX_FIR,repelem(drive,meta.DAC_Hold)); clear drive u;
carrier=exp(1i*(2*pi*meta.LO_Frequency/meta.RF_Sample_Rate)*(0:numel(filtered)-1)');
rf=real(filtered.*carrier); clear filtered;
if beta>0, k=sqrt(beta); rf=atan(k*rf)/k; end
received=fftfilt(meta.RX_FIR,2*rf.*conj(carrier)); clear rf carrier;
received=received(1:meta.DAC_Hold:end);
if isfield(meta,'RX_Equalizer_FIR'), received=filter(meta.RX_Equalizer_FIR,1,received); end
received=filter(meta.RX_RRC,1,received);
received=filter(meta.Fractional_FIR,1,received);
received=received(meta.Total_Delay+1:L:meta.Total_Delay+1+(numel(r)-1)*L);
gain=(r'*received)/(r'*r);
normalized=received/gain; error=normalized-r;
evm=norm(error)/norm(r);
prediction.EVM_Percent=100*evm;
prediction.EVM_dB=20*log10(max(evm,realmin));
prediction.TX_SNR_dB=-prediction.EVM_dB;
prediction.MER_dB=-prediction.EVM_dB;
prediction.Beta_Estimate=beta;
prediction.Num_Symbols=numel(r);
prediction.Fitted_Complex_Gain=gain;
prediction.Received_Symbols=normalized;
prediction.Error_Vector=error;
prediction.Description='Whole clean-TX MER including RRC, DAC and LPFs; ideal IQ/jitter, no AWGN.';
end
