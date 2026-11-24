function cfg = init_rfdac_model()
%INIT_RFDAC_MODEL Central configuration (SI units unless stated otherwise).
% cfg = init_rfdac_model; cfg.LO_RMS_Jitter = 100e-15;
% results = run_rfdac_simulation(cfg);
paths=setup_rfdac_project();
cfg=rfdac_default_config(); % shared base; the settings below belong to this workflow
cfg.Model_Name = 'rfdac_lo_jitter_link_budget';
%% System Set
cfg.TX_Nonlinearity_Enable = true;
cfg.TX_Target_EVM_dB = -42;         % TX SNR 42 dB: clean TX with ideal LO legs and no jitter
cfg.LO_Frequency = 15e9;            % RF LO frequency, Hz
cfg.LO_RMS_Jitter = 100e-15;        % 100fs RMS jitter
cfg.LO_Quadrature_Error_Enable = true;
cfg.LO_Quadrature_Error_Deg = 1;    % daily default; sweep 1..3 deg with run_rfdac_iq_mismatch_sweep
cfg.LO_Differential_Phase_Error_Deg = 0.8; % added to the 180 and 270 degree legs
cfg.LO_Quadrature_Amplitude_Mismatch = .10; % both Q legs have normalized gain 1.10
cfg.LO_Jitter_Enable = true;
cfg.Jitter_Mode = 'white';    % 'bandlimited' (stationary AR(1)) or 'white'
cfg.Jitter_Bandwidth = 5e6;         % One-pole correlation bandwidth, Hz
%% Baseband Set
cfg.QAM_Order = 4096;
cfg.DAC_Bits = 10;
cfg.DAC_Full_Scale = 1;          % signed range [-FS, FS-LSB]
cfg.Input_Amplitude = 0.35;      % unit-average-power QAM multiplier; clipping headroom

cfg.Baseband_Frequency = 400e6;  % TOTAL occupied RRC baseband bandwidth, Hz
cfg.Sample_Rate = 80e9;         % requested RF sample rate; auto mode can raise it
cfg.Sample_Rate_Auto = true;    % raise Fs AND FIR orders when LO requires it
cfg.DAC_Sample_Rate = 8e9;       % physical DAC zero-order-hold update rate

cfg.Symbol_Rate = [];          % [] => bandwidth/(1+RRC_Rolloff) = 320 MBaud
cfg.RRC_Rolloff = 0.25;
cfg.RRC_Span = 16;             % pulse length in symbols, even
cfg.Oversampling_Ratio = [];    % [] => Sample_Rate / Symbol_Rate; or set explicitly

cfg.Num_Symbols = 16384;

cfg.LPF_Cutoff = 500e6;         % FIR windowed-sinc -6 dB transition midpoint
cfg.LPF_Order = 1024;           % even order, 1025 taps
cfg.LPF_Transition_Bandwidth = 0.6e9; % design/verification target; see README

cfg.RX_LPF_Cutoff = 500e6;
cfg.RX_LPF_Order = 1024;
cfg.TX_Nonlinearity_Beta = [];  % [] automatically fits atan(sqrt(beta)*x)/sqrt(beta)
cfg.TX_EVM_Fit_Tolerance_dB = 0.01;

%% DPD set
cfg.DPD_Enable = true;          % digital predistortion BEFORE the I/Q DACs
cfg.DPD_IQ_Enable = true;       % invert static four-phase LO IQ imbalance
cfg.DPD_Nonlinearity_Enable = true; % invert atan RF fundamental AM/AM
cfg.DPD_TX_Beta_Estimate = [];  % analytic/static reference only; link LUT ignores estimates
cfg.DPD_Quadrature_Estimate_Deg = []; % analytic/static reference only
cfg.DPD_Phase_Errors_Estimate_Deg = []; % analytic/static reference only
cfg.DPD_Max_Gain = 2;           % analytic reference only; LUT uses bounded trained drives
cfg.DPD_Algorithm = 'lut';      % 'lut' actual lookup, 'analytic' reference inverse
cfg.DPD_LUT_Size_Mode = 'training_order'; % 'training_order', 'total_points', 'axis_bits', 'qam_multiple'
cfg.DPD_LUT_Training_Order = 16384; % 128x128 measured snake points, BEFORE interpolation
cfg.DPD_LUT_Training_Mode = 'link'; % PPT: zero prefix + snake -> RF -> demod/phase alignment
cfg.DPD_LUT_Training_Observed = []; % []: capture actual link; or supplied paired RX symbols in V
cfg.DPD_LUT_Training_Repeats = 2; % repeat complete zero-prefixed snake frames
cfg.DPD_LUT_Training_Dwell_Samples = 25; % DAC updates per snake point
cfg.DPD_LUT_Training_Prefix_Zeros = 512; % zero guard before/after each snake
cfg.DPD_LUT_Training_Seed = 1073; % independent of payload seed
cfg.DPD_LUT_Drive_Range = 1;  % full legal DAC range; training is a raw snake, not random RRC QAM
cfg.DPD_LUT_Points = 16384;     % total_points mode: training candidate count
cfg.DPD_LUT_Address_Bits = [7 7]; % [I Q], used in axis_bits mode
cfg.DPD_LUT_Points_Per_QAM_Symbol = 4; % qam_multiple mode only; 4096*4=16384
cfg.DPD_LUT_Value_Bits = 10;    % bits per absolute I/Q DAC word (>= DAC_Bits)
cfg.DPD_LUT_Fraction_Bits = 0;  % must be zero: integer training DAC words
cfg.DPD_LUT_Interpolation = 'linear'; % measured 128x128 -> dense 1024x1024 -> nearest output b/input c
cfg.DPD_LUT_Max_Penalty_dB = 0.1; % sweep: allowed EVM penalty vs analytic; no auto override


cfg.Random_Seed = 73;
cfg.Measure_DAC_Noise = true;
cfg.Make_Plots = true;
%% RX set
cfg.RX_Equalizer_Enable = true;     % auto-fit TX/RX LPF + DAC-hold in-band droop
cfg.RX_Equalizer_Order = 256;       % even FIR order at DAC rate, before matched RRC
cfg.RX_Equalizer_Max_Boost_dB = 6;   % bounded gain; never invert the LPF stopband
cfg.RX_Equalizer_Regularization = 1e-6; % stabilize the coefficient fit
cfg.RX_LO_Mode = 'ideal';           % 'ideal', 'shared', 'independent'
cfg.RX_LO_Frequency = [];           % [] follows TX LO frequency
cfg.RX_LO_Phase = 0;                % radians
cfg.RX_LO_RMS_Jitter = [];          % [] follows TX RMS setting
cfg.LO_Phase_Errors_Deg = [0 0 0 0]; % optional additional errors on each leg

%% Plot
cfg.Plot_Constellation = true;   % final recovered symbols (primary result)
cfg.Plot_DPD_Comparison = true;  % paired actual SLX run, identical plant/data/jitter
cfg.Plot_DPD_LUT_Selection = true; % centered lower panel: all training RF outputs, selected points in red
cfg.Plot_LPF_Response = false;   % separate reconstruction/RX FIR response figure
cfg.Plot_Waveforms = false;      % separate time-domain I/Q, codewords and RF
cfg.Plot_Spectra = false;        % separate baseband/RF PSD figure
cfg.Plot_Diagnostics = false;    % error vectors, jitter and RF AM/AM figure
cfg.Figure_Visible = 'on';
cfg.Save_Results = true;
cfg.Waveform_Log_Frames = 128;  % contiguous tail preview; Inf logs every frame
cfg.Output_Directory = paths.Results;
cfg.Run_Tag = 'single';
if nargout == 0
    assignin('base','cfg',cfg);
    fprintf('RF-DAC defaults installed as cfg. Run run_rfdac_simulation(cfg).\n');
end
end
