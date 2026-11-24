function report=validate_rfdac_link_lut(fullRun)
% Compatibility entry point: link mode now follows the supplied chip-test PPT.
if nargin<1, fullRun=false; end
report=validate_rfdac_ppt_lut(fullRun);
end
