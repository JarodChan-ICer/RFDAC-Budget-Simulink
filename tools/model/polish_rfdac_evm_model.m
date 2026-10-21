function polish_rfdac_evm_model()
% Refresh explanatory labels only; does not change the simulated chain.
c=init_rfdac_model(); m=c.Model_Name; load_system(m);
aa=find_system(m,'SearchDepth',1,'FindAll','on','Type','annotation');
for k=1:numel(aa)
    a=get_param(aa(k),'Object');
    if startsWith(a.Text,'RF-DAC LO JITTER LINK BUDGET')
        a.Text=sprintf(['RF-DAC TX EVM / FOUR-PHASE LO / JITTER | REAL RF\n' ...
            'LO: cfg.LO_Frequency | Clean TX: cfg.TX_Target_EVM_dB | Quadrature: cfg.LO_Quadrature_Error_Deg']);
    elseif startsWith(a.Text,'Physical')
        a.Text=sprintf(['RF sample rate and FIR orders auto-adjust for the selected LO.\n' ...
            'Each solver update processes one symbol frame of consecutive RF samples.\n' ...
            'Full-record EVM/SER/jitter statistics; bounded contiguous waveform previews.']);
    end
end
pp=get_param([m '/Quadrature Mixer'],'PortHandles');
line=get_param(pp.Outport(1),'Line'); if line>0, set_param(line,'Name','RF_before_TX'); end
aa=find_system([m '/Measurements'],'SearchDepth',1,'FindAll','on','Type','annotation');
for k=1:numel(aa)
    a=get_param(aa(k),'Object');
    if startsWith(a.Text,'All physical waveforms')
        a.Text=sprintf(['Full-record symbols and jitter RMS statistics are saved.\n' ...
            'Physical waveforms retain cfg.Waveform_Log_Frames contiguous tail frames.\n' ...
            'Use run_rfdac_simulation / evaluate_24g_tx_budget for EVM, SNDR and plots.']);
    end
end
save_system(m);
paths=setup_rfdac_project(); folder=fullfile(paths.Validation,'tx_evm_24g');
if ~isfolder(folder), mkdir(folder); end
print(['-s' m],'-dpng','-r100',fullfile(folder,'model_overview.png'));
end
