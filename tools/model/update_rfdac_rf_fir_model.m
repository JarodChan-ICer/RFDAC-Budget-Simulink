function update_rfdac_rf_fir_model(model)
% Replace the three RF FIR implementations with equivalent frame overlap-add.
% The caller prepares the base workspace and owns saving the model, if desired.
if ~bdIsLoaded(model), load_system(model); end
load_system('simulink');
replace_fir([model '/Reconstruction LPF/I reconstruction FIR'],'p.TX_FIR',false);
replace_fir([model '/Reconstruction LPF/Q reconstruction FIR'],'p.TX_FIR',false);
replace_fir([model '/Receiver Downconversion/Receiver anti alias LPF'],'p.RX_FIR',true);
end

function replace_fir(block,coefficients,isComplex)
assert(getSimulinkBlockHandle(block)>0,'RF FIR block missing: %s',block);
tag='rfdac_rf_fir_fft';
if strcmp(get_param(block,'Tag'),tag), return; end
assert(strcmp(get_param(block,'BlockType'),'DiscreteFir'), ...
    'Expected the original Discrete FIR Filter at %s.',block);
assert(strcmp(get_param(block,'Coefficients'),coefficients), ...
    'Unexpected FIR numerator at %s.',block);
oldPorts=get_param(block,'PortHandles');
inputLine=get_param(oldPorts.Inport(1),'Line');
outputLine=get_param(oldPorts.Outport(1),'Line');
assert(inputLine>0 && outputLine>0,'RF FIR block is disconnected: %s',block);
source=get_param(inputLine,'SrcPortHandle');
destinations=get_param(outputLine,'DstPortHandle');
destinations=destinations(destinations>0);
assert(source>0 && ~isempty(destinations),'RF FIR has incomplete connections: %s',block);
inputName=get_param(inputLine,'Name'); outputName=get_param(outputLine,'Name');
parent=get_param(block,'Parent'); name=get_param(block,'Name');
newBlock=add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function', ...
    [block ' FFT'],'MakeNameUnique','on','Position',get_param(block,'Position'), ...
    'Orientation',get_param(block,'Orientation'),'FunctionName','rfdac_fir_frame', ...
    'Parameters',sprintf('%s,p.Samples_Per_Symbol,%d',coefficients,isComplex),'Tag',tag);
newPorts=get_param(newBlock,'PortHandles');
if numel(newPorts.Inport)~=1 || numel(newPorts.Outport)~=1
    delete_block(newBlock);
    error('rfdac:FIRFramePorts','Could not initialize the frame FIR ports for %s.',block);
end
delete_line(inputLine); delete_line(outputLine);
newInputLine=add_line(parent,source,newPorts.Inport(1),'autorouting','on');
if ~isempty(inputName), set_param(newInputLine,'Name',inputName); end
for k=1:numel(destinations)
    add_line(parent,newPorts.Outport(1),destinations(k),'autorouting','on');
end
if ~isempty(outputName), set_param(get_param(newPorts.Outport(1),'Line'),'Name',outputName); end
delete_block(block);
set_param(newBlock,'Name',name,'Description', ...
    'Causal overlap-add with the same FIR coefficients and no added frame delay.');
end
