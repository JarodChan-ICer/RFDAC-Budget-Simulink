function rfdac_model_init()
% Model InitFcn: direct Run button and scripted runs use the same cfg.
if evalin('base','exist(''cfg'',''var'')')
    cfg=evalin('base','cfg');
else
    cfg=init_rfdac_model();
end
[p,cfg]=rfdac_prepare(cfg);
if strcmp(p.DPD.Algorithm,'lut') && p.DPD.Enabled && ...
        (p.DPD.IQ_Enable || p.DPD.Nonlinearity_Enable) && strcmp(cfg.DPD_LUT_Training_Mode,'link')
    assert(~isempty(p.DPD.LUT.Training_Output),'rfdac:LUTTrainingRequired', ...
        'Run run_rfdac_simulation(cfg) once to capture the actual training link before pressing Run in Simulink.');
    meta=cfg.DPD_LUT_Training_Metadata;
    assert(~isfield(meta,'Key') || isequal(meta.Key,rfdac_lut_training_key(cfg,p)), ...
        'rfdac:LUTTrainingStale','Physical link changed. Run run_rfdac_simulation(cfg) to retrain.');
end
assignin('base','cfg',cfg);
assignin('base','p',p);
end
