function [v,limited,index]=rfdac_dpd_lut_lookup(u,d)
% Select one trained absolute drive. No interpolation, addition or inverse.
lut=d.LUT;
if isfield(lut,'Format') && strcmp(lut.Format,'ppt_runtime_direct_map_v1')
    ci=min(max(round(real(u)/d.LSB),d.Min_Code),d.Max_Code)-lut.Input_First_Code+1;
    cq=min(max(round(imag(u)/d.LSB),d.Min_Code),d.Max_Code)-lut.Input_First_Code+1;
    address=ci+lut.Input_Axis_Points*(cq-1);
    ic=double(lut.Direct_I(address)); qc=double(lut.Direct_Q(address));
    v=complex(ic,qc)*d.LSB; limited=lut.Outside_Observed_Hull(address);
    index=(ic-lut.Dense_First_I+1)+lut.Dense_I_Points*(qc-lut.Dense_First_Q);
    return;
end
if isfield(lut,'Format') && strcmp(lut.Format,'ppt_measured_2d_lut_v1')
    assert(isfield(lut,'Inverse_Index'),'rfdac:LUTTrainingRequired','Complete the serpentine training capture first.');
    ci=min(max(round(real(u)/d.LSB),d.Min_Code),d.Max_Code)-lut.Input_First_Code+1;
    cq=min(max(round(imag(u)/d.LSB),d.Min_Code),d.Max_Code)-lut.Input_First_Code+1;
    address=ci+lut.Input_Axis_Points*(cq-1);
    index=double(lut.Inverse_Index(address));
    v=complex(double(lut.Output_I(index)),double(lut.Output_Q(index)))*d.LSB;
    limited=lut.Outside_Observed_Hull(address);
    return;
end
assert(isfield(lut,'Format') && strcmp(lut.Format,'trained_absolute_codebook_v1'), ...
    'rfdac:LegacyLUT','Regenerate this LUT: saved correction tables are not finite training alphabets.');
if isempty(u), v=u; limited=false(size(u)); index=zeros(size(u)); return; end
nearest=dsearchn(lut.Search_Points,lut.Search_Triangles,[real(u(:)) imag(u(:))]);
index=double(lut.Search_Codebook_Indices(nearest));
index=reshape(index,size(u));
v=complex(double(lut.Output_I(index)),double(lut.Output_Q(index)))*d.LSB;
limited=false(size(u));
end
