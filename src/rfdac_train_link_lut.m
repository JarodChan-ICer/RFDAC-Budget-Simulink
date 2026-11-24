function [observed,meta]=rfdac_train_link_lut(c,p)
% Chip-test PPT pp.4-6: zero-prefixed snake -> physical RF -> equalized RX.
persistent cachedKey cachedObserved cachedMeta
key=rfdac_lut_training_key(c,p);
if isequal(key,cachedKey), observed=cachedObserved; meta=cachedMeta; return; end
lut=p.DPD.LUT; drive=lut.Training_Drive(:);
training=c;
training.DPD_LUT_Size_Mode='axis_bits'; training.DPD_LUT_Address_Bits=log2(lut.Training_Size);
opt=struct('Repeats',c.DPD_LUT_Training_Repeats, ...
    'Dwell',c.DPD_LUT_Training_Dwell_Samples, ...
    'Prefix',c.DPD_LUT_Training_Prefix_Zeros,'Seed',c.DPD_LUT_Training_Seed);
% Training and mapped-QAM measurement share the same causal equalized RX
% observation domain. The helper freezes beta and disables additional DPD.
capture=rfdac_capture_serpentine(training,p,drive,lut.Training_Size,opt);
observed=capture.Output;
meta=capture.Alignment;
meta.Source=capture.Source;
meta.Pipeline='ppt_serpentine_v1'; meta.Key=key;
meta.Training_Order=lut.Training_Order; meta.Training_Size=lut.Training_Size;
meta.Training_Drive=drive; meta.Snake_Order=capture.Snake_Order;
meta.Dwell_DAC_Samples=capture.Dwell_DAC_Samples;
meta.Prefix_Zero_Samples=capture.Prefix_Zero_Samples;
meta.Requested_Prefix_Zero_Samples=capture.Requested_Prefix_Zero_Samples;
meta.Prefix_Extended=capture.Prefix_Extended;
meta.Guard_DAC_Samples=capture.Guard_DAC_Samples;
meta.Observer_Fractional_FIR=capture.Observer_Fractional_FIR;
meta.Observer_Delay_DAC_Samples=capture.Observer_Delay_DAC_Samples;
meta.RX_Equalizer_FIR=capture.RX_Equalizer_FIR;
meta.Observation_Domain=capture.Measurement_Domain;
meta.Physical_Beta=capture.Physical_Beta; meta.DPD_Enabled=false;
meta.LO_Phase_Offsets_Deg=capture.LO_Phase_Offsets_Deg;
meta.LO_Leg_Amplitudes=capture.LO_Leg_Amplitudes;
meta.LO_Leg_Waveform_Max_Error=capture.LO_Leg_Waveform_Max_Error;
meta.LO_Differential_Waveform_Max_Error=capture.LO_Differential_Waveform_Max_Error;
meta.Training_Seed=c.DPD_LUT_Training_Seed;
meta.Simulation_Seconds=capture.Simulation_Seconds; meta.Jitter_Enabled=logical(c.LO_Jitter_Enable);
meta.Alignment=['Zero guards + configured RX equalizer + known-snake correlation; ' ...
    'phase from received pilots only; physical amplitude retained'];
meta.DAC_I_Clipped_Full=capture.DAC_I_Clipped_Full;
meta.DAC_Q_Clipped_Full=capture.DAC_Q_Clipped_Full;
% Preserve measured points/extraction evidence without duplicating the long
% continuous envelope. No model-derived output is substituted.
folder=fullfile(rfdac_project_root(),'outputs','cache');
if ~isfolder(folder), mkdir(folder); end
save(fullfile(folder,[c.Run_Tag '_ppt_training_capture.mat']),'observed','meta','-v7.3');
cachedKey=key; cachedObserved=observed; cachedMeta=meta;
end
