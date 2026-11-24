function update_rfdac_evm_model(m)
% Update the two changed subsystems, retaining other user blocks and layout.
if nargin<1, c=init_rfdac_model(); m=c.Model_Name; end
load_system(m);
old=[m '/Gm Nonlinearity']; tx=[m '/TX EVM Nonlinearity'];
if getSimulinkBlockHandle(old)>0, set_param(old,'Name','TX EVM Nonlinearity'); end
assert(getSimulinkBlockHandle(tx)>0,'TX nonlinearity subsystem missing.');
clearinside(tx);
add('Math Operations/Gain',tx,'Fitted input scale',[130 65 260 110],'Gain','p.TX_K');
add('Math Operations/Trigonometric Function',tx,'Monotonic atan soft compression',[320 65 475 110],'Operator','atan');
add('Math Operations/Gain',tx,'Restore small signal gain',[545 65 690 110],'Gain','1/p.TX_K');
wire(tx,'RF input/1','Fitted input scale/1');
wire(tx,'Fitted input scale/1','Monotonic atan soft compression/1');
wire(tx,'Monotonic atan soft compression/1','Restore small signal gain/1');
wire(tx,'Restore small signal gain/1','RF output/1');
tap(tx,'Restore small signal gain/1','rf_output',[725 210 895 235]);
annotation(tx,['y = atan(sqrt(beta)*x)/sqrt(beta), beta >= 0; beta=0 gives a linear TX.\n' ...
    'Beta is fitted to cfg.TX_Target_EVM_dB on the complete clean-TX record.\n' ...
    'Calibration includes DAC/FIR errors; jitter OFF and ideal quadrature.\n' ...
    'One EVM value fixes strength within this model family, not unique hardware behavior.'],[25 300 1070 405]);

s=[m '/Jittered LO']; clearinside(s);
add('User-Defined Functions/Level-2 MATLAB S-Function',s,'Streaming TX RX timing jitter',[30 70 245 220], ...
    'FunctionName','rfdac_lo_stream','Parameters','cfg,p.Samples_Per_Symbol');
for k=1:4
    yy=25+(k-1)*105;
    add('Math Operations/Bias',s,['Phase offset ' num2str(k)],[310 yy 440 yy+35], ...
        'Bias',sprintf('p.LO_Phase_Offsets(%d)',k));
    add('Math Operations/Trigonometric Function',s,['LO phase ' num2str(k)],[490 yy 560 yy+35],'Operator','cos');
    wire(s,'Streaming TX RX timing jitter/1',['Phase offset ' num2str(k) '/1']);
    wire(s,['Phase offset ' num2str(k) '/1'],['LO phase ' num2str(k) '/1']);
    tap(s,['LO phase ' num2str(k) '/1'],['lo_' num2str((k-1)*90)],[650 yy+45 780 yy+65]);
end
add('Math Operations/Sum',s,'I differential pair',[845 55 885 100],'Inputs','+-');
add('Math Operations/Sum',s,'Q differential pair',[845 245 885 290],'Inputs','+-');
add('Math Operations/Gain',s,'Normalize I',[945 55 1015 100],'Gain','0.5');
add('Math Operations/Gain',s,'Normalize Q',[945 245 1015 290],'Gain','0.5');
set_param([s '/LO I'],'Position',[1095 65 1125 85]);
set_param([s '/LO Q'],'Position',[1095 255 1125 275]);
wire(s,'LO phase 1/1','I differential pair/1'); wire(s,'LO phase 3/1','I differential pair/2');
wire(s,'LO phase 4/1','Q differential pair/1'); wire(s,'LO phase 2/1','Q differential pair/2');
wire(s,'I differential pair/1','Normalize I/1'); wire(s,'Q differential pair/1','Normalize Q/1');
wire(s,'Normalize I/1','LO I/1'); wire(s,'Normalize Q/1','LO Q/1');
tap(s,'Normalize I/1','lo_i',[1070 140 1210 160]);
tap(s,'Normalize Q/1','lo_q',[1070 330 1210 350]);
tap(s,'Streaming TX RX timing jitter/2','rx_phase',[280 500 430 520]);
tap(s,'Streaming TX RX timing jitter/3','lo_phase_error',[280 560 450 580]);
tap(s,'Streaming TX RX timing jitter/4','rx_phase_error',[510 500 680 520]);
tap(s,'Streaming TX RX timing jitter/5','lo_statistics',[510 560 680 580]);
annotation(s,['Four sinusoidal phases: 0, 90+epsilon, 180, 270+epsilon degrees.\n' ...
    'Differential I=(LO0-LO180)/2, Q=(LO270-LO90)/2.\n' ...
    'epsilon=1 degree means 91-degree I/Q separation; opposite legs stay 180 degrees apart.\n' ...
    'Common timing jitter is generated per RF sample, with bounded frame memory.'],[30 660 1180 760]);

s=[m '/Receiver Downconversion'];
if strcmp(get_param([s '/RX phase'],'BlockType'),'FromWorkspace')
    pos=get_param([s '/RX phase'],'Position');
    ports=get_param([s '/RX phase'],'PortHandles'); oldline=get_param(ports.Outport(1),'Line');
    if oldline>0, delete_line(oldline); end
    delete_block([s '/RX phase']);
    add('Signal Routing/From',s,'RX phase',pos,'GotoTag','rfdac_rx_phase');
    wire(s,'RX phase/1','RX cosine/1'); wire(s,'RX phase/1','RX sine/1');
end

s=[m '/Measurements'];
names={'lo_0','lo_90','lo_180','lo_270','rx_phase_error','lo_statistics'};
for k=1:numel(names)
    y=40+(k-1)*85;
    add('Signal Routing/From',s,['Read ' names{k}],[1410 y 1565 y+25],'GotoTag',['rfdac_' names{k}]);
    add('Sinks/To Workspace',s,['Save ' names{k}],[1620 y-5 1810 y+30], ...
        'VariableName',['log_' names{k}],'SaveFormat','Structure With Time','MaxDataPoints','inf');
    wire(s,['Read ' names{k} '/1'],['Save ' names{k} '/1']);
end
logs=find_system(s,'SearchDepth',1,'BlockType','ToWorkspace');
for k=1:numel(logs)
    v=get_param(logs{k},'VariableName');
    if ismember(v,{'log_rx_symbol','log_online_decisions','log_online_symbols','log_lo_statistics'})
        set_param(logs{k},'MaxDataPoints','inf');
    else
        set_param(logs{k},'MaxDataPoints','cfg.Waveform_Log_Frames');
    end
end
set_param(tx,'Tag','rfdac_evm_v2');
update_rfdac_lo_amplitude_model(m);
set_param(m,'Description','RF TX target-EVM calibration, four-phase LO phase and amplitude imbalance, and timing jitter.');
save_system(m);
fprintf('Updated SLX: target-EVM TX, four-phase LO, streaming jitter and bounded waveform previews.\n');
end
function clearinside(s)
lines=find_system(s,'SearchDepth',1,'FindAll','on','Type','line');
for k=1:numel(lines)
    try, get_param(lines(k),'Handle'); catch, continue; end
    delete_line(lines(k));
end
blocks=find_system(s,'SearchDepth',1,'Type','Block');
for k=2:numel(blocks)
    if ~ismember(get_param(blocks{k},'BlockType'),{'Inport','Outport'}), delete_block(blocks{k}); end
end
aa=find_system(s,'SearchDepth',1,'FindAll','on','Type','annotation');
for k=1:numel(aa), delete(get_param(aa(k),'Object')); end
end
function add(lib,s,n,pos,varargin)
add_block(['simulink/' lib],[s '/' n],'Position',pos,varargin{:});
end
function wire(s,a,b)
add_line(s,a,b,'autorouting','on');
end
function tap(s,a,tag,pos)
add('Signal Routing/Goto',s,['Log ' tag],pos,'GotoTag',['rfdac_' tag],'TagVisibility','global');
wire(s,a,['Log ' tag '/1']);
end
function annotation(s,t,pos)
a=Simulink.Annotation(s,sprintf(t)); a.Position=pos; a.FontSize=11;
end
