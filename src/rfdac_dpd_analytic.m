function [v,limited]=rfdac_dpd_analytic(u,d)
% Known-model inverse, used to generate LUT entries or as analytic reference.
v=u; limited=false(size(u));
if d.Nonlinearity_Enable && d.Beta>0
    denominator=1-d.Beta*abs(u).^2/4;
    limited=denominator<1/d.Max_Gain;
    v=u./max(denominator,1/d.Max_Gain);
end
if d.IQ_Enable
    v=(conj(d.Alpha)*v-d.Image*conj(v))/d.Determinant;
end
end
