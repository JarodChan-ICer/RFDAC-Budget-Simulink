function report=validate_rfdac_codeword_plots()
% Validate the real SLX word interface, unchanged plant and plot controls.
paths=setup_rfdac_project(); c=init_rfdac_model();
c.LO_Quadrature_Error_Deg=1; c.Figure_Visible='off';
c.Output_Directory=fullfile(paths.Validation,'dpd_codewords');
if ~isfolder(c.Output_Directory), mkdir(c.Output_Directory); end

% Every physical digital output must belong to the N-bit code lattice.
d=struct('Enabled',true,'IQ_Enable',true,'Nonlinearity_Enable',true, ...
    'Beta',.6,'Alpha',(1+exp(1i*pi/180))/2,'Image',(1-exp(1i*pi/180))/2, ...
    'Max_Gain',2,'LSB',2/1024,'Min_Code',-512,'Max_Code',511);
d.Determinant=abs(d.Alpha)^2-abs(d.Image)^2;
u=complex(linspace(-1.2,1.2,10001)',.4*sin((1:10001)'));
[v,ideal,inputCodes,stats]=rfdac_dpd_codewords(u,d);
assert(all(round(real(v)/d.LSB)>=-512 & round(real(v)/d.LSB)<=511));
assert(all(abs(real(v)/d.LSB-round(real(v)/d.LSB))<1e-12));
assert(stats(10)>0 && any(v~=ideal),'Finite output-word precision was bypassed.');
d.IQ_Enable=false; d.Nonlinearity_Enable=false;
[v,~,sameCodes,~]=rfdac_dpd_codewords(u,d);
assert(isequal(v,inputCodes*d.LSB) && isequal(inputCodes,sameCodes),'Word bypass changed input codes.');

% Main full-length comparison; the runner asserts identical beta and jitter.
for enabled=0:1
    c.LO_Jitter_Enable=logical(enabled); c.Run_Tag=sprintf('jitter_%d',enabled);
    r=run_rfdac_simulation(c);
    m=r.metrics; before=r.DPD_Comparison.Before_Metrics;
    assert(m.Invalid_Output_Codeword_Pairs==0 && m.DPD_Modified_Codeword_Pairs>0);
    assert(m.DPD_Output_Quantization_Error_RMS>0 || m.DPD_LUT_Node_Quantization_RMS_Code>0);
    assert(m.EVM_Percent<before.EVM_Percent,'Word-limited DPD did not improve EVM.');
    assert(m.DPD_DAC_I_Clipped_Full+m.DPD_DAC_Q_Clipped_Full==0);
    w=r.waveforms; k=sqrt(r.TX_Beta);
    assert(max(abs(w.rf_output-atan(k*w.rf_before_gm)/k))<1e-10, ...
        'The original RF nonlinearity was bypassed.');
    row=table(logical(enabled),before.EVM_Percent,m.EVM_Percent,m.EVM_dB, ...
        m.DPD_Output_Quantization_Error_RMS,m.DPD_Modified_Codeword_Pairs, ...
        'VariableNames',{'Jitter_On','Before_EVM_Percent','After_EVM_Percent','After_EVM_dB', ...
        'Output_Word_Quantization_Error_RMS','Modified_Codeword_Pairs'});
    if enabled==0, report.Table=row; else, report.Table=[report.Table;row]; end
end

% Exercise each independent plotting flag without repeating the simulation.
r.cfg.Output_Directory=fullfile(c.Output_Directory,'plot_switch_checks');
fields={'Plot_Constellation','Plot_LPF_Response','Plot_Waveforms','Plot_Spectra','Plot_Diagnostics'};
suffix={'dpd_before_after_constellation','lpf_response','waveforms','spectra','diagnostics'};
for a=1:numel(fields), r.cfg.(fields{a})=false; end
f=plot_rfdac_results(r); assert(isempty(f),'Disabled flags created a figure.');
for a=1:numel(fields)
    r.cfg.(fields{a})=true; r.cfg.Run_Tag=sprintf('flag_%d',a);
    f=plot_rfdac_results(r); assert(numel(f)==1,'Plot flag does not control one figure.');
    assert(isfile(fullfile(r.cfg.Output_Directory,[r.cfg.Run_Tag '_' suffix{a} '.png'])));
    close(f); r.cfg.(fields{a})=false;
end
r.cfg.Make_Plots=false; r.cfg.Plot_Waveforms=true;
assert(isempty(plot_rfdac_results(r)),'Make_Plots master switch failed.');

% All five QAM modes use the same word-only interface.
q=c; q.Make_Plots=false; q.Save_Results=false; q.Num_Symbols=256; q.TX_Nonlinearity_Beta=r.TX_Beta;
for order=[16 64 256 1024 4096]
    q.QAM_Order=order; t=run_rfdac_simulation(q);
    assert(isfinite(t.metrics.EVM_Percent) && t.metrics.Invalid_Output_Codeword_Pairs==0);
end
report.Config=c; report.All_Passed=true;
writetable(report.Table,fullfile(c.Output_Directory,'codeword_comparison.csv'));
save(fullfile(c.Output_Directory,'codeword_validation.mat'),'report');
fid=fopen(fullfile(c.Output_Directory,'validation.txt'),'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'PASS: signed 10-bit input AND output words; quantization and saturation active.\n');
fprintf(fid,'PASS: identical analog TX beta, data seed and jitter for before/after.\n');
fprintf(fid,'PASS: actual RF output still equals the original atan nonlinearity.\n');
fprintf(fid,'PASS: final RX constellation comparisons and independent plot switches.\n');
fprintf(fid,'PASS: all five QAM modes run with the same codeword restrictions.\n');
disp(report.Table); disp('ALL CODEWORD AND FIGURE CHECKS PASSED.');
bdclose('all');
end
