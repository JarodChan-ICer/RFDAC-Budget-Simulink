function [v,limited]=rfdac_dpd_lut_lookup(u,d)
% Actual LUT runtime: index/interpolate stored words, add to original input.
lut=d.LUT;
x=(real(u)/d.LSB-lut.First_Code(1))/lut.Code_Step(1)+1;
y=(imag(u)/d.LSB-lut.First_Code(2))/lut.Code_Step(2)+1;
x=min(max(x,1),lut.Size(1)); y=min(max(y,1),lut.Size(2));
if strcmp(lut.Interpolation,'nearest')
    ix=round(x); iy=round(y); idx=ix+(iy-1)*lut.Size(1);
    di=double(lut.Delta_I(idx)); dq=double(lut.Delta_Q(idx));
    limited=lut.Gain_Limited(idx);
else
    ix=floor(x); iy=floor(y); fx=x-ix; fy=y-iy;
    jx=min(ix+1,lut.Size(1)); jy=min(iy+1,lut.Size(2));
    a=ix+(iy-1)*lut.Size(1); b=jx+(iy-1)*lut.Size(1);
    cc=ix+(jy-1)*lut.Size(1); e=jx+(jy-1)*lut.Size(1);
    wa=(1-fx).*(1-fy); wb=fx.*(1-fy); wc=(1-fx).*fy; we=fx.*fy;
    di=wa.*double(lut.Delta_I(a))+wb.*double(lut.Delta_I(b))+wc.*double(lut.Delta_I(cc))+we.*double(lut.Delta_I(e));
    dq=wa.*double(lut.Delta_Q(a))+wb.*double(lut.Delta_Q(b))+wc.*double(lut.Delta_Q(cc))+we.*double(lut.Delta_Q(e));
    limited=(wa.*lut.Gain_Limited(a)+wb.*lut.Gain_Limited(b)+wc.*lut.Gain_Limited(cc)+we.*lut.Gain_Limited(e))>0;
end
v=u+complex(di,dq)*(d.LSB/2^lut.Fraction_Bits);
end
