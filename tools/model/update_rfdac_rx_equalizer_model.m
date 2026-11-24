function update_rfdac_rx_equalizer_model(m)
%UPDATE_RFDAC_RX_EQUALIZER_MODEL Insert the fitted DAC-rate receive FIR.
% This idempotent upgrade changes only the affected receiver connection.
% The caller saves the model; opening a saved model never writes its SLX.
if nargin<1, c=init_rfdac_model(); m=c.Model_Name; end
if ~bdIsLoaded(m), load_system(m); end
s=[m '/Receiver Downconversion'];
eq=[s '/Auto-fitted in-band equalizer'];
dec=[s '/Decimate to DAC rate']; match=[s '/RRC matched filter'];
assert(getSimulinkBlockHandle(dec)>0 && getSimulinkBlockHandle(match)>0, ...
    'Receiver DAC-rate decimator and matched filter are required.');

if getSimulinkBlockHandle(eq)<0
    % Create room between the existing blocks, retaining their vertical
    % placement and all user branches elsewhere in the receiver.
    left=get_param(dec,'Position'); right=get_param(match,'Position');
    shift=max(0,left(3)+290-right(1));
    blocks=find_system(s,'SearchDepth',1,'Type','Block');
    for k=2:numel(blocks)
        pos=get_param(blocks{k},'Position');
        if pos(1)>=right(1)
            set_param(blocks{k},'Position',pos+[shift 0 shift 0]);
        end
    end
    y=right(2);
    add_block('simulink/Discrete/Discrete FIR Filter',eq, ...
        'Position',[left(3)+45 y left(3)+245 y+55], ...
        'Coefficients','p.RX_Equalizer_FIR', ...
        'InputProcessing','Columns as channels (frame based)', ...
        'Tag','rfdac_rx_equalizer_v1','BackgroundColor','green');
else
    assert(strcmp(get_param(eq,'Tag'),'rfdac_rx_equalizer_v1'), ...
        'An unrelated block named Auto-fitted in-band equalizer already exists.');
    set_param(eq,'Coefficients','p.RX_Equalizer_FIR', ...
        'InputProcessing','Columns as channels (frame based)');
end

connect(s,dec,eq);
connect(s,eq,match);
set_param(eq,'Description',sprintf(['Causal FIR fitted automatically to the configured TX/RX LPF responses.\n' ...
    'Runs at DAC_Sample_Rate before the RRC matched filter.\n' ...
    'cfg.RX_Equalizer_Enable=false selects the unity coefficient.\n' ...
    'Its known FIR delay is included in receive symbol/reference timing.']));

% Keep direct model opens on the same schema as scripted simulations.
hook=get_param(m,'PostLoadFcn');
if ~contains(hook,'update_rfdac_rx_equalizer_model')
    hook=sprintf('%s\nupdate_rfdac_rx_equalizer_model(''%s'');',hook,m);
    set_param(m,'PostLoadFcn',hook);
end
end

function connect(s,source,destination)
src=get_param(source,'PortHandles'); dst=get_param(destination,'PortHandles');
line=get_param(dst.Inport(1),'Line');
if line>0
    if get_param(line,'SrcPortHandle')==src.Outport(1), return; end
    % The input line handle is the destination's branch, preserving other
    % consumers of the old source when reconnecting this one input.
    delete_line(line);
end
add_line(s,src.Outport(1),dst.Inport(1),'autorouting','on');
end
