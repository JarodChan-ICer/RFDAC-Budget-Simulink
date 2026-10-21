% Quick developer smoke test; full validation is validate_rfdac_model.
build_rfdac_model;
cfg=init_rfdac_model; cfg.Num_Symbols=64; cfg.Make_Plots=false; cfg.Save_Results=false;
assignin('base','cfg',cfg);
out=sim(cfg.Model_Name);
disp(out);
disp(size(out.log_rx_symbol.signals.values));
disp(size(out.log_dac_i.signals.values));
disp(size(out.log_input_i.signals.values));
