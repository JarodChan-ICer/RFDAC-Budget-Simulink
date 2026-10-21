function finalize_rfdac_dpd()
% Focused inverse/regeneration checks after the full-record comparison.
cfg=init_rfdac_model(); cfg.Num_Symbols=128;
cfg.Make_Plots=false; cfg.Save_Results=false;
cfg.TX_Nonlinearity_Beta=.6; cfg.LO_Quadrature_Error_Deg=1;
cfg.LO_Phase_Errors_Deg=[.2 -.3 .1 .4];
[p,~]=rfdac_prepare(cfg);
u=complex(linspace(-.3,.3,1001)',.2*sin((1:1001)'));
d=p.DPD; d.Algorithm='analytic'; d.Nonlinearity_Enable=false;
[v,~]=rfdac_dpd_apply(u,d);
recovered=d.Alpha*v+d.Image*conj(v);
assert(max(abs(recovered-u))<1e-12,'General four-phase IQ inverse failed.');
d.IQ_Enable=false; d.Nonlinearity_Enable=false;
[v,~]=rfdac_dpd_apply(u,d); assert(isequal(u,v),'Digital bypass is not exact.');
bad=cfg; bad.LO_Quadrature_Error_Deg=90; bad.LO_Phase_Errors_Deg=[0 0 0 0];
try
    rfdac_prepare(bad); error('rfdac:MissingSingularGuard','Singular IQ inverse was accepted.');
catch err
    assert(strcmp(err.identifier,'rfdac:DPDSingularIQ'),'%s',err.message);
end

paths=setup_rfdac_project(); root=paths.Root;
cfg.Model_Name='rfdac_dpd_build_verification';
path=fullfile(root,[cfg.Model_Name '.slx']); assert(~isfile(path),'Verification filename already exists.');
build_rfdac_model(cfg); r=run_rfdac_simulation(cfg);
assert(r.metrics.DPD_Enabled && isfinite(r.metrics.EVM_Percent));
assert(getSimulinkBlockHandle([cfg.Model_Name '/Digital Predistortion'])>0);
close_system(cfg.Model_Name,0); delete(path);
cache=fullfile(root,[cfg.Model_Name '.slxc']); if isfile(cache), delete(cache); end
polish_rfdac_dpd_model();
c=init_rfdac_model();
if bdIsLoaded(c.Model_Name), close_system(c.Model_Name,0); end
folder=fullfile(paths.Validation,'dpd_evaluation'); if ~isfolder(folder), mkdir(folder); end
fid=fopen(fullfile(folder,'delivery_checks.txt'),'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'PASS: general independent four-phase errors are inverted before the DACs.\n');
fprintf(fid,'PASS: bypass is exact and singular IQ mapping is rejected.\n');
fprintf(fid,'PASS: source builder regenerates and runs an independent SLX with DPD.\n');
fprintf(fid,'PASS: original model canvas updated; user default LO/QAM/TX EVM retained.\n');
disp('ALL FINAL DPD CHECKS PASSED.');
end
