function [cfg,opt]=init_rfdac_identification()
% Independent RX identification configuration; no model init is required.
% cfg describes the simulated device; opt controls acquisition/plots/statistics.
paths=setup_rfdac_project();
cfg=rfdac_default_config();
%% Device under test (truth is hidden from the estimator)
cfg.LO_Frequency=10e9; 
cfg.RX_LO_Frequency=[];
cfg.TX_Target_EVM_dB=-42; % +42 dB whole clean-TX MER, including RRC/DAC/LPFs

cfg.LO_RMS_Jitter=100e-15; cfg.LO_Quadrature_Error_Deg=1;

cfg.LO_Quadrature_Error_Enable=true; cfg.LO_Jitter_Enable=true;

cfg.LO_Phase_Errors_Deg=zeros(1,4); cfg.TX_Nonlinearity_Enable=true;
cfg.TX_Nonlinearity_Beta=[];
cfg.QAM_Order=4096;
cfg.DAC_Bits=10; cfg.DAC_Full_Scale=1;
cfg.Input_Amplitude=.35;
cfg.Baseband_Frequency=400e6; % total RRC bandwidth
cfg.Sample_Rate=80e9; cfg.Sample_Rate_Auto=true;
cfg.DAC_Sample_Rate=8e9;
cfg.Jitter_Mode='white'; % 'white' or 'bandlimited'
cfg.Jitter_Bandwidth=5e6;
cfg.DPD_Algorithm='lut';
cfg.DPD_LUT_Training_Mode='static'; % separate parameter-identification reference experiment
cfg.DPD_LUT_Drive_Range=1;
cfg.DPD_LUT_Size_Mode='training_order'; cfg.DPD_LUT_Training_Order=16384;
cfg.DPD_LUT_Training_Observed=[];
cfg.DPD_LUT_Value_Bits=10; cfg.DPD_LUT_Fraction_Bits=0;
cfg.DPD_LUT_Interpolation='nearest';
cfg.DPD_Enable=false; cfg.Make_Plots=false; cfg.Save_Results=false;
cfg.Plot_DPD_Comparison=false;
%% Identification workflow (these control the final identification figures)
opt.Output_Directory=fullfile(paths.Validation,'rx_identification');
opt.Figure_Visible='on'; % 'off' saves PNGs without opening windows
opt.Training_Amplitudes=[.07 .10 .14];
opt.Training_Symbols=4096;
opt.Capture_Frames=2048;
opt.Validation_Symbols=16384;
opt.Monte_Carlo_Repeats=0; % EXTRA complete re-identifications; 5 => 6 trials total
opt.Training_Seed=1073;
opt.Validation_Seed=4073;
opt.Cluster_Symbols=32;
opt.Observer_Gain=.83; % simulator-only observation nuisance, hidden from fitter
opt.Observer_DC_Offset=.003;
if nargout==0
    assignin('base','cfg',cfg); assignin('base','opt',opt);
    fprintf('Identification cfg/opt installed. Run run_rfdac_identification(cfg,opt).\n');
end
end
