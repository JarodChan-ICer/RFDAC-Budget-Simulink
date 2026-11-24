function lut=rfdac_lut_grid(c,d)
% Training coordinates only. No forward or inverse device model is used.
mode=validatestring(c.DPD_LUT_Size_Mode,{'training_order','total_points','axis_bits','qam_multiple'});
if strcmp(mode,'axis_bits')
    bits=c.DPD_LUT_Address_Bits;
    validateattributes(bits,{'numeric'},{'vector','numel',2,'integer','>=',1,'<=',c.DAC_Bits});
    count=2.^reshape(bits,1,2);
else
    if strcmp(mode,'training_order'), points=c.DPD_LUT_Training_Order;
    else, points=c.DPD_LUT_Points; end
    if strcmp(mode,'qam_multiple')
        validateattributes(c.DPD_LUT_Points_Per_QAM_Symbol,{'numeric'},{'scalar','integer','positive'});
        points=c.QAM_Order*c.DPD_LUT_Points_Per_QAM_Symbol;
    end
    validateattributes(points,{'numeric'},{'scalar','integer','>=',4,'<=',2^20});
    bits=log2(points)/2;
    assert(abs(bits-round(bits))<1e-12 && bits<=c.DAC_Bits,'rfdac:LUTPointCount', ...
        'Training points must form a square power-of-two grid within the DAC resolution.');
    count=[1 1]*2^round(bits);
end
assert(prod(count)<=2^20,'rfdac:LUTMemory','At most 1048576 training points are supported.');
validateattributes(c.DPD_LUT_Value_Bits,{'numeric'},{'scalar','integer','>=',c.DAC_Bits,'<=',24});
assert(c.DPD_LUT_Fraction_Bits==0,'rfdac:LUTDiscreteWords','DAC output words must have zero fractional bits.');
validateattributes(c.DPD_LUT_Drive_Range,{'numeric'},{'scalar','positive','<=',1,'finite'});
step=(d.Max_Code-d.Min_Code+1)./count*c.DPD_LUT_Drive_Range;
first=(d.Min_Code+d.Max_Code)/2-(count-1).*step/2;
ci=first(1)+(0:count(1)-1)*step(1); cq=first(2)+(0:count(2)-1)*step(2);
if strcmp(c.DPD_LUT_Training_Mode,'link')
    % PPT snake scans the complete legal input rectangle, including its rails.
    ci=linspace(d.Min_Code*c.DPD_LUT_Drive_Range,d.Max_Code*c.DPD_LUT_Drive_Range,count(1));
    cq=linspace(d.Min_Code*c.DPD_LUT_Drive_Range,d.Max_Code*c.DPD_LUT_Drive_Range,count(2));
end
[ic,qc]=ndgrid(ci,cq);
lut.Output_I=int32(min(max(round(ic),d.Min_Code),d.Max_Code));
lut.Output_Q=int32(min(max(round(qc),d.Min_Code),d.Max_Code));
lut.Training_Drive=complex(double(lut.Output_I),double(lut.Output_Q))*d.LSB;
assert(numel(unique(lut.Training_Drive))==prod(count),'rfdac:LUTDuplicateDrive', ...
    'Training range and DAC resolution cannot represent this many distinct drives.');
lut.Training_I=lut.Output_I; lut.Training_Q=lut.Output_Q;
lut.Training_Order=prod(count); lut.Training_Size=count;
lut.Size_Mode=mode; lut.Size=count; lut.Points=prod(count); lut.Address_Bits=log2(count);
lut.Value_Bits=c.DPD_LUT_Value_Bits; lut.Fraction_Bits=0;
lut.Code_Step=step; lut.First_Code=[ci(1) cq(1)];
lut.Node_Quantization_Error_RMS_Code=sqrt(mean( ...
    (double(lut.Output_I(:))-ic(:)).^2+(double(lut.Output_Q(:))-qc(:)).^2));
lut.Gain_Limited_Nodes=0; lut.Value_Clipped_Nodes=0;
lut.Packed_Payload_Bytes=ceil(lut.Points*2*lut.Value_Bits/8);
end
