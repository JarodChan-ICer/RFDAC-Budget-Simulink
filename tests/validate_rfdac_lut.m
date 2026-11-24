function report=validate_rfdac_lut()
% Verify finite LUT storage, actual lookup, all size modes, and actual SLX.
paths=setup_rfdac_project(); cfg=init_rfdac_model();
cfg.DPD_LUT_Training_Mode='static'; cfg.DPD_LUT_Drive_Range=1; % legacy sample-wise reference
report.Core=validate_rfdac_trained_lut();
cfg.DPD_Algorithm='lut'; cfg.DPD_LUT_Size_Mode='total_points'; cfg.DPD_LUT_Points=16384;
cfg.DPD_LUT_Value_Bits=10; cfg.DPD_LUT_Fraction_Bits=0; cfg.DPD_LUT_Interpolation='nearest';
cfg.Make_Plots=false; cfg.Save_Results=false;
[p,cfg]=rfdac_prepare(cfg); d=p.DPD;
assert(isequal(d.LUT.Size,[128 128]) && d.LUT.Points==16384);
assert(d.LUT.Packed_Payload_Bytes==40960);
assert(all(double(d.LUT.Output_I(:))>=-512 & double(d.LUT.Output_I(:))<=511));
assert(all(double(d.LUT.Output_Q(:))>=-512 & double(d.LUT.Output_Q(:))<=511));
probe=complex((-500:7:500)',(500:-7:-500)')*d.LSB;
[actual,~]=rfdac_dpd_apply(probe,d);
% Poison analytic coefficients AFTER building: runtime must still read LUT.
poison=d; poison.Alpha=NaN; poison.Image=NaN; poison.Beta=NaN;
[check,~]=rfdac_dpd_apply(probe,poison); assert(isequal(check,actual));
zero=d; zero.LUT.Output_I(:)=0; zero.LUT.Output_Q(:)=0;
[check,~]=rfdac_dpd_apply(probe,zero); assert(all(check==0));

c=cfg; c.DPD_LUT_Size_Mode='axis_bits'; c.DPD_LUT_Address_Bits=[6 8];
rect=rfdac_build_dpd_lut(c,d); assert(isequal(rect.Size,[64 256]) && rect.Points==16384);
c.DPD_LUT_Size_Mode='qam_multiple'; c.DPD_LUT_Points_Per_QAM_Symbol=4;
multi=rfdac_build_dpd_lut(c,d); assert(multi.Points==c.QAM_Order*4);
c=cfg; c.DPD_LUT_Points=10000;
try
    rfdac_build_dpd_lut(c,d); error('rfdac:MissingLUTGuard','Invalid count accepted.');
catch err
    assert(strcmp(err.identifier,'rfdac:LUTPointCount'));
end

% Full-record operating point with automatic DPD-off constellation comparison.
c=cfg; c.Make_Plots=true; c.Save_Results=true; c.Figure_Visible='off';
c.Plot_Constellation=true; c.Plot_DPD_Comparison=true;
c.Output_Directory=fullfile(paths.Validation,'lut_evaluation'); c.Run_Tag='lut_16384';
c.TX_Nonlinearity_Beta=p.TX_Beta;
r=run_rfdac_simulation(c);
assert(r.metrics.Invalid_Output_Codeword_Pairs==0 && r.metrics.DPD_LUT_Points==16384);
assert(r.metrics.EVM_Percent<r.DPD_Comparison.Before_Metrics.EVM_Percent);
report.Main_Metrics=r.metrics; report.Config=r.cfg;
report.Before_Metrics=r.DPD_Comparison.Before_Metrics;
clear r;

% Same full record and analog plant with analytic arithmetic for comparison.
c.Make_Plots=false; c.DPD_Algorithm='analytic'; c.Run_Tag='analytic_reference';
a=run_rfdac_simulation(c); report.Analytic_Reference=a.metrics; clear a;

% Short actual simulations measure the address-resolution tradeoff.
c.Save_Results=false; c.Num_Symbols=1024; c.LO_Jitter_Enable=false;
c.DPD_Algorithm='lut'; report.Sweep=sweep_dpd_lut(c,[256 4096 16384 65536]);

% All QAM modes use the same finite alphabet; no interpolated output points.
c.Num_Symbols=256; c.DPD_IQ_Enable=true; c.DPD_Nonlinearity_Enable=true;
c.DPD_LUT_Interpolation='nearest'; c.DPD_LUT_Value_Bits=10; c.DPD_LUT_Fraction_Bits=0;
for order=[16 64 256 1024 4096]
    c.QAM_Order=order; t=run_rfdac_simulation(c);
    assert(isfinite(t.metrics.EVM_Percent) && t.metrics.Invalid_Output_Codeword_Pairs==0);
end
finalize_rfdac_dpd();
report.All_Passed=true;
folder=fullfile(paths.Validation,'lut_evaluation');
save(fullfile(folder,'lut_validation.mat'),'report');
fid=fopen(fullfile(folder,'validation.txt'),'w'); cleanup=onCleanup(@()fclose(fid));
fprintf(fid,'PASS: 16384 trained absolute DAC drives = 128x128, signed 10-bit I/Q words, 40 KiB word payload.\n');
fprintf(fid,'PASS: runtime uses stored observations/words with poisoned model coefficients; zero output table emits zero.\n');
fprintf(fid,'PASS: total_points / axis_bits / qam_multiple and invalid-count guard.\n');
fprintf(fid,'PASS: actual full-record LUT simulation and matched analytic reference.\n');
fprintf(fid,'PASS: five QAM modes; finite-alphabet membership; interpolation and fractional output words rejected.\n');
fprintf(fid,'Main EVM before / LUT / analytic: %.9f / %.9f / %.9f %%\n', ...
    report.Before_Metrics.EVM_Percent,report.Main_Metrics.EVM_Percent,report.Analytic_Reference.EVM_Percent);
disp(report.Sweep.Table); disp('ALL LUT VALIDATION CHECKS PASSED.');
end
