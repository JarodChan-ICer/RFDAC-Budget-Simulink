function figs=show_rfdac_identification(source)
%SHOW_RFDAC_IDENTIFICATION Display a saved report without simulating/training.
% show_rfdac_identification() loads the default identification_report.mat.
% show_rfdac_identification(report) accepts an in-memory report.
% show_rfdac_identification('path/to/identification_report.mat') loads that file.
paths=setup_rfdac_project();
if nargin<1
    source=fullfile(paths.Validation,'rx_identification','identification_report.mat');
end
if ischar(source) || (isstring(source) && isscalar(source))
    file=char(source);
    assert(isfile(file),'Report not found: %s. Run run_rfdac_identification first.',file);
    data=load(file,'report');
    assert(isfield(data,'report'),'MAT file must contain a report variable.');
    report=data.report;
    % Re-export beside a moved report instead of using a stale absolute path.
    [folder,~,~]=fileparts(file);
    if isempty(folder), folder=pwd; end
    report.Output_Directory=folder;
else
    report=source;
end
assert(isstruct(report) && isscalar(report) && isfield(report,'Cases') && ...
    isfield(report,'Estimate'),'Expected a completed identification report.');
report.Figure_Visible='on';
figs=plot_rfdac_identification(report);
if isfield(report,'Identification_Trials')
    figs(end+1,1)=plot_rfdac_identification_reliability(report);
end
drawnow;
fprintf('Showing saved identification results (no new simulation): %s\n',report.Output_Directory);
end
