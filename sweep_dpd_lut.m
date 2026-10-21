function report=sweep_dpd_lut(cfg,points)
% Run actual SLX at fixed plant/seed with off, analytic and finite LUT sizes.
setup_rfdac_project();
if nargin<1, cfg=init_rfdac_model(); end
if nargin<2, points=[4096 16384 65536]; end
cfg.Output_Directory=rfdac_output_directory(cfg.Output_Directory);
original=cfg; [p,cfg]=rfdac_prepare(cfg);
cfg.TX_Nonlinearity_Beta=p.TX_Beta; cfg.Make_Plots=false; cfg.Save_Results=false;
folder=fullfile(original.Output_Directory,'lut_sweep');
if ~isfolder(folder), mkdir(folder); end
rows={};
for k=1:numel(points)+2
    c=cfg;
    if k==1, c.DPD_Enable=false; label='DPD off';
    elseif k==2, c.DPD_Enable=true; c.DPD_Algorithm='analytic'; label='Analytic reference';
    else
        c.DPD_Enable=true; c.DPD_Algorithm='lut'; c.DPD_LUT_Size_Mode='total_points';
        c.DPD_LUT_Points=points(k-2); label=sprintf('LUT %d',points(k-2));
    end
    r=run_rfdac_simulation(c); m=r.metrics;
    assert(abs(r.TX_Beta-p.TX_Beta)<1e-12);
    rows{k,1}=table(string(label),m.DPD_LUT_Points,m.DPD_LUT_Value_Bits,m.DPD_LUT_Fraction_Bits, ...
        m.DPD_LUT_Interpolation,m.DPD_LUT_Packed_Payload_Bytes/1024, ...
        m.EVM_Percent,m.EVM_dB,-m.EVM_dB,m.DPD_LUT_Value_Clipped_Nodes, ...
        'VariableNames',{'Case','LUT_Points','Value_Bits','Fraction_Bits','Interpolation', ...
        'Payload_KiB','EVM_Percent','EVM_dB','MER_dB','Table_Clipped_Nodes'});
end
report.Table=vertcat(rows{:}); report.Config=original; report.TX_Beta=p.TX_Beta;
report=rfdac_lut_select_precision(report);
writetable(report.Table,fullfile(folder,'lut_precision_sweep.csv'));
save(fullfile(folder,'lut_precision_sweep.mat'),'report');
f=plot_dpd_lut_sweep(report,folder);
if strcmp(original.Figure_Visible,'off'), close(f); end
disp(report.Table); assignin('base','lut_report',report);
fprintf('Allowed EVM penalty %.3f dB; recommended tested LUT points: %s (configured LUT is unchanged).\n', ...
    report.Config.DPD_LUT_Max_Penalty_dB,mat2str(report.Recommended_Points));
end
