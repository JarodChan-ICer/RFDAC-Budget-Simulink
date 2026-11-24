function meta=rfdac_public_identification_metadata(cfg,p)
% Explicit whitelist: nominal calibrated linear paths, clocks, known pilots.
% This adapter runs at simulator boundary; hidden nonlinear/IQ values omitted.
meta.RF_Sample_Rate=cfg.Sample_Rate;
meta.DAC_Sample_Rate=cfg.DAC_Sample_Rate;
meta.LO_Frequency=cfg.LO_Frequency;
meta.DAC_LSB=p.LSB;
meta.TX_FIR=p.TX_FIR; meta.RX_FIR=p.RX_FIR;
meta.RX_Equalizer_FIR=p.RX_Equalizer_FIR;
meta.TX_RRC=p.RRC; meta.RX_RRC=p.RX_RRC;
meta.Fractional_FIR=p.Fractional_FIR;
meta.DAC_Hold=p.DAC_Hold;
meta.DAC_Samples_Per_Symbol=p.DAC_Samples_Per_Symbol;
meta.Total_Delay=p.Total_Delay;
meta.Reference_Symbols=p.Reference;
meta.Reference_Amplitude=cfg.Input_Amplitude;
meta.Num_Frames=p.Num_Frames;
meta.Min_Code=p.Min_Code; meta.Max_Code=p.Max_Code;
meta.Known_Jitter_RMS_s=cfg.LO_RMS_Jitter;
meta.Jitter_Mode=cfg.Jitter_Mode;
meta.Jitter_Bandwidth=cfg.Jitter_Bandwidth;
end
