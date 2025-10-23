irc export  
save('S0.mat','S0')


irc export-quality
irc export-csv
%irc export-cluwav


try
    save('tmrWav_clu','tmrWav_clu')
catch
    error('export waveforms from gui')
end
try
    save('mrRate_clu','mrRate_clu')
catch
    error(['export firing rates from gui, then run ', "save('mrRate_clu','mrRate_clu')"])
end




