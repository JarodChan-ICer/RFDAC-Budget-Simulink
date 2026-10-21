function report=audit_rfdac_iq_residual()
% Isolate residual IQ error using the actual word-limited Simulink link.
paths=setup_rfdac_project();
saved=load(rfdac_find_result(fullfile('dpd_codewords','jitter_0_results.mat')),'results');
c=saved.results.cfg; c.Make_Plots=false; c.Save_Results=false;
c.TX_Nonlinearity_Enable=false; c.LO_Jitter_Enable=false;
c.DPD_Nonlinearity_Enable=false; c.DPD_IQ_Enable=true;
c.DPD_Quadrature_Estimate_Deg=[]; c.DPD_Phase_Errors_Estimate_Deg=[];
c.LO_Phase_Errors_Deg=[0 0 0 0]; c.LO_Quadrature_Error_Enable=true;
labels={'Ideal quadrature, DPD off','1 degree, DPD off', ...
    '1 degree, exact known estimate, 10-bit DPD','1 degree, 0.9-degree estimate, 10-bit DPD'};
rows={};
for k=1:4
    c.LO_Quadrature_Error_Deg=double(k>1); c.DPD_Enable=k>=3;
    if k==4, c.DPD_Quadrature_Estimate_Deg=.9; end
    r=run_rfdac_simulation(c); m=r.metrics;
    if k==1, reference=r.Received_Symbols; end
    paired=100*norm(r.Received_Symbols-reference)/norm(r.Reference_Symbols);
    rows{k,1}=table(string(labels{k}),m.EVM_Percent,m.EVM_dB,paired, ...
        m.DPD_Output_Quantization_Error_RMS,m.Invalid_Output_Codeword_Pairs, ...
        'VariableNames',{'Case','EVM_Percent','EVM_dB','Paired_Difference_From_Clean_Percent', ...
        'Output_Quantization_RMS_V','Invalid_Codewords'});
end
report.Table=vertcat(rows{:}); report.Config=c;
assert(report.Table.Paired_Difference_From_Clean_Percent(3)>0,'Residual was incorrectly zero.');
assert(report.Table.EVM_Percent(3)<report.Table.EVM_Percent(2));
assert(report.Table.Paired_Difference_From_Clean_Percent(4)>report.Table.Paired_Difference_From_Clean_Percent(3));

% One concrete word-pair demonstrates why exact inversion is impossible.
[p,~]=rfdac_prepare(c); d=p.DPD; d.Algorithm='analytic';
phase=pi/180; d.Alpha=(1+exp(1i*phase))/2; d.Image=(1-exp(1i*phase))/2;
d.Determinant=abs(d.Alpha)^2-abs(d.Image)^2;
[v,ideal]=rfdac_dpd_codewords((100+200i)*d.LSB,d);
report.Example_Input_Codes=[100 200];
report.Example_Ideal_Codes=[real(ideal) imag(ideal)]/d.LSB;
report.Example_Actual_Codes=[real(v) imag(v)]/d.LSB;
y=d.Alpha*v+d.Image*conj(v);
report.Example_Recovered_Codes=[real(y) imag(y)]/d.LSB;
report.Example_Error_Codes=report.Example_Recovered_Codes-report.Example_Input_Codes;
folder=fullfile(paths.Validation,'iq_residual_audit'); if ~isfolder(folder), mkdir(folder); end
writetable(report.Table,fullfile(folder,'iq_residual.csv'));
save(fullfile(folder,'iq_residual.mat'),'report');
disp(report.Table); disp(report); disp('IQ RESIDUAL AUDIT PASSED: FINITE 10-BIT RESIDUAL IS NONZERO.');
bdclose('all');
end
