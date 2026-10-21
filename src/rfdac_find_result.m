function file=rfdac_find_result(relative)
% Find current outputs or preserved historical records without adding archives.
root=rfdac_project_root();
locations={fullfile(root,'outputs','results'),fullfile(root,'outputs','validation'),fullfile(root,'results')};
archives=dir(fullfile(root,'archive'));
for k=numel(archives):-1:1
    if archives(k).isdir && ~startsWith(archives(k).name,'.')
        locations{end+1}=fullfile(root,'archive',archives(k).name,'results'); %#ok<AGROW>
    end
end
for k=1:numel(locations)
    candidate=fullfile(locations{k},relative);
    if isfile(candidate), file=candidate; return; end
end
error('rfdac:ResultNotFound','Result not found in outputs or archives: %s',relative);
end
