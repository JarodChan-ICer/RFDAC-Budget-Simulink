function root=rfdac_project_root()
% Runtime sources live exactly one level below the project root.
root=fileparts(fileparts(mfilename('fullpath')));
end
