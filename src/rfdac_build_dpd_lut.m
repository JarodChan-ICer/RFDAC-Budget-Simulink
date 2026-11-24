function lut=rfdac_build_dpd_lut(c,d)
% Measured PPT workflow by default; explicit static reference remains separate.
lut=rfdac_lut_grid(c,d);
if strcmp(c.DPD_LUT_Training_Mode,'link')
    lut=rfdac_build_ppt_lut(c,d,lut); return;
end
assert(strcmp(c.DPD_LUT_Interpolation,'nearest'),'rfdac:LUTDiscreteSelection', ...
    'The legacy static finite alphabet permits nearest selection only.');
lut.Format='trained_absolute_codebook_v1'; lut.Interpolation='nearest';
drive=lut.Training_Drive;
if ~isempty(c.DPD_LUT_Training_Observed) && (d.IQ_Enable || d.Nonlinearity_Enable)
    assert(d.IQ_Enable && d.Nonlinearity_Enable,'rfdac:LUTObservedCalibration', ...
        'Full observations require joint IQ/nonlinear calibration.');
    validateattributes(c.DPD_LUT_Training_Observed,{'numeric'},{'numel',lut.Points,'finite'});
    lut.Training_Output=reshape(c.DPD_LUT_Training_Observed,lut.Size);
    lut.Generation='Supplied TX observations paired with finite training drives';
else
    lut.Training_Output=rfdac_train_dpd_lut(drive,d);
    lut.Generation='Static RF reference only; not a measured link capture';
end
response=lut.Training_Output(:);
[lut.Search_Points,indices]=unique([real(response) imag(response)],'rows','stable');
assert(size(lut.Search_Points,1)>=3 && rank(lut.Search_Points-lut.Search_Points(1,:))==2, ...
    'rfdac:LUTTrainingDegenerate','Training observations must span the I/Q plane.');
lut.Search_Codebook_Indices=uint32(indices); lut.Search_Triangles=delaunayn(lut.Search_Points);
lut.Gain_Limited=false(lut.Size);
lut.Storage='Absolute signed I/Q drives; responses and search data are additional';
lut.Selection='Nearest static reference output -> paired trained input';
lut.Observation_Domain='static_RF_fundamental';
end
