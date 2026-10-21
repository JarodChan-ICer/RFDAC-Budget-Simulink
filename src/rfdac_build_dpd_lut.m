function lut=rfdac_build_dpd_lut(c,d)
% Uniform Cartesian bins. Each entry stores two finite-precision corrections.
mode=validatestring(c.DPD_LUT_Size_Mode,{'total_points','axis_bits','qam_multiple'});
if strcmp(mode,'axis_bits')
    bits=c.DPD_LUT_Address_Bits;
    validateattributes(bits,{'numeric'},{'vector','numel',2,'integer','>=',1,'<=',c.DAC_Bits});
    count=2.^reshape(bits,1,2);
else
    points=c.DPD_LUT_Points;
    if strcmp(mode,'qam_multiple')
        validateattributes(c.DPD_LUT_Points_Per_QAM_Symbol,{'numeric'},{'scalar','integer','positive'});
        points=c.QAM_Order*c.DPD_LUT_Points_Per_QAM_Symbol;
    end
    validateattributes(points,{'numeric'},{'scalar','integer','>=',4,'<=',2^20});
    axisBits=log2(points)/2;
    assert(abs(axisBits-round(axisBits))<1e-12 && axisBits<=c.DAC_Bits, ...
        'rfdac:LUTPointCount','Total LUT points must be a square power of two with <= DAC_Bits address bits per axis. Use axis_bits mode for rectangular grids.');
    count=[1 1]*2^round(axisBits);
end
assert(prod(count)<=2^20,'rfdac:LUTMemory','LUT is limited to 1048576 complex entries.');
validateattributes(c.DPD_LUT_Value_Bits,{'numeric'},{'scalar','integer','>=',2,'<=',24});
validateattributes(c.DPD_LUT_Fraction_Bits,{'numeric'}, ...
    {'scalar','integer','nonnegative','<=',c.DPD_LUT_Value_Bits-2});
lut.Interpolation=validatestring(c.DPD_LUT_Interpolation,{'nearest','linear'});
lut.Size_Mode=mode; lut.Size=count; lut.Points=prod(count); lut.Address_Bits=log2(count);
lut.Value_Bits=c.DPD_LUT_Value_Bits; lut.Fraction_Bits=c.DPD_LUT_Fraction_Bits;
lut.Code_Step=(d.Max_Code-d.Min_Code+1)./count;
lut.First_Code=d.Min_Code+(lut.Code_Step-1)/2;
lut.I_Breakpoints_Codes=lut.First_Code(1)+(0:count(1)-1)*lut.Code_Step(1);
lut.Q_Breakpoints_Codes=lut.First_Code(2)+(0:count(2)-1)*lut.Code_Step(2);
[ic,qc]=ndgrid(lut.I_Breakpoints_Codes,lut.Q_Breakpoints_Codes);
u=complex(ic,qc)*d.LSB;
[v,limited]=rfdac_dpd_analytic(u,d); % generation only, never the LUT runtime path
scale=2^lut.Fraction_Bits;
di=round((real(v)/d.LSB-ic)*scale); dq=round((imag(v)/d.LSB-qc)*scale);
lo=-2^(lut.Value_Bits-1); hi=2^(lut.Value_Bits-1)-1;
clipped=di<lo | di>hi | dq<lo | dq>hi;
lut.Delta_I=int32(min(max(di,lo),hi)); lut.Delta_Q=int32(min(max(dq,lo),hi));
errorI=double(lut.Delta_I)/scale-(real(v)/d.LSB-ic);
errorQ=double(lut.Delta_Q)/scale-(imag(v)/d.LSB-qc);
lut.Node_Quantization_Error_RMS_Code=sqrt(mean(errorI(:).^2+errorQ(:).^2));
lut.Gain_Limited=limited;
lut.Value_Clipped_Nodes=sum(clipped(:)); lut.Gain_Limited_Nodes=sum(limited(:));
lut.Packed_Payload_Bytes=ceil(lut.Points*2*lut.Value_Bits/8);
lut.Storage='Signed I/Q correction words; payload excludes addressing/metadata/interpolator';
lut.Generation='Known static model inverse, not feedback-trained';
end
