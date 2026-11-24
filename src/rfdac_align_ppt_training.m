function [observed,meta]=rfdac_align_ppt_training(y,drive,order,dwell,prefix,repeats,guard)
% Frame and phase alignment use only known transmitted pilots and RX samples.
assert(prefix>=2*guard+16,'rfdac:TrainingZeroGuard', ...
    'Training zero guard is too short for TX/RX filter settling.');
y=y(:); drive=drive(:); n=numel(drive);
snake=repelem(drive(order),dwell);
frame=[complex(zeros(prefix,1));snake;complex(zeros(prefix,1))];
frameLength=numel(frame);
threshold=max(abs(drive))*1e-3;
activity=find(abs(y)>threshold,1);
assert(~isempty(activity) && activity>guard,'rfdac:TrainingFrame','Leading zero guard was not observed.');
% Correlation resolves the filter-smeared zero boundary to one DAC update.
nfft=2^nextpow2(numel(y)+frameLength-1);
correlation=ifft(fft(y,nfft).*conj(fft(frame,nfft)));
maxlag=min(prefix+2*guard,numel(y)-frameLength);
assert(maxlag>=0,'rfdac:TrainingFrame','Capture does not contain one complete snake frame.');
[~,best]=max(abs(correlation(1:maxlag+1))); lag=best-1;
assert(lag+(repeats-1)*frameLength+prefix+n*dwell<=numel(y), ...
    'rfdac:TrainingFrame','Capture ends before the last complete snake.');
middle=max(1,floor(dwell*.3)+1):min(dwell,ceil(dwell*.7));
aligned=complex(zeros(n,repeats)); before=aligned;
phase=zeros(repeats,1); zeroRMS=phase; starts=phase;
for k=1:repeats
    first=lag+(k-1)*frameLength+1; starts(k)=first;
    quiet=y(first+guard:first+prefix-guard-1);
    zeroRMS(k)=sqrt(mean(abs(quiet).^2));
    assert(zeroRMS(k)<.02*sqrt(mean(abs(drive).^2)), ...
        'rfdac:TrainingFrame','Detected frame has no sufficiently quiet zero prefix.');
    payload=y(first+prefix+(0:n*dwell-1));
    samples=reshape(payload,dwell,n);
    serial=mean(samples(middle,:),1).';
    values=complex(zeros(n,1)); values(order)=serial;
    phase(k)=angle(drive'*values);
    before(:,k)=values; aligned(:,k)=values*exp(-1i*phase(k));
end
observed=mean(aligned,2);
meta.Counts=repeats*ones(n,1); meta.Frame_Starts=starts;
meta.Payload_Starts=starts+prefix; meta.Frame_Length_DAC=frameLength;
meta.Phase_Alignment_Rad=phase; meta.Zero_Prefix_RMS_V=zeroRMS;
meta.First_Activity_DAC=activity; meta.Correlation_Lag_DAC=lag;
meta.Point_Sampling_Offsets=middle;
meta.Point_Observations_Before_Phase=before;
meta.Point_Observations_Aligned=aligned;
meta.Scatter_RMS_V=sqrt(mean(abs(aligned-observed).^2,2));
end
