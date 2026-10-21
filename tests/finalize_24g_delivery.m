function finalize_24g_delivery()
% Final checks for model generation and saved presentation artifacts.
validate_rfdac_sampling_fix();
polish_rfdac_evm_model();
paths=setup_rfdac_project(); root=paths.Root;
folder=fullfile(paths.Validation,'tx_evm_24g'); if ~isfolder(folder), mkdir(folder); end
for k=[2 7]
    saved=load(rfdac_find_result(fullfile('tx_evm_24g',sprintf('case_%d_results.mat',k))),'results');
    saved.results.cfg.Figure_Visible='off'; saved.results.cfg.Output_Directory=folder;
    plot_rfdac_results(saved.results);
end
cfg=init_rfdac_model(); cfg.Num_Symbols=128;
cfg.Make_Plots=false; cfg.Save_Results=false;
cfg.Model_Name='rfdac_evm_build_verification';
path=fullfile(root,[cfg.Model_Name '.slx']);
assert(~isfile(path),'Temporary verification filename already exists.');
build_rfdac_model(cfg);
r=run_rfdac_simulation(cfg);
assert(isfinite(r.metrics.EVM_Percent));
assert(max(abs(r.LO_Phase_Offsets_Deg-[0 91 180 271]))<1e-10);
close_system(cfg.Model_Name,0); delete(path);
cache=fullfile(root,[cfg.Model_Name '.slxc']); if isfile(cache), delete(cache); end
cfg=init_rfdac_model();
if bdIsLoaded(cfg.Model_Name), close_system(cfg.Model_Name,0); end
fid=fopen(fullfile(folder,'delivery_checks.txt'),'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'PASS: auto/manual sampling identical; manual alias guard retained.\n');
fprintf(fid,'PASS: source builder regenerated an independent SLX and its simulation ran.\n');
fprintf(fid,'PASS: four physical LO phase offsets are [0 91 180 271] degrees.\n');
fprintf(fid,'PASS: saved full-record results re-rendered and model overview generated.\n');
disp('ALL FINAL DELIVERY CHECKS PASSED.');
end
