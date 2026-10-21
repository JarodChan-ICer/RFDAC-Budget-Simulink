function report=verify_project_layout()
% Structural regression after reorganizing files; uses actual Simulink runs.
paths=setup_rfdac_project(); original=pwd; cleanup=onCleanup(@()cd(original));
cfg=init_rfdac_model();
assert(strcmp(cfg.Output_Directory,paths.Results));
assert(strcmp(rfdac_output_directory(fullfile(paths.Root,'results')),paths.Results));
% A fresh Git clone deliberately has no historical outputs or archives.
fixtureFolder=fullfile(paths.Validation,'project_layout');
if ~isfolder(fixtureFolder), mkdir(fixtureFolder); end
fixture=fullfile(fixtureFolder,'result_lookup_fixture.txt');
assert(~isfile(fixture),'Result-lookup fixture already exists.');
fid=fopen(fixture,'w'); assert(fid>=0); fprintf(fid,'lookup fixture\n'); fclose(fid);
assert(strcmp(rfdac_find_result(fullfile('project_layout','result_lookup_fixture.txt')),fixture));
delete(fixture);
assert(~contains(path,fullfile(paths.Root,'archive')),'Archive code was added to path.');

% Open by absolute filename from another directory, with only root on path.
model=cfg.Model_Name; if bdIsLoaded(model), close_system(model,0); end
load_system(fullfile(paths.Root,[model '.slx']));
set_param(model,'PostLoadFcn',sprintf('addpath(fileparts(get_param(''%s'',''FileName''))); setup_rfdac_project;',model));
save_system(model); close_system(model,0);
parts={paths.Source,paths.Tools,paths.Tests};
for k=1:numel(parts), rmpath(parts{k}); end
cd(paths.Logs); load_system(fullfile(paths.Root,[model '.slx']));
assert(~isempty(which('rfdac_model_init')) && ~isempty(which('update_rfdac_dpd_model')));
cfg.Num_Symbols=512; cfg.Make_Plots=true; cfg.Figure_Visible='off';
cfg.Save_Results=true; cfg.Run_Tag='layout_smoke';
cfg.Output_Directory=fullfile(paths.Validation,'project_layout');
r=run_rfdac_simulation(cfg);
assert(isfinite(r.metrics.EVM_Percent) && r.metrics.Invalid_Output_Codeword_Pairs==0);
assert(isfile(fullfile(cfg.Output_Directory,'layout_smoke_results.mat')));
assert(isfile(fullfile(cfg.Output_Directory,'layout_smoke_dpd_before_after_constellation.png')));
assignin('base','cfg',r.cfg); direct=sim(model); %#ok<NASGU>
close_system(model,0);

% The source builder must keep new model files in root, not tools/model.
cfg.Num_Symbols=64; cfg.Make_Plots=false; cfg.Save_Results=false;
cfg.Model_Name='rfdac_layout_build_verification';
temporary=fullfile(paths.Root,[cfg.Model_Name '.slx']);
assert(~isfile(temporary),'Temporary verification model already exists.');
build_rfdac_model(cfg); b=run_rfdac_simulation(cfg);
assert(isfile(temporary) && isfinite(b.metrics.EVM_Percent));
close_system(cfg.Model_Name,0); delete(temporary);
assert(~isfolder(fullfile(paths.Root,'slprj')));
assert(~isfile(fullfile(paths.Root,[model '.slxc'])));
report=struct('All_Passed',true,'EVM_Percent',r.metrics.EVM_Percent, ...
    'Runtime_Function',which('rfdac_dpd_block'),'Results_Directory',paths.Results, ...
    'Cache_Directory',paths.Cache,'Direct_Model_Simulation',true,'Builder_Verified',true);
save(fullfile(paths.Validation,'project_layout','verification.mat'),'report');
fid=fopen(fullfile(paths.Validation,'project_layout','verification.txt'),'w'); fileCleanup=onCleanup(@()fclose(fid));
fprintf(fid,'PASS: root-only entrypoints; source/tools auto-load when model opens from another working directory.\n');
fprintf(fid,'PASS: actual paired DPD simulation, plotting, and direct sim(model).\n');
fprintf(fid,'PASS: builder saves to root; generated caches stay under outputs/cache.\n');
fprintf(fid,'PASS: archived result lookup and redirect of legacy output directories.\n');
disp(report); disp('PROJECT LAYOUT VERIFICATION PASSED.');
end
