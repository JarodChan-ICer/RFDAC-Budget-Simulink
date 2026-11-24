function usage=rfdac_lut_usage(results)
% Replay TX RRC and sample-wise LUT to identify the actually selected points.
c=results.cfg; d=results.DPD; lut=d.LUT;
assert(d.Enabled && (d.IQ_Enable || d.Nonlinearity_Enable) && ...
    strcmp(d.Algorithm,'lut') && isfield(lut,'Output_I'),'rfdac:LUTInactive', ...
    'An active trained LUT is required.');
L=results.timing.DAC_Samples_Per_Symbol;
r=results.Reference_Symbols(:); frames=numel(r)+results.timing.Decision_Frame_Delay+2;
input=complex(zeros(frames*L,1)); input(1:L:numel(r)*L)=r*(sqrt(L)*c.Input_Amplitude);
symbolMode=isfield(d,'Placement') && strcmp(d.Placement,'symbol_before_rrc');
if symbolMode
    index=d.Symbol_LUT_Indices(results.Transmitted_IDs+1);
    source=d.Symbol_Drives(results.Transmitted_IDs+1)/c.Input_Amplitude;
    input(1:L:numel(r)*L)=source*(sqrt(L)*c.Input_Amplitude);
end
input=filter(results.filters.RRC,1,input);
[out,~,~,~]=rfdac_dpd_codewords(input,d);
if ~symbolMode
    if strcmp(lut.Format,'ppt_measured_2d_lut_v1')
        inputCodes=complex(min(max(round(real(input)/d.LSB),d.Min_Code),d.Max_Code), ...
            min(max(round(imag(input)/d.LSB),d.Min_Code),d.Max_Code));
        [selected,~,index]=rfdac_dpd_lut_lookup(inputCodes*d.LSB,d);
        assert(isequal(selected,out));
    else
        words=complex(double(lut.Output_I(:)),double(lut.Output_Q(:)));
        [ok,index]=ismember(out/d.LSB,words); assert(all(ok));
    end
end
usage.Counts=accumarray(index,1,[lut.Points 1]);
usage.Used=usage.Counts>0; usage.Mapped=usage.Used;
usage.Count_Unit='DAC samples';
expected=out/d.LSB;
usage.Used_Indices=find(usage.Used); usage.Used_Points=sum(usage.Used);
usage.Mapped_Points=sum(usage.Mapped); usage.Total_Points=lut.Points;
usage.Total_DAC_Samples=frames*L; usage.Payload_Symbols=numel(r);
usage.Includes_Filter_Flush=true; usage.Verified_Logged_Samples=0;
usage.Source='TX RRC waveform, sample-wise trained LUT selection, including filter flush';
if strcmp(lut.Format,'ppt_measured_2d_lut_v1')
    usage.Source='TX RRC waveform -> nearest interpolated measured output -> paired legal DAC code; includes filter flush';
    usage.Raw_Training_Points=lut.Training_Order;
end
if symbolMode
    usage.Count_Unit='payload symbols';
    usage.Includes_Filter_Flush=false;
    usage.Source='Measured RX constellation lookup before TX RRC; selected training inputs replayed through RRC/DAC';
end
if isfield(results,'waveforms') && isfield(results.waveforms,'codes_i')
    logged=complex(results.waveforms.codes_i(:),results.waveforms.codes_q(:)); n=numel(logged);
    assert(n<=numel(expected) && isequal(expected(end-n+1:end),logged), ...
        'rfdac:LUTUsageReplay','Reconstructed TX RRC / LUT outputs differ from actual DAC words.');
    usage.Verified_Logged_Samples=n;
end
end
