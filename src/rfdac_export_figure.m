function rfdac_export_figure(fig,path)
% Raster PNG export with bounded memory; avoids exportgraphics' extra render.
set(fig,'PaperPositionMode','auto','Renderer','painters');
drawnow;
print(fig,path,'-dpng','-r110','-painters');
end
