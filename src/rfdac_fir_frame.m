function rfdac_fir_frame(block)
% Causal overlap-add FIR with one input and output frame per model step.
% Dialog parameters are the FIR coefficients, frame length and complexity flag.
block.NumDialogPrms=3;
block.DialogPrmsTunable={'Nontunable','Nontunable','Nontunable'};
block.NumInputPorts=1; block.NumOutputPorts=1;
block.SetPreCompInpPortInfoToDynamic;
block.SetPreCompOutPortInfoToDynamic;
frameLength=block.DialogPrm(2).Data;
complexity='Real';
if block.DialogPrm(3).Data, complexity='Complex'; end
block.InputPort(1).Dimensions=[frameLength 1];
block.InputPort(1).DatatypeID=0;
block.InputPort(1).Complexity=complexity;
block.InputPort(1).DirectFeedthrough=true;
block.OutputPort(1).Dimensions=[frameLength 1];
block.OutputPort(1).DatatypeID=0;
block.OutputPort(1).Complexity=complexity;
block.SampleTimes=[-1 0];
block.SimStateCompliance='DefaultSimState';
block.RegBlockMethod('SetInputPortSamplingMode',@set_sampling_mode);
block.RegBlockMethod('PostPropagationSetup',@setup_state);
block.RegBlockMethod('InitializeConditions',@initialize);
block.RegBlockMethod('Outputs',@output);
block.RegBlockMethod('Update',@update);
end

function set_sampling_mode(block,index,mode)
block.InputPort(index).SamplingMode=mode;
block.OutputPort(1).SamplingMode=mode;
end

function setup_state(block)
coefficients=block.DialogPrm(1).Data;
tailLength=numel(coefficients)-1;
assert(tailLength>=1,'rfdac:FIRFrameTaps','Frame FIR requires at least two taps.');
fftLength=2^nextpow2(block.DialogPrm(2).Data+tailLength);
block.NumDworks=3;
block.Dwork(1).Name='Overlap';
block.Dwork(1).Dimensions=tailLength;
block.Dwork(1).DatatypeID=0;
block.Dwork(1).Complexity=block.InputPort(1).Complexity;
block.Dwork(1).UsedAsDiscState=true;
block.Dwork(2).Name='FrequencyResponse';
block.Dwork(2).Dimensions=fftLength;
block.Dwork(2).DatatypeID=0;
block.Dwork(2).Complexity='Complex';
block.Dwork(2).UsedAsDiscState=false;
block.Dwork(3).Name='NextOverlap';
block.Dwork(3).Dimensions=tailLength;
block.Dwork(3).DatatypeID=0;
block.Dwork(3).Complexity=block.InputPort(1).Complexity;
block.Dwork(3).UsedAsDiscState=false;
end

function initialize(block)
initialOverlap=zeros(block.Dwork(1).Dimensions,1);
if block.DialogPrm(3).Data, initialOverlap=complex(initialOverlap); end
block.Dwork(1).Data=initialOverlap;
block.Dwork(3).Data=initialOverlap;
coefficients=block.DialogPrm(1).Data;
block.Dwork(2).Data=complex(fft(coefficients(:),block.Dwork(2).Dimensions));
end

function output(block)
inputFrame=block.InputPort(1).Data;
frequencyResponse=block.Dwork(2).Data;
overlap=block.Dwork(1).Data;
samples=ifft(fft(inputFrame(:),numel(frequencyResponse)).*frequencyResponse);
if block.DialogPrm(3).Data
    samples=complex(samples);
else
    samples=real(samples);
end
samples(1:numel(overlap))=samples(1:numel(overlap))+overlap;
frameLength=numel(inputFrame);
block.OutputPort(1).Data=samples(1:frameLength);
% If the filter is longer than the frame, this includes the still-pending
% contribution of earlier frames as well as the current frame's own tail.
block.Dwork(3).Data=samples(frameLength+1:frameLength+numel(overlap));
end

function update(block)
block.Dwork(1).Data=block.Dwork(3).Data;
end
