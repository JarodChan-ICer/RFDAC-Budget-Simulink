function update_rfdac_dpd_model(m)
% Insert digital I/Q DPD after TX RRC pulse shaping and before the DACs.
if nargin<1, c=init_rfdac_model(); m=c.Model_Name; end
load_system(m); s=[m '/Digital Predistortion'];
if getSimulinkBlockHandle(s)>0 && strcmp(get_param(s,'Tag'),'rfdac_dpd_v7'), return; end
if getSimulinkBlockHandle(s)>0 && ismember(get_param(s,'Tag'),{'rfdac_dpd_v2','rfdac_dpd_v3','rfdac_dpd_v4','rfdac_dpd_v5','rfdac_dpd_v6'})
    finish(s); save_system(m); return;
end
fresh=getSimulinkBlockHandle(s)<0;
if ~fresh
    assert(strcmp(get_param(s,'Tag'),'rfdac_dpd_v1'),'An unrelated Digital Predistortion block already exists.');
end
if fresh
for name={'10-bit I DAC','10-bit Q DAC'}
    pp=get_param([m '/' name{1}],'PortHandles'); line=get_param(pp.Inport(1),'Line');
    if line>0, delete_line(line); end
end
add_block('built-in/Subsystem',s,'Position',[250 135 425 275],'BackgroundColor','green');
add('Ports & Subsystems/In1',s,'Desired I',[20 55 50 75],'Port','1');
add('Ports & Subsystems/In1',s,'Desired Q',[20 145 50 165],'Port','2');
add('User-Defined Functions/Level-2 MATLAB S-Function',s,'Envelope inverse then IQ inverse', ...
    [160 50 425 175],'FunctionName','rfdac_dpd_block','Parameters','p.DPD,p.DAC_Samples_Per_Symbol');
add('Ports & Subsystems/Out1',s,'Predistorted I',[570 60 600 80],'Port','1');
add('Ports & Subsystems/Out1',s,'Predistorted Q',[570 135 600 155],'Port','2');
wire(s,'Desired I/1','Envelope inverse then IQ inverse/1');
wire(s,'Desired Q/1','Envelope inverse then IQ inverse/2');
wire(s,'Envelope inverse then IQ inverse/1','Predistorted I/1');
wire(s,'Envelope inverse then IQ inverse/2','Predistorted Q/1');
wire(m,'QAM Source/1','Digital Predistortion/1'); wire(m,'QAM Source/2','Digital Predistortion/2');
wire(m,'Digital Predistortion/1','10-bit I DAC/1'); wire(m,'Digital Predistortion/2','10-bit Q DAC/1');
end
names={'dpd_i','dpd_q','dpd_statistics','dpd_ideal_i','dpd_ideal_q','input_codes_i','input_codes_q'};
% Refresh the saved v1 S-function port layout before wiring new log ports.
set_param(m,'SimulationCommand','update');
for k=1:numel(names)
    if ~fresh && k<=3, continue; end
    add('Signal Routing/Goto',s,['Log ' names{k}],[500 230+k*55 690 255+k*55], ...
        'GotoTag',['rfdac_' names{k}],'TagVisibility','global');
    wire(s,sprintf('Envelope inverse then IQ inverse/%d',k),['Log ' names{k} '/1']);
end
aa=find_system(s,'SearchDepth',1,'FindAll','on','Type','annotation');
for k=1:numel(aa), delete(get_param(aa(k),'Object')); end
a=Simulink.Annotation(s,sprintf(['Signed N-bit input words -> DPD inverse -> signed N-bit round/saturate.\n' ...
    'Nonlinear envelope inverse, then widely-linear inverse of static LO IQ mapping.\n' ...
    'Outputs are exact codeword voltages: code * LSB. DAC conversion remains active.\n' ...
    'Analog TX nonlinearity / LO errors remain. No instantaneous jitter is used.']));
a.Position=[20 730 1000 835]; a.FontSize=11;
if fresh
layout={'QAM Source',[30 130 205 250];'10-bit I DAC',[470 105 640 175]; ...
    '10-bit Q DAC',[470 230 640 300];'Reconstruction LPF',[700 135 885 265]; ...
    'Jittered LO',[700 365 885 485];'Quadrature Mixer',[955 155 1125 300]; ...
    'TX EVM Nonlinearity',[1190 185 1395 275];'Receiver Downconversion',[1190 550 1410 680]; ...
    'QAM Demodulator',[730 550 950 680];'Measurements',[120 535 375 725]};
for k=1:size(layout,1), set_param([m '/' layout{k,1}],'Position',layout{k,2}); end
end
meas=[m '/Measurements'];
for k=1:numel(names)
    if ~fresh && k<=3, continue; end
    y=650+k*80;
    add('Signal Routing/From',meas,['Read ' names{k}],[1410 y 1565 y+25], ...
        'GotoTag',['rfdac_' names{k}]);
    if k==3, limit='inf'; else, limit='cfg.Waveform_Log_Frames'; end
    add('Sinks/To Workspace',meas,['Save ' names{k}],[1620 y-5 1810 y+30], ...
        'VariableName',['log_' names{k}],'SaveFormat','Structure With Time','MaxDataPoints',limit);
    wire(meas,['Read ' names{k} '/1'],['Save ' names{k} '/1']);
end
finish(s); set_param(m,'ZoomFactor','75');
save_system(m); fprintf('Updated DPD: signed N-bit input/output codewords, original analog plant retained.\n');
end
function finish(s)
m=bdroot(s); source=[m '/QAM Source'];
rfdac_upgrade_ppt_source(m);
set_param([source '/Gray QAM mapper'],'Parameters','p.Source_Constellation');
reference=[source '/Reference QAM mapper'];
if getSimulinkBlockHandle(reference)<0
    add('User-Defined Functions/Level-2 MATLAB S-Function',source,'Reference QAM mapper', ...
        [200 225 350 270],'FunctionName','rfdac_qam_map','Parameters','p.Constellation');
    ports=get_param([source '/Reference symbol'],'PortHandles');
    line=get_param(ports.Inport(1),'Line'); if line>0, delete_line(line); end
    wire(source,'Random codewords/1','Reference QAM mapper/1');
    wire(source,'Reference QAM mapper/1','Reference symbol/1');
end
old=[s '/Envelope inverse then IQ inverse'];
if getSimulinkBlockHandle(old)>0, set_param(old,'Name','Selected DPD algorithm'); end
set_param([s '/Selected DPD algorithm'],'Parameters','p.DPD_Runtime,p.DAC_Samples_Per_Symbol');
aa=find_system(s,'SearchDepth',1,'FindAll','on','Type','annotation');
for k=1:numel(aa), delete(get_param(aa(k),'Object')); end
a=Simulink.Annotation(s,sprintf(['TX RRC -> N-bit desired waveform a -> nearest measured/interpolated output b -> paired input c.\n' ...
    'LINK LUT follows the chip-test PPT: zero-prefixed snake -> actual RF -> frame/phase alignment.\n' ...
    'Interpolate measured forward responses to the legal DAC grid; precompute exact nearest inverse.\n' ...
    'DPD acts on EVERY DAC-rate baseband sample after TX RRC, not on QAM symbols.\n' ...
    'Raw snake bypasses TX RRC only during training. Business TX/RX RRC remain active.\n' ...
    'Original analog TX / LO impairments remain active. No instantaneous jitter is used.']));
a.Position=[20 730 1050 865]; a.FontSize=11;
set_param(s,'Tag','rfdac_dpd_v7');
end
function add(lib,s,name,pos,varargin)
add_block(['simulink/' lib],[s '/' name],'Position',pos,varargin{:});
end
function wire(s,a,b)
add_line(s,a,b,'autorouting','on');
end
