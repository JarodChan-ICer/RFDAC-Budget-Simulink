function update_rfdac_lo_amplitude_model(model)
% Insert per-leg amplitude gains ahead of the differential LO sums and taps.
% The caller owns saving the SLX. Reloading the final model is idempotent.
if nargin<1, cfg=init_rfdac_model(); model=cfg.Model_Name; end
if ~bdIsLoaded(model), load_system(model); end
subsystem=[model '/Jittered LO'];
for leg=1:4
    cosine=[subsystem '/LO phase ' num2str(leg)];
    gain=[subsystem '/LO amplitude ' num2str(leg)];
    assert(getSimulinkBlockHandle(cosine)>0,'Four-phase LO cosine block missing: %s',cosine);
    coefficient=sprintf('p.LO_Leg_Amplitudes(%d)',leg);
    if getSimulinkBlockHandle(gain)>0
        assert(strcmp(get_param(gain,'Tag'),'rfdac_lo_leg_amplitude_v1'), ...
            'Unrelated block at LO amplitude location: %s',gain);
        if ~strcmp(get_param(gain,'Gain'),coefficient), set_param(gain,'Gain',coefficient); end
        continue;
    end
    cosinePorts=get_param(cosine,'PortHandles');
    source=cosinePorts.Outport(1);
    originalLine=get_param(source,'Line');
    assert(originalLine>0,'LO cosine is disconnected: %s',cosine);
    destinations=get_param(originalLine,'DstPortHandle');
    destinations=destinations(destinations>0);
    assert(~isempty(destinations),'LO cosine has no destinations: %s',cosine);
    signalName=get_param(originalLine,'Name');
    position=get_param(cosine,'Position');
    add_block('simulink/Math Operations/Gain',gain, ...
        'Position',[position(3)+50 position(2) position(3)+200 position(4)], ...
        'Gain',coefficient,'Tag','rfdac_lo_leg_amplitude_v1');
    gainPorts=get_param(gain,'PortHandles');
    delete_line(originalLine);
    add_line(subsystem,source,gainPorts.Inport(1),'autorouting','on');
    for k=1:numel(destinations)
        add_line(subsystem,gainPorts.Outport(1),destinations(k),'autorouting','on');
    end
    if ~isempty(signalName), set_param(get_param(gainPorts.Outport(1),'Line'),'Name',signalName); end
end

annotations=find_system(subsystem,'SearchDepth',1,'FindAll','on','Type','annotation');
for k=1:numel(annotations)
    annotation=get_param(annotations(k),'Object');
    if startsWith(annotation.Text,'Four sinusoidal phases:')
        annotation.Text=sprintf(['Phase offsets (degrees): 0, 90+Mp, 180+Md, 270+Mp+Md.\n' ...
            'Normalized leg amplitudes: 1, 1+MA, 1, 1+MA.\n' ...
            'Differential I=(LO0-LO180)/2 and Q=(LO270-LO90)/2.\n' ...
            'Common timing jitter is generated per RF sample.']);
    end
end

hook=get_param(model,'PostLoadFcn');
if ~contains(hook,'update_rfdac_lo_amplitude_model')
    hook=sprintf('%s\nupdate_rfdac_lo_amplitude_model(''%s'');',hook,model);
    set_param(model,'PostLoadFcn',hook);
end
end
