function rfdac_upgrade_ppt_source(m)
% Raw training-code injection and a coherent pre-matched-filter observation.
s=[m '/QAM Source']; raw=[s '/Raw training frames'];
if getSimulinkBlockHandle(raw)<0
    add_block('simulink/Sources/From Workspace',raw,'Position',[420 525 630 565], ...
        'VariableName','p.Raw_DAC_Data','SampleTime','p.Frame_Period', ...
        'Interpolate','off','OutputAfterFinalValue','Holding final value');
    add_block('simulink/Sources/Constant',[s '/Raw training enabled'], ...
        'Position',[660 530 800 565],'Value','double(p.Raw_Training_Enable)');
    add_block('simulink/Signal Routing/Switch',[s '/Training waveform selector'], ...
        'Position',[810 65 865 145],'Threshold','0.5','Criteria','u2 >= Threshold');
    pp=get_param([s '/I Q split'],'PortHandles'); line=get_param(pp.Inport(1),'Line');
    if line>0, delete_line(line); end
    set_param([s '/I Q split'],'Position',[920 65 965 115]);
    add_line(s,'Raw training frames/1','Training waveform selector/1','autorouting','on');
    add_line(s,'Raw training enabled/1','Training waveform selector/2','autorouting','on');
    add_line(s,'TX RRC pulse shaping/1','Training waveform selector/3','autorouting','on');
    add_line(s,'Training waveform selector/1','I Q split/1','autorouting','on');
end
rx=[m '/Receiver Downconversion']; tag='rx_envelope';
if getSimulinkBlockHandle([rx '/Log rx_envelope'])<0
    add_block('simulink/Signal Routing/Goto',[rx '/Log rx_envelope'], ...
        'Position',[850 340 1050 370],'GotoTag',['rfdac_' tag],'TagVisibility','global');
    add_line(rx,'Decimate to DAC rate/1','Log rx_envelope/1','autorouting','on');
    meas=[m '/Measurements'];
    add_block('simulink/Signal Routing/From',[meas '/Read rx_envelope'], ...
        'Position',[1410 1350 1565 1380],'GotoTag',['rfdac_' tag]);
    add_block('simulink/Sinks/To Workspace',[meas '/Save rx_envelope'], ...
        'Position',[1620 1345 1810 1385],'VariableName','log_rx_envelope', ...
        'SaveFormat','Structure With Time','MaxDataPoints','p.Observation_Log_Frames');
    add_line(meas,'Read rx_envelope/1','Save rx_envelope/1','autorouting','on');
end
end
