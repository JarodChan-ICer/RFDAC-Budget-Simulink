function folder=rfdac_output_directory(folder)
% Redirect saved pre-organization cfg paths; preserve other user directories.
root=rfdac_project_root(); legacy=fullfile(root,'results');
if strcmpi(folder,legacy)
    folder=fullfile(root,'outputs','results');
elseif startsWith(folder,[legacy filesep],'IgnoreCase',true)
    folder=fullfile(root,'outputs','results',folder(numel(legacy)+2:end));
end
end
