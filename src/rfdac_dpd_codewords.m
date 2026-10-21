function [v,ideal,inputCodes,stats]=rfdac_dpd_codewords(u,d)
% Only signed N-bit words cross the digital TX interface.
% Double stores the words exactly; it does not grant fractional code bits.
inputCodes=complex(clip(round(real(u)/d.LSB),d),clip(round(imag(u)/d.LSB),d));
formatted=inputCodes*d.LSB;
[ideal,base]=rfdac_dpd_apply(formatted,d);
outputCodes=complex(clip(round(real(ideal)/d.LSB),d),clip(round(imag(ideal)/d.LSB),d));
v=outputCodes*d.LSB;
stats=base;
stats(2)=sum(abs(v).^2); stats(8)=max(abs(v));
inputI=round(real(u)/d.LSB); inputQ=round(imag(u)/d.LSB);
invalid=real(outputCodes)~=round(real(outputCodes)) | imag(outputCodes)~=round(imag(outputCodes)) | ...
    real(outputCodes)<d.Min_Code | real(outputCodes)>d.Max_Code | ...
    imag(outputCodes)<d.Min_Code | imag(outputCodes)>d.Max_Code;
stats=[stats;sum(abs(ideal).^2);sum(abs(v-ideal).^2);sum(abs(formatted-u).^2); ...
    sum(outputCodes~=inputCodes);sum(inputI<d.Min_Code | inputI>d.Max_Code); ...
    sum(inputQ<d.Min_Code | inputQ>d.Max_Code);sum(invalid); ...
    max([abs(real(outputCodes));abs(imag(outputCodes))])];
end
function x=clip(x,d)
x=min(max(x,d.Min_Code),d.Max_Code);
end
