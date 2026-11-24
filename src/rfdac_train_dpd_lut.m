function observed=rfdac_train_dpd_lut(drive,d)
% Static RF characterization of every candidate drive, not analytic inversion.
% Hold each I/Q point to steady state, probe one uniformly sampled RF period,
% and coherently measure its complex fundamental. Linear filters have unity
% DC gain; waveform memory/jitter/observation noise are not trained here.
envelope=drive(:);
if d.IQ_Enable, envelope=d.Alpha*envelope+d.Image*conj(envelope); end
if ~d.Nonlinearity_Enable || d.Beta==0
    observed=reshape(envelope,size(drive)); return;
end
phase=(0:127)*2*pi/128;
carrier=exp(1i*phase); demod=conj(carrier).';
k=sqrt(d.Beta); response=complex(zeros(size(envelope)));
for first=1:256:numel(envelope)
    selected=first:min(first+255,numel(envelope));
    rf=real(envelope(selected)*carrier);
    rf=atan(k*rf)/k;
    response(selected)=2/numel(phase)*(rf*demod);
end
observed=reshape(response,size(drive));
end
