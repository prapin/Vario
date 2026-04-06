function vario(date)
data = load([date '.dat']);

graphics_toolkit gnuplot
figure('visible','off')
stairs([data(:,1);24], [data(:,[2 4]); data(end, [2 4])]); 
axis([0 24]); 
xticks(0:24);
title(date)
print([date '.png']);

f = fopen([date '.txt'], 'wt');
vario=data(:,2);
fprintf(f, 'Rapport VARIO du %s\n\n', date)
[a, b] = min(vario);
fprintf(f, 'Prix minimal %.2f ct/kWh à %s\n', a, hour((b - 1)/4));
[a, b] = max(vario);
fprintf(f, 'Prix maximal %.2f ct/kWh à %s\n', a, hour((b - 1)/4));
fprintf(f, 'Prix moyen   %.2f ct/kWh\n', mean(vario));

plage=13; # 3h
c=conv(vario, ones(plage, 1), 'valid');
d=diff(sign(diff(c)));
mins = find(d > 0);
h = [data(mins+7-6, 1) data(mins+7+6, 1)];
p=c(mins+1)/plage;
fprintf(f, '\nMeilleures plages de 3h:\n');
for i=1:numel(p)
	fprintf(f, 'De %s à %s: %.2f ct/kWh\n', hour(h(i, 1)), hour(h(i, 2)), p(i));
end
fclose(f);

function out=hour(h)
out = sprintf('%02dh%02d', floor(h), (h-floor(h))* 60);
