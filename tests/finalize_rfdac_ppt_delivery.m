function report=finalize_rfdac_ppt_delivery()
% Final integration plus actual RF replay of the saved full measured table.
paths=setup_rfdac_project();
folder=fullfile(paths.Validation,'ppt_dpd_20261102');
report.Integration=validate_rfdac_link_lut_integration();
one=load(fullfile(folder,'full_validation.mat'),'report','r');
large=load(fullfile(folder,'full_iq_30_validation.mat'),'report');
assert(one.report.All_Passed && large.report.All_Passed);
c=one.r.cfg; c.Make_Plots=false; c.Save_Results=false;
replayed=run_rfdac_simulation(c);
report.Compact_Runtime_Received_Max_Difference=max(abs(replayed.Received_Symbols-one.r.Received_Symbols));
assert(report.Compact_Runtime_Received_Max_Difference<1e-13, ...
    'Compact runtime changed the actual full-record RF output.');
assert(strcmp(get_param([c.Model_Name '/Digital Predistortion'],'Tag'),'rfdac_dpd_v7'));
report.Full_1_Degree=one.report.After; report.Full_30_Degree=large.report.After;
report.All_Passed=true;
iq=[1;1;30;30];
metrics=[one.report.Before;one.report.After;large.report.Before;large.report.After];
summary=struct2table(metrics); summary.IQ_Error_Deg=iq;
summary.Case={'DPD OFF';'PPT LUT DPD ON';'DPD OFF';'PPT LUT DPD ON'};
writetable(summary,fullfile(folder,'verified_comparison.csv'));
save(fullfile(folder,'final_validation.mat'),'report');
disp(summary(:,{'IQ_Error_Deg','Case','EVM_Percent','EVM_dB','Symbol_Error_Rate'}));
fprintf('PPT FINAL PASS; compact-runtime full-record RX difference %.12g.\n', ...
    report.Compact_Runtime_Received_Max_Difference);
end
