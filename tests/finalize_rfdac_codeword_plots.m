function finalize_rfdac_codeword_plots()
% Re-render saved receiver data and verify the builder after word upgrade.
paths=setup_rfdac_project(); folder=fullfile(paths.Validation,'dpd_codewords');
if ~isfolder(folder), mkdir(folder); end
for clock=0:1
    data=load(rfdac_find_result(fullfile('dpd_codewords',sprintf('jitter_%d_results.mat',clock))),'results');
    r=data.results; r.cfg.Output_Directory=folder; plot_rfdac_results(r);
end
fields={'Plot_Constellation','Plot_LPF_Response','Plot_Waveforms','Plot_Spectra','Plot_Diagnostics'};
r.cfg.Output_Directory=fullfile(folder,'plot_switch_checks');
for k=1:numel(fields), r.cfg.(fields{k})=false; end
assert(isempty(plot_rfdac_results(r)));
for k=1:numel(fields)
    r.cfg.(fields{k})=true; r.cfg.Run_Tag=sprintf('flag_%d',k);
    f=plot_rfdac_results(r); assert(isscalar(f)); close(f); r.cfg.(fields{k})=false;
end
data=load(rfdac_find_result(fullfile('dpd_codewords','jitter_1_results.mat')),'results');
saved=load(rfdac_find_result(fullfile('dpd_codewords','codeword_validation.mat')),'report');
report=saved.report; report.Config=data.results.cfg;
save(fullfile(folder,'codeword_validation.mat'),'report');
finalize_rfdac_dpd();
disp('ALL WORD-INTERFACE BUILD AND FIGURE DELIVERY CHECKS PASSED.');
end
