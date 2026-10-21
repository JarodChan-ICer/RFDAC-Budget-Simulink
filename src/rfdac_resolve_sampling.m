function [cfg,info] = rfdac_resolve_sampling(cfg)
%RFDAC_RESOLVE_SAMPLING Keep RF harmonics inside Nyquist when LO is changed.
% Auto mode only raises Fs, in powers of two, and scales both RF FIR orders
% by the same factor. This preserves integer rate ratios and filter duration.
% Calling this again on an already resolved cfg does not scale it again.
if ~isfield(cfg,'Sample_Rate_Auto'), cfg.Sample_Rate_Auto=true; end
validateattributes(cfg.Sample_Rate_Auto,{'logical','numeric'},{'scalar','binary'});
validateattributes(cfg.Sample_Rate,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(cfg.LPF_Cutoff,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(cfg.LPF_Transition_Bandwidth,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(cfg.LPF_Order,{'numeric'},{'scalar','integer','positive','even'});
validateattributes(cfg.RX_LPF_Order,{'numeric'},{'scalar','integer','positive','even'});
edges=[cfg.LO_Frequency+cfg.LPF_Cutoff+cfg.LPF_Transition_Bandwidth/2, ...
    cfg.LO_Frequency+cfg.RX_LO_Frequency+cfg.LPF_Cutoff];
if cfg.TX_Nonlinearity_Enable
    edges(end+1)=3*(cfg.LO_Frequency+cfg.LPF_Cutoff);
end
info.Requested_Sample_Rate=cfg.Sample_Rate;
info.Minimum_Sample_Rate=2*max(edges); % STRICT lower bound
assert(isfinite(info.Minimum_Sample_Rate),'RF frequency settings are too large.');
info.Scale_Factor=1;
if cfg.Sample_Rate<=info.Minimum_Sample_Rate
    if ~cfg.Sample_Rate_Auto
        error('rfdac:InsufficientSampleRate', ...
            ['Sample_Rate %.3g GHz is insufficient for TX LO %.3g GHz / RX LO %.3g GHz. ' ...
             'It must exceed %.3g GHz to resolve RF, receiver sum frequency, and TX third harmonic. ' ...
             'Set cfg.Sample_Rate_Auto=true, or increase Sample_Rate and scale both LPF orders accordingly.'], ...
            cfg.Sample_Rate/1e9,cfg.LO_Frequency/1e9,cfg.RX_LO_Frequency/1e9,info.Minimum_Sample_Rate/1e9);
    end
    while cfg.Sample_Rate*info.Scale_Factor<=info.Minimum_Sample_Rate
        info.Scale_Factor=2*info.Scale_Factor;
    end
    % A previously derived oversampling ratio follows the automatic increase;
    % inconsistent user-specified ratios still fail the subsequent validator.
    if ~isempty(cfg.Oversampling_Ratio) && ...
            abs(cfg.Oversampling_Ratio-cfg.Sample_Rate/cfg.Symbol_Rate)<1e-8
        cfg.Oversampling_Ratio=cfg.Oversampling_Ratio*info.Scale_Factor;
    end
    cfg.Sample_Rate=cfg.Sample_Rate*info.Scale_Factor;
    cfg.LPF_Order=cfg.LPF_Order*info.Scale_Factor;
    cfg.RX_LPF_Order=cfg.RX_LPF_Order*info.Scale_Factor;
    fprintf(['RF sample rate auto-adjusted: %.3g -> %.3g GHz (LO %.3g GHz). ' ...
        'TX/RX FIR orders: %d / %d.\n'],info.Requested_Sample_Rate/1e9,cfg.Sample_Rate/1e9, ...
        cfg.LO_Frequency/1e9,cfg.LPF_Order,cfg.RX_LPF_Order);
end
info.Effective_Sample_Rate=cfg.Sample_Rate;
info.Adjusted=info.Scale_Factor>1;
end
