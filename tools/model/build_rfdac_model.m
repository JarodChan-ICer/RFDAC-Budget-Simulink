function build_rfdac_model(cfg)
%BUILD_RFDAC_MODEL Rebuild the delivered native, frame-based Simulink model.
% Each frame is ONE symbol interval, containing real cfg.Sample_Rate samples.
paths=setup_rfdac_project();
if nargin<1, cfg=init_rfdac_model(); end
[p,cfg]=rfdac_prepare(cfg);
requestedCfg=cfg;
if strcmp(p.DPD.Algorithm,'lut') && isempty(p.DPD.LUT.Training_Output)
    % Model construction compiles intermediate schemas. Train only after the
    % complete model exists, never recursively from an InitFcn compilation.
    cfg.DPD_Enable=false; [p,cfg]=rfdac_prepare(cfg);
end
assignin('base','cfg',cfg); assignin('base','p',p);
m=cfg.Model_Name;
if bdIsLoaded(m), close_system(m,0); end
load_system('simulink'); new_system(m);
set_param(m,'SolverType','Fixed-step','Solver','FixedStepDiscrete', ...
    'FixedStep','p.Frame_Period','StopTime','p.Stop_Time', ...
    'ReturnWorkspaceOutputs','on','SaveTime','off','SaveOutput','off', ...
    'SignalLogging','off','InitFcn','rfdac_model_init;', ...
    'Description',['Real passband RF-DAC. LO and total RRC bandwidth are set by cfg. ' ...
    'RF sample rate and FIR orders auto-adjust when required; samples use symbol-length frames.'], ...
    'Location',[20 40 1530 940]);
set_param(m,'PostLoadFcn',sprintf('addpath(fileparts(get_param(''%s'',''FileName''))); setup_rfdac_project;',m));

s=sub(m,'QAM Source',[50 130 225 250]);
blk('Sources/From Workspace',s,'Random codewords',[25 50 155 85], ...
    'VariableName','p.Symbol_Data','SampleTime','p.Frame_Period','Interpolate','off','OutputAfterFinalValue','Holding final value');
blk('User-Defined Functions/Level-2 MATLAB S-Function',s,'Gray QAM mapper',[200 40 350 95], ...
    'FunctionName','rfdac_qam_map','Parameters','p.Source_Constellation');
blk('Sources/Constant',s,'Impulse and amplitude',[200 145 350 180],'Value','p.TX_Impulse');
blk('Math Operations/Product',s,'Symbol upsampling',[395 65 430 115]);
fir(s,'TX RRC pulse shaping',[480 65 640 115],'p.RRC');
blk('Math Operations/Complex to Real-Imag',s,'I Q split',[690 65 735 115]);
out(s,'I analog input',1,[820 45 850 65]); out(s,'Q analog input',2,[820 115 850 135]);
out(s,'Reference symbol',3,[420 230 450 250]);
wire(s,'Random codewords/1','Gray QAM mapper/1','codeword');
wire(s,'Gray QAM mapper/1','Symbol upsampling/1','unit_power_QAM');
wire(s,'Impulse and amplitude/1','Symbol upsampling/2');
wire(s,'Symbol upsampling/1','TX RRC pulse shaping/1');
wire(s,'TX RRC pulse shaping/1','I Q split/1');
wire(s,'I Q split/1','I analog input/1','I_input'); wire(s,'I Q split/2','Q analog input/1','Q_input');
wire(s,'Gray QAM mapper/1','Reference symbol/1');
tap(s,'I Q split/1','input_i',[805 320 930 340]);
tap(s,'I Q split/2','input_q',[805 370 930 390]);
note(s,'Random integer codewords -> Gray square QAM, E[|s|^2]=1.\nRRC: 320 MBaud, rolloff 0.25 => TOTAL bandwidth 400 MHz.\nPulse shaping runs at the physical DAC sample rate. Negative codeword flushes zeros.',[20 410 840 475]);

make_dac(m,'10-bit I DAC',[280 110 450 175],'i');
make_dac(m,'10-bit Q DAC',[280 230 450 295],'q');
s=sub(m,'Reconstruction LPF',[515 130 700 260]);
in(s,'I DAC',1,[25 55 55 75]); in(s,'Q DAC',2,[25 170 55 190]);
fir(s,'I reconstruction FIR',[115 40 290 90],'p.TX_FIR');
fir(s,'Q reconstruction FIR',[115 155 290 205],'p.TX_FIR');
out(s,'I filtered',1,[395 55 425 75]); out(s,'Q filtered',2,[395 170 425 190]);
wire(s,'I DAC/1','I reconstruction FIR/1'); wire(s,'Q DAC/1','Q reconstruction FIR/1');
wire(s,'I reconstruction FIR/1','I filtered/1'); wire(s,'Q reconstruction FIR/1','Q filtered/1');
tap(s,'I reconstruction FIR/1','filtered_i',[330 275 450 295]);
tap(s,'Q reconstruction FIR/1','filtered_q',[330 320 450 340]);
note(s,'Separate unity-DC, linear-phase Blackman FIRs at Sample_Rate.\nConfigurable cutoff/order; physical DAC zero-order-hold images are filtered.',[20 385 650 440]);

s=sub(m,'Jittered LO',[520 370 705 485]);
out(s,'LO I',1,[415 35 445 55]); out(s,'LO Q',2,[415 120 445 140]);
% update_rfdac_evm_model fills these ports with the four-phase streaming LO.

s=sub(m,'Quadrature Mixer',[775 155 945 300]);
in(s,'I filtered',1,[30 40 60 60]); in(s,'Q filtered',2,[30 140 60 160]);
in(s,'LO cosine',3,[30 235 60 255]); in(s,'LO sine',4,[30 310 60 330]);
blk('Math Operations/Product',s,'I times cosine',[175 55 220 95]);
blk('Math Operations/Product',s,'Q times sine',[175 150 220 190]);
blk('Math Operations/Sum',s,'Icos minus Qsin',[330 100 370 150],'Inputs','+-');
out(s,'Real RF',1,[485 115 515 135]);
wire(s,'I filtered/1','I times cosine/1'); wire(s,'LO cosine/1','I times cosine/2');
wire(s,'Q filtered/1','Q times sine/1'); wire(s,'LO sine/1','Q times sine/2');
wire(s,'I times cosine/1','Icos minus Qsin/1'); wire(s,'Q times sine/1','Icos minus Qsin/2');
wire(s,'Icos minus Qsin/1','Real RF/1','RF_before_Gm');
tap(s,'Icos minus Qsin/1','rf_before_gm',[410 240 560 260]);
note(s,'Real RF = I*cos(phi) - Q*sin(phi).\nThe two quadrature paths preserve the complex modulation.',[20 390 640 445]);

s=sub(m,'TX EVM Nonlinearity',[1020 185 1205 275]);
in(s,'RF input',1,[25 70 55 90]);
out(s,'RF output',1,[830 75 860 95]);
% update_rfdac_evm_model fills the fitted, monotonic RF atan compressor.

s=sub(m,'Receiver Downconversion',[1000 530 1220 660]);
in(s,'Real RF',1,[20 50 50 70]);
blk('Signal Routing/From',s,'RX phase',[20 195 165 240],'GotoTag','rfdac_rx_phase');
blk('Math Operations/Trigonometric Function',s,'RX cosine',[210 165 265 205],'Operator','cos');
blk('Math Operations/Trigonometric Function',s,'RX sine',[210 265 265 305],'Operator','sin');
blk('Math Operations/Product',s,'I mixing',[315 45 360 85]);
blk('Math Operations/Product',s,'Q mixing',[315 110 360 150]);
blk('Math Operations/Gain',s,'I gain two',[400 40 450 85],'Gain','2');
blk('Math Operations/Gain',s,'Q gain minus two',[400 110 450 155],'Gain','-2');
blk('Math Operations/Real-Imag to Complex',s,'Recovered complex baseband',[500 65 550 125]);
fir(s,'Receiver anti alias LPF',[600 65 785 120],'p.RX_FIR');
select(s,'Decimate to DAC rate',[835 65 950 120],'p.RX_Decimation_Indices','p.Samples_Per_Symbol');
fir(s,'RRC matched filter',[1000 65 1160 120],'p.RX_RRC');
fir(s,'Fractional timing correction',[1210 65 1390 120],'p.Fractional_FIR');
select(s,'Symbol sample selection',[1440 65 1600 120],'p.Decision_Index','p.DAC_Samples_Per_Symbol');
out(s,'Received symbol',1,[1650 80 1680 100]);
wire(s,'Real RF/1','I mixing/1'); wire(s,'Real RF/1','Q mixing/1');
wire(s,'RX phase/1','RX cosine/1'); wire(s,'RX phase/1','RX sine/1');
wire(s,'RX cosine/1','I mixing/2'); wire(s,'RX sine/1','Q mixing/2');
wire(s,'I mixing/1','I gain two/1'); wire(s,'Q mixing/1','Q gain minus two/1');
wire(s,'I gain two/1','Recovered complex baseband/1'); wire(s,'Q gain minus two/1','Recovered complex baseband/2');
wire(s,'Recovered complex baseband/1','Receiver anti alias LPF/1');
wire(s,'Receiver anti alias LPF/1','Decimate to DAC rate/1'); wire(s,'Decimate to DAC rate/1','RRC matched filter/1');
wire(s,'RRC matched filter/1','Fractional timing correction/1'); wire(s,'Fractional timing correction/1','Symbol sample selection/1');
wire(s,'Symbol sample selection/1','Received symbol/1','symbol_after_timing');
tap(s,'Receiver anti alias LPF/1','rx_baseband',[670 285 830 305]);
tap(s,'Fractional timing correction/1','rx_matched',[1260 285 1420 305]);
tap(s,'Symbol sample selection/1','rx_symbol',[1490 285 1620 305]);
note(s,'LO modes: ideal (default), shared TX timing realization, independent jitter.\n2*RF*cos and -2*RF*sin -> anti-alias FIR -> DAC-rate decimation -> matched RRC.\nCubic fractional delay plus symbol indexing accounts for RRC, LPF and ZOH delays.',[20 400 1280 480]);

s=sub(m,'QAM Demodulator',[590 545 810 675]);
in(s,'Received symbol',1,[20 45 50 65]); in(s,'Reference symbol',2,[20 150 50 170]);
blk('Discrete/Delay',s,'Reference delay',[105 135 245 185],'DelayLength','p.Decision_Frame_Delay');
blk('User-Defined Functions/Level-2 MATLAB S-Function',s,'Training gain and Gray demapper',[310 60 540 155], ...
    'FunctionName','rfdac_qam_demod','Parameters','cfg.QAM_Order');
blk('Sinks/Terminator',s,'Decision sink',[660 75 685 95]);
blk('Sinks/Terminator',s,'Equalized sink',[660 145 685 165]);
wire(s,'Received symbol/1','Training gain and Gray demapper/1');
wire(s,'Reference symbol/1','Reference delay/1'); wire(s,'Reference delay/1','Training gain and Gray demapper/2');
wire(s,'Training gain and Gray demapper/1','Decision sink/1'); wire(s,'Training gain and Gray demapper/2','Equalized sink/1');
tap(s,'Training gain and Gray demapper/1','online_decisions',[510 255 670 275]);
tap(s,'Training gain and Gray demapper/2','online_symbols',[510 310 670 330]);
note(s,'Known-reference one-tap gain/phase training, then Gray qamdemod.\nPost-processing refits ONE constant complex gain over the full valid record,\nreports EVM/SNDR, and re-demodulates all symbols consistently.',[20 390 830 460]);

s=sub(m,'Measurements',[110 510 365 700]);
names={'input_i','input_q','codes_i','codes_q','dac_i','dac_q', ...
    'filtered_i','filtered_q','lo_i','lo_q','lo_phase_error', ...
    'rf_before_gm','rf_output','rx_baseband','rx_matched','rx_symbol', ...
    'online_decisions','online_symbols'};
for k=1:numel(names)
    col=floor((k-1)/6); row=mod(k-1,6); x=30+col*445; y=40+row*85;
    blk('Signal Routing/From',s,['Read ' names{k}],[x y x+155 y+25],'GotoTag',['rfdac_' names{k}]);
    blk('Sinks/To Workspace',s,['Save ' names{k}],[x+210 y-5 x+400 y+30], ...
        'VariableName',['log_' names{k}],'SaveFormat','Structure With Time', ...
        'MaxDataPoints','inf','Decimation','1','SampleTime','-1');
    wire(s,['Read ' names{k} '/1'],['Save ' names{k} '/1']);
end
note(s,'All physical waveforms are saved with frame timestamps.\nrun_rfdac_simulation reconstructs the sample time axes, computes EVM/SNDR,\nSER, signed-code clipping and DAC error, then saves MAT, CSV and PNG results.',[20 600 1210 680]);

wire(m,'QAM Source/1','10-bit I DAC/1','I_at_DAC_rate');
wire(m,'QAM Source/2','10-bit Q DAC/1','Q_at_DAC_rate');
wire(m,'10-bit I DAC/1','Reconstruction LPF/1','I_DAC_ZOH');
wire(m,'10-bit Q DAC/1','Reconstruction LPF/2','Q_DAC_ZOH');
wire(m,'Reconstruction LPF/1','Quadrature Mixer/1','I_filtered');
wire(m,'Reconstruction LPF/2','Quadrature Mixer/2','Q_filtered');
wire(m,'Jittered LO/1','Quadrature Mixer/3','LO_cos'); wire(m,'Jittered LO/2','Quadrature Mixer/4','LO_sin');
wire(m,'Quadrature Mixer/1','TX EVM Nonlinearity/1','RF_before_TX');
wire(m,'TX EVM Nonlinearity/1','Receiver Downconversion/1','RF_output_real');
wire(m,'Receiver Downconversion/1','QAM Demodulator/1','received_symbol');
wire(m,'QAM Source/3','QAM Demodulator/2','reference_symbol');
note(m,'RF-DAC LO JITTER LINK BUDGET | REAL PASSBAND\nLO: cfg.LO_Frequency | Total bandwidth: cfg.Baseband_Frequency | Signed I/Q DACs',[50 15 1270 85]);
note(m,'Physical rate: cfg.Sample_Rate; auto mode raises RF rate and FIR orders for higher LO.\nEach solver update contains a symbol-length frame of consecutive RF samples.\nConfigure cfg with init_rfdac_model; run run_rfdac_simulation(cfg); compare sweep_lo_jitter(cfg).',[55 780 1300 855]);
set_param(m,'ZoomFactor','85');
% Give intermediate schema upgrades an absolute save target, even from another cwd.
save_system(m,fullfile(paths.Root,[m '.slx']));
update_rfdac_evm_model(m);
update_rfdac_rx_equalizer_model(m);
update_rfdac_dpd_model(m);
save_system(m,fullfile(paths.Root,[m '.slx']));
fprintf('Built %s.slx\n',m);
[p,cfg]=rfdac_prepare(requestedCfg);
assignin('base','cfg',cfg); assignin('base','p',p);
end

function make_dac(m,name,pos,suffix)
s=sub(m,name,pos);
in(s,'Analog desired input',1,[20 70 50 90]);
blk('Math Operations/Gain',s,'Volts to signed code',[105 60 210 105],'Gain','1/p.LSB');
blk('Math Operations/Rounding Function',s,'Round to nearest',[250 60 365 105],'Operator','round');
blk('Discontinuities/Saturation',s,'Signed N bit saturation',[405 60 545 105], ...
    'UpperLimit','p.Max_Code','LowerLimit','p.Min_Code');
blk('Math Operations/Gain',s,'DAC code to volts',[590 60 710 105],'Gain','p.LSB');
select(s,'Physical zero order hold',[755 60 920 105],'p.DAC_Hold_Indices','p.DAC_Samples_Per_Symbol');
out(s,'DAC held voltage',1,[995 75 1025 95]);
wire(s,'Analog desired input/1','Volts to signed code/1'); wire(s,'Volts to signed code/1','Round to nearest/1');
wire(s,'Round to nearest/1','Signed N bit saturation/1'); wire(s,'Signed N bit saturation/1','DAC code to volts/1');
wire(s,'DAC code to volts/1','Physical zero order hold/1'); wire(s,'Physical zero order hold/1','DAC held voltage/1');
tap(s,'Signed N bit saturation/1',['codes_' suffix],[485 200 615 220]);
tap(s,'Physical zero order hold/1',['dac_' suffix],[860 200 990 220]);
note(s,'10-bit default: LSB=2*FS/1024, codes -512..511, voltages -FS..FS-LSB.\nInteger-valued doubles are the exact signed codewords (no Fixed-Point license needed).\nPhysical DAC updates at DAC_Sample_Rate and holds between RF time samples.\nAdd gain/offset, INL/DNL or skew inside this subsystem.',[20 300 1140 395]);
end
function s=sub(parent,name,pos)
s=[parent '/' name]; add_block('built-in/Subsystem',s,'Position',pos,'BackgroundColor','lightBlue');
end
function blk(lib,parent,name,pos,varargin)
add_block(['simulink/' lib],[parent '/' name],'Position',pos,varargin{:});
end
function in(s,name,num,pos)
blk('Ports & Subsystems/In1',s,name,pos,'Port',num2str(num));
end
function out(s,name,num,pos)
blk('Ports & Subsystems/Out1',s,name,pos,'Port',num2str(num));
end
function fir(s,name,pos,coeff)
blk('Discrete/Discrete FIR Filter',s,name,pos,'Coefficients',coeff, ...
    'InputProcessing','Columns as channels (frame based)');
end
function select(s,name,pos,idx,width)
blk('Signal Routing/Selector',s,name,pos,'NumberOfDimensions','1', ...
    'IndexMode','One-based','IndexOptionArray',{'Index vector (dialog)'}, ...
    'IndexParamArray',{idx},'InputPortWidth',width);
end
function fromws(s,name,var,pos)
blk('Sources/From Workspace',s,name,pos,'VariableName',var, ...
    'SampleTime','p.Frame_Period','Interpolate','off','OutputAfterFinalValue','Holding final value');
end
function wire(s,a,b,varargin)
h=add_line(s,a,b,'autorouting','on');
if ~isempty(varargin), set_param(h,'Name',varargin{1}); end
end
function tap(s,port,tag,pos)
blk('Signal Routing/Goto',s,['Log ' tag],pos,'GotoTag',['rfdac_' tag],'TagVisibility','global');
wire(s,port,['Log ' tag '/1']);
end
function note(s,txt,pos)
a=Simulink.Annotation(s,sprintf(txt)); a.Position=pos; a.FontSize=11;
end
