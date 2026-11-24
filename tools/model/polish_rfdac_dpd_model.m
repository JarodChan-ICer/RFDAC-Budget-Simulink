function polish_rfdac_dpd_model()
% Explain the new digital calibration in the model canvas; no plant changes.
c=init_rfdac_model(); m=c.Model_Name; load_system(m);
aa=find_system(m,'SearchDepth',1,'FindAll','on','Type','annotation');
for k=1:numel(aa)
    a=get_param(aa(k),'Object');
    if startsWith(a.Text,'RF-DAC')
        a.Text=sprintf(['RF-DAC TX WITH DIGITAL IQ / NONLINEAR PREDISTORTION | REAL RF\n' ...
            'cfg.DPD_Enable | DPD before DACs | Same impaired analog TX and LO']);
    elseif startsWith(a.Text,'RF sample') || startsWith(a.Text,'Physical')
        a.Text=sprintf(['Measured 2D LUT: zero-prefixed snake, frame/phase alignment, forward interpolation and nearest inverse.\n' ...
            'Random timing jitter remains active and is never read by DPD.\n' ...
            'Compare evaluate_rfdac_dpd for deterministic calibration and jitter-limited performance.']);
    end
end
save_system(m);
paths=setup_rfdac_project(); folder=fullfile(paths.Validation,'dpd_evaluation');
if ~isfolder(folder), mkdir(folder); end
print(['-s' m],'-dpng','-r100',fullfile(folder,'model_with_dpd.png'));
end
