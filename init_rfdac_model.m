function cfg = init_rfdac_model()
%INIT_RFDAC_MODEL Central configuration (SI units unless stated otherwise).
% cfg = init_rfdac_model; cfg.LO_RMS_Jitter = 100e-15;
% results = run_rfdac_simulation(cfg);
paths=setup_rfdac_project();
cfg.Model_Name = 'rfdac_lo_jitter_link_budget';
%% System Set
cfg.TX_Nonlinearity_Enable = true;
cfg.TX_Target_EVM_dB = -45;         % whole TX, with jitter OFF and perfect quadrature
cfg.LO_Frequency = 7e9;             % RF LO frequency, Hz
cfg.LO_RMS_Jitter = 100e-15;        % 100fs RMS jitter
cfg.LO_Quadrature_Error_Enable = true;
cfg.LO_Quadrature_Error_Deg = 1;    % four phases: 0, 90+error, 180, 270+error
cfg.LO_Jitter_Enable = true;
cfg.Jitter_Mode = 'white';    % 'bandlimited' (stationary AR(1)) or 'white'
cfg.Jitter_Bandwidth = 5e6;         % One-pole correlation bandwidth, Hz
%% Baseband Set
cfg.QAM_Order = 4096;
cfg.DAC_Bits = 10;
cfg.DAC_Full_Scale = 1;          % signed range [-FS, FS-LSB]
cfg.Input_Amplitude = 0.35;      % unit-average-power QAM multiplier; clipping headroom
cfg.Baseband_Frequency = 400e6;  % TOTAL occupied baseband bandwidth, Hz
cfg.Sample_Rate = 80e9;         % requested RF sample rate; auto mode can raise it
cfg.Sample_Rate_Auto = true;    % raise Fs AND FIR orders when LO requires it
cfg.DAC_Sample_Rate = 8e9;       % physical DAC zero-order-hold update rate
cfg.Symbol_Rate = [];           % [] => bandwidth/(1+RRC_Rolloff) = 320 MBaud
cfg.RRC_Rolloff = 0.25;
cfg.RRC_Span = 16;              % pulse length in symbols, even
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
cfg.DPD_Nonlinearity_Enable = false; % invert atan RF fundamental AM/AM
cfg.DPD_TX_Beta_Estimate = [];  % [] uses known TX beta: optimistic model limit
cfg.DPD_Quadrature_Estimate_Deg = []; % [] uses actual static LO setting
cfg.DPD_Phase_Errors_Estimate_Deg = []; % [] uses actual additional leg errors
cfg.DPD_Max_Gain = 2;           % bound nonlinear inverse gain / avoid pole
cfg.DPD_Algorithm = 'lut';      % 'lut' actual lookup, 'analytic' reference inverse
cfg.DPD_LUT_Size_Mode = 'total_points'; % 'total_points', 'axis_bits', 'qam_multiple'
cfg.DPD_LUT_Points = 16384;     % TOTAL complex correction entries = 128 x 128
cfg.DPD_LUT_Address_Bits = [7 7]; % [I Q], used in axis_bits mode
cfg.DPD_LUT_Points_Per_QAM_Symbol = 4; % qam_multiple mode only; 4096*4=16384
cfg.DPD_LUT_Value_Bits = 10;    % signed bits per I/Q CORRECTION stored in table
cfg.DPD_LUT_Fraction_Bits = 0;  % fractional bits in DAC-code units, not volts
cfg.DPD_LUT_Interpolation = 'nearest'; % 'nearest' pure lookup, 'linear' bilinear
cfg.DPD_LUT_Max_Penalty_dB = 0.1; % sweep: allowed EVM penalty vs analytic; no auto override


cfg.Random_Seed = 73;
cfg.Measure_DAC_Noise = true;
cfg.Make_Plots = true;
%% RX set
cfg.RX_LO_Mode = 'ideal';           % 'ideal', 'shared', 'independent'
cfg.RX_LO_Frequency = [];           % [] follows TX LO frequency
cfg.RX_LO_Phase = 0;                % radians
cfg.RX_LO_RMS_Jitter = [];          % [] follows TX RMS setting
cfg.LO_Phase_Errors_Deg = [0 0 0 0]; % optional additional errors on each leg

%% Plot
cfg.Plot_Constellation = true;   % final recovered symbols (primary result)
cfg.Plot_DPD_Comparison = true;  % paired actual SLX run, identical plant/data/jitter
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
