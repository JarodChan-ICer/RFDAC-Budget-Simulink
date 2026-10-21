function [v,stats]=rfdac_dpd_apply(u,d)
% Predistort desired complex envelope at the DAC sample rate.
% atan RF fundamental: F(A)=2*A/(1+sqrt(1+beta*A^2)).
% Its envelope inverse is A=R/(1-beta*R^2/4). Invert IQ AFTER this.
if isfield(d,'Algorithm') && strcmp(d.Algorithm,'lut') && (d.IQ_Enable || d.Nonlinearity_Enable)
    [v,limited]=rfdac_dpd_lut_lookup(u,d);
else
    [v,limited]=rfdac_dpd_analytic(u,d);
end
ratio=ones(size(u)); nz=abs(u)>eps;
ratio(nz)=abs(v(nz))./abs(u(nz));
ci=round(real(v)/d.LSB); cq=round(imag(v)/d.LSB);
stats=[sum(abs(u).^2);sum(abs(v).^2);numel(u);max(ratio);sum(limited); ...
    sum(ci<d.Min_Code | ci>d.Max_Code);sum(cq<d.Min_Code | cq>d.Max_Code);max(abs(v))];
end
