function report=validate_rfdac_link_lut_integration()
% Exercise saved captures, automatic OFF/ON plotting, direct Run, invalidation
% and construction of a fresh model, using a small real training alphabet.
paths=setup_rfdac_project(); c=init_rfdac_model();
c.Num_Symbols=256; c.TX_Nonlinearity_Beta=0.4;
c.DPD_LUT_Training_Order=64; c.DPD_LUT_Training_Repeats=2;
c.Make_Plots=true; c.Figure_Visible='off'; c.Save_Results=true;
c.Output_Directory=fullfile(paths.Validation,'ppt_dpd_20261102');
c.Run_Tag='integration'; c.Waveform_Log_Frames=8;
r=run_rfdac_simulation(c);
assert(isfile(fullfile(c.Output_Directory,'integration_dpd_link_training.mat')));
assert(isfield(r,'DPD_Comparison'));
assert(isnan(r.DPD.Beta) && isnan(r.DPD.Alpha) && isnan(r.DPD.Image));
assignin('base','cfg',r.cfg); direct=sim(c.Model_Name); %#ok<NASGU>

% Oracle parameters are not even validated/read in measured link mode.
changed=r.cfg; changed.DPD_TX_Beta_Estimate=NaN;
changed.DPD_Quadrature_Estimate_Deg=NaN; changed.DPD_Phase_Errors_Estimate_Deg=NaN;
[p,~]=rfdac_prepare(changed);
assert(isequal(p.DPD.LUT.Inverse_Index,r.DPD.LUT.Inverse_Index));
assert(isequal(p.Source_Constellation,r.Reference_Constellation));
assert(~isfield(p.DPD,'Symbol_LUT_Indices'));
probe=complex((-512:511)',(511:-1:-512)')*p.LSB;
[full,limited,index]=rfdac_dpd_lut_lookup(probe,p.DPD);
[small,smallLimited,smallIndex]=rfdac_dpd_lut_lookup(probe,p.DPD_Runtime);
assert(isequal(full,small) && isequal(limited,smallLimited) && isequal(index,smallIndex));

% A changed physical link must reject direct Run and recapture via the runner.
changed.LO_Quadrature_Error_Deg=5; assignin('base','cfg',changed);
try
    rfdac_model_init(); error('rfdac:MissingGuard','Stale training was accepted.');
catch err
    assert(strcmp(err.identifier,'rfdac:LUTTrainingStale'),'%s',err.message);
end
changed.Make_Plots=false; changed.Save_Results=false;
new=run_rfdac_simulation(changed);
assert(new.DPD.LUT.Training_Metadata.Key.LO_Quadrature_Error_Deg==5);
assert(norm(new.DPD.LUT.Training_Output-r.DPD.LUT.Training_Output)>1e-3);
assert(new.TX_Beta==r.TX_Beta);
resized=r.cfg; resized.DPD_LUT_Training_Order=256;
resized.Make_Plots=false; resized.Save_Results=false;
larger=run_rfdac_simulation(resized);
assert(larger.DPD.LUT.Training_Order==256 && numel(larger.cfg.DPD_LUT_Training_Observed)==256);
multiple=c; multiple.QAM_Order=16; multiple.DPD_LUT_Size_Mode='qam_multiple';
multiple.DPD_LUT_Points_Per_QAM_Symbol=4; multiple.Make_Plots=false; multiple.Save_Results=false;
small=run_rfdac_simulation(multiple);
assert(small.DPD.LUT.Training_Order==64 && small.DPD.LUT.Training_Metadata.Training_Order==64);

% Fresh SLX generation must not try to train a half-built model from InitFcn.
fresh=c; fresh.Model_Name='rfdac_link_lut_builder_verification';
fresh.Make_Plots=false; fresh.Save_Results=false;
file=fullfile(paths.Root,[fresh.Model_Name '.slx']);
assert(~isfile(file),'Temporary builder model already exists.');
cleanup=onCleanup(@()remove_fixture(fresh.Model_Name,file));
build_rfdac_model(fresh);
fromBuilder=run_rfdac_simulation(fresh);
assert(strcmp(get_param([fresh.Model_Name '/Digital Predistortion'],'Tag'),'rfdac_dpd_v7'));
assert(isfinite(fromBuilder.metrics.EVM_Percent));
report=struct('All_Passed',true,'Automatic_Comparison',true,'Training_Save',true, ...
    'Direct_Run',true,'Estimate_Independence',true,'Stale_Training_Rejected',true, ...
    'Physical_Change_Retrained',true,'Resized_Alphabet_Retrained',true, ...
    'QAM_Multiple_Mode',true,'Fresh_Builder',true);
save(fullfile(c.Output_Directory,'integration_validation.mat'),'report');
close all; disp(report);
end

function remove_fixture(model,file)
if bdIsLoaded(model), close_system(model,0); end
if isfile(file), delete(file); end
end
