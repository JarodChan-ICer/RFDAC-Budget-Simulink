function rfdac_model_init()
% Model InitFcn: direct Run button and scripted runs use the same cfg.
if evalin('base','exist(''cfg'',''var'')')
    cfg=evalin('base','cfg');
else
    cfg=init_rfdac_model();
end
[p,cfg]=rfdac_prepare(cfg);
assignin('base','cfg',cfg);
assignin('base','p',p);
end
