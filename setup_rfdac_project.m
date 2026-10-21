function paths=setup_rfdac_project()
%SETUP_RFDAC_PROJECT Add only active code; keep generated files under outputs.
root=fileparts(mfilename('fullpath'));
paths.Root=root;
paths.Source=fullfile(root,'src');
paths.Tools=fullfile(root,'tools','model');
paths.Tests=fullfile(root,'tests');
paths.Results=fullfile(root,'outputs','results');
paths.Validation=fullfile(root,'outputs','validation');
paths.Logs=fullfile(root,'outputs','logs');
paths.Cache=fullfile(root,'outputs','cache');
paths.Codegen=fullfile(paths.Cache,'codegen');
paths.Archive=fullfile(root,'archive');
addpath(root,paths.Source,paths.Tools,paths.Tests);
folders={paths.Results,paths.Validation,paths.Logs,paths.Cache,paths.Codegen};
for k=1:numel(folders), if ~isfolder(folders{k}), mkdir(folders{k}); end; end
if license('test','Simulink')
    current=Simulink.fileGenControl('getConfig');
    if ~strcmp(current.CacheFolder,paths.Cache) || ~strcmp(current.CodeGenFolder,paths.Codegen)
        Simulink.fileGenControl('set','CacheFolder',paths.Cache, ...
            'CodeGenFolder',paths.Codegen,'createDir',true);
    end
end
end
