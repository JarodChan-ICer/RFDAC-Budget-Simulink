function report=validate_rfdac_sampling_fix()
% Focused automatic-vs-manual sampling regression for the current LO.
cfg=init_rfdac_model(); cfg.Num_Symbols=512;
cfg.Make_Plots=false; cfg.Save_Results=false;
a=run_rfdac_simulation(cfg);
manual=a.cfg; manual.Sample_Rate_Auto=false;
b=run_rfdac_simulation(manual);
assert(isequal(a.Received_Symbols,b.Received_Symbols),'Automatic/manual sampling differ.');
assert(a.cfg.Sample_Rate>a.sampling.Minimum_Sample_Rate);
[p,resolved]=rfdac_prepare(a.cfg);
assert(resolved.Sample_Rate==a.cfg.Sample_Rate && p.Sampling.Scale_Factor==1);
manual.Sample_Rate=a.sampling.Minimum_Sample_Rate/2;
manual.Oversampling_Ratio=[];
try
    rfdac_prepare(manual);
    error('rfdac:MissingGuard','Manual undersampling was accepted.');
catch err
    assert(strcmp(err.identifier,'rfdac:InsufficientSampleRate'),'%s',err.message);
end
report=struct('All_Passed',true,'Effective_Sample_Rate',a.cfg.Sample_Rate, ...
    'Minimum_Sample_Rate',a.sampling.Minimum_Sample_Rate,'Auto_Equals_Manual',true);
disp(report);
end
