function lut=rfdac_build_ppt_lut(c,d,lut)
% PPT pp.4-5: interpolate MEASURED forward map, then find nearest output b
% and store its corresponding legal input c for every desired DAC word a.
persistent cacheKey cacheLUT
assert(strcmp(c.DPD_LUT_Interpolation,'linear'),'rfdac:PPTInterpolation', ...
    'PPT workflow requires DPD_LUT_Interpolation=''linear'' (measured forward-map interpolation).');
assert(c.DAC_Bits<=10,'rfdac:PPTLUTMemory','Dense 2-D PPT lookup currently supports up to 10 bits per DAC axis.');
lut.Format='ppt_measured_2d_lut_v1'; lut.Interpolation='linear';
lut.Training_Output=[]; lut.Observation_Domain='phase_aligned_equalized_RX_envelope_V';
lut.Calibration_Mode='joint';
if d.IQ_Enable && ~d.Nonlinearity_Enable, lut.Calibration_Mode='iq_only'; end
lut.Generation='Pending actual zero-prefixed serpentine RF capture';
lut.Storage='Dense DAC input/output address map plus measured/interpolated forward responses';
lut.Selection='Desired waveform code a -> nearest interpolated measured output b -> paired DAC input c';
if ~d.Enabled || ~(d.IQ_Enable || d.Nonlinearity_Enable)
    lut.Generation='DPD bypass; no training capture requested'; return;
end
meta=c.DPD_LUT_Training_Metadata;
if isfield(meta,'Key') && (~isfield(meta,'Pipeline') || ~strcmp(meta.Pipeline,'ppt_serpentine_v1') || ...
        ~isequal(meta.Key.Drive_I,lut.Training_I) || ~isequal(meta.Key.Drive_Q,lut.Training_Q))
    return; % stale generated observations: runner will recapture
end
if isempty(c.DPD_LUT_Training_Observed), return; end
observed=c.DPD_LUT_Training_Observed;
validateattributes(observed,{'numeric'},{'numel',lut.Training_Order,'finite'});
key={lut.Training_Drive,observed,c.DAC_Bits,c.DAC_Full_Scale,c.DPD_LUT_Value_Bits,meta,lut.Calibration_Mode};
if isequal(key,cacheKey), lut=cacheLUT; return; end
lut.Training_Output=reshape(observed,lut.Training_Size);
if ~isempty(fieldnames(meta)), lut.Training_Metadata=meta; end
lut.Generation='Actual serpentine RF capture -> frame extraction/phase alignment -> interpolated forward 2D LUT';
if isempty(fieldnames(meta))
    lut.Generation='Supplied phase-aligned forward observations -> interpolated 2D LUT';
end
lut.Mapping_Training_Output=lut.Training_Output;
if strcmp(lut.Calibration_Mode,'iq_only')
    lut.IQ_Estimate=rfdac_fit_measured_iq(lut.Training_Drive,observed,'i_branch');
    M=lut.IQ_Estimate.Matrix; u=lut.Training_Drive;
    lut.Mapping_Training_Output=complex(M(1,1)*real(u)+M(1,2)*imag(u), ...
        M(2,1)*real(u)+M(2,2)*imag(u));
    lut.Generation='Measured direction-only IQ fit -> linear IQ map; physical TX radial distortion left uncompensated';
end
axisI=double(lut.Training_I(:,1)); axisQ=double(lut.Training_Q(1,:));
ci=(min(axisI):max(axisI))'; cq=min(axisQ):max(axisQ);
[ic,qc]=ndgrid(ci,cq);
lut.Output_I=int32(ic); lut.Output_Q=int32(qc);
f=griddedInterpolant({axisI,axisQ(:)},lut.Mapping_Training_Output,'linear','none');
lut.Dense_Output=f(ic,qc); % interpolation only inside the measured rectangle
assert(all(isfinite(lut.Dense_Output(:))),'rfdac:PPTInterpolation','Nonfinite interpolated observations.');
lut.Size=size(ic); lut.Points=numel(ic); lut.Address_Bits=log2(lut.Size);
lut.Dense_Code_I=ci; lut.Dense_Code_Q=cq;
lut.Input_First_Code=d.Min_Code; lut.Input_Axis_Points=2^c.DAC_Bits;
address=(d.Min_Code:d.Max_Code)';
[ai,aq]=ndgrid(address,address);
targets=[ai(:),aq(:)]*d.LSB;
points=[real(lut.Dense_Output(:)),imag(lut.Dense_Output(:))];
fprintf('PPT LUT: %d measured points -> %d interpolated legal inputs; solving %d output-to-input addresses...\n', ...
    lut.Training_Order,lut.Points,size(targets,1));
t=tic;
if exist('knnsearch','file')==2 && license('test','Statistics_Toolbox')
    search=KDTreeSearcher(points);
    lut.Inverse_Index=reshape(uint32(knnsearch(search,targets)),size(ai));
    lut.Search_Backend='Exact KD-tree nearest measured/interpolated output';
else
    % Base-MATLAB fallback, with higher temporary memory use than a KD tree.
    triangles=delaunayn(points);
    lut.Inverse_Index=reshape(uint32(dsearchn(points,triangles,targets)),size(ai));
    lut.Search_Backend='Exact Delaunay nearest measured/interpolated output';
end
fprintf('PPT nearest-output address map complete in %.2f s.\n',toc(t));
% Convex-hull diagnostic only: do not extrapolate new measured responses.
measured=[real(lut.Mapping_Training_Output(:)),imag(lut.Mapping_Training_Output(:))];
h=convhull(measured(:,1),measured(:,2));
lut.Outside_Observed_Hull=reshape(~inpolygon(targets(:,1),targets(:,2),measured(h,1),measured(h,2)),size(ai));
lut.Packed_Payload_Bytes=ceil(numel(ai)*2*lut.Value_Bits/8);
lut.Total_Auxiliary_Bytes=numel(lut.Dense_Output)*16+numel(lut.Inverse_Index)*4;
cacheKey=key; cacheLUT=lut;
end
