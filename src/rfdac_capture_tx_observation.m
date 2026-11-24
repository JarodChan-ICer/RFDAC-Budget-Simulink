function capture=rfdac_capture_tx_observation(cfg,opt)
% Simulator boundary: export ONLY known input words and observable RF samples.
% Full cfg, RF-before-TX, true jitter, beta and metrics never reach estimator.
cfg.Make_Plots=false; cfg.Save_Results=false; cfg.DPD_Enable=false;
cfg.Waveform_Log_Frames=opt.Capture_Frames;
r=run_rfdac_simulation(cfg);
assert(r.waveform_start_time.codes_i==r.waveform_start_time.rf_output);
capture.Codes=complex(r.waveforms.codes_i,r.waveforms.codes_q);
capture.RF=opt.Observer_Gain*r.waveforms.rf_output+opt.Observer_DC_Offset;
capture.Start_Time=r.waveform_start_time.rf_output;
capture.Amplitude=cfg.Input_Amplitude;
end
