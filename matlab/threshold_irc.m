function custom_ironclust_analysis(pathToRecording)
    % This function calculates detection thresholds and noise levels from a
    % recording file without running the full IronClust sorting pipeline.
    %
    % Args:
    %   pathToRecording: The full path to the binary recording file.

    % --- 1. Set up IronClust Parameters ---
    % Create a temporary directory for IronClust output
    outputDir = fullfile(fileparts(pathToRecording), 'ironclust_output');
    if ~exist(outputDir, 'dir'), mkdir(outputDir); end

    % Create a parameter file (.prm) for IronClust
    prmFile = fullfile(outputDir, 'ironclust.prm');
    
    % Get default IronClust parameters
    P = irc('default-prm');
    
    % Modify parameters as needed
    P.vcFile = pathToRecording;
    P.vcDir_out = outputDir;
    P.fGpu = 1; % Use GPU if available (set to 0 for CPU)
    P.CHUNK = [200000, 40000]; % Chunk size for processing
    
    % Write the parameter file (good practice, though not used for a full 'run')
    irc('write-prm', P, prmFile);

    % --- 2. Calculate Thresholds and Noise Levels ---
    fprintf('Calculating thresholds...\n');
    
    % Initialize variables to store thresholds
    all_thresholds = [];
    
    % Get the recording file info
    d = dir(P.vcFile);
    nBytes = d.bytes;
    nChans = P.nChans;
    bytesPerSample = 2; % Assuming int16
    nSamples = nBytes / (nChans * bytesPerSample);
    
    % Process the file in chunks to get thresholds
    chunkSize = P.CHUNK(1);
    nChunks = ceil(nSamples / chunkSize);
    
    % Create a recording object to read the file
    hRec = jrclust.models.recording.Recording(P.vcFile, P);

    for iChunk = 1:nChunks
        fprintf('Processing chunk %d of %d\n', iChunk, nChunks);
        
        % Get the current chunk of raw data
        vrWav_raw = hRec.readRaw(iChunk);
        
        % Filter the chunk
        vrWav_filt = jrclust.filters.bandpass(vrWav_raw, P);
        
        % Estimate noise and set threshold for the chunk
        vrThresh_site = jrclust.detect.detect_threshold(vrWav_filt, P);
        all_thresholds = [all_thresholds, vrThresh_site];
    end
    
    % Use the standard deviation of thresholds as a proxy for noise level per chunk
    noise_over_time = std(all_thresholds, 0, 1);
    
    fprintf('Threshold calculation complete.\n');

    % --- 3. Plotting ---
    fprintf('Generating plots...\n');
    % Create a new figure
    figure('Name', 'IronClust Detection Analysis', 'NumberTitle', 'off', 'Position', [100, 100, 1200, 600]);

    % Subplot 1: Thresholds per channel over time
    subplot(2, 1, 1);
    plot(all_thresholds');
    title('Detection Thresholds per Channel Over Time');
    xlabel('Chunk Number');
    ylabel('Threshold (uV)');
    grid on;
    legend(arrayfun(@(c) sprintf('Channel %d', c), 1:nChans, 'UniformOutput', false), 'Location', 'eastoutside');
    axis tight;

    % Subplot 2: Noise level over time
    subplot(2, 1, 2);
    plot(noise_over_time, 'r', 'LineWidth', 1.5);
    title('Noise Level Over Time');
    xlabel('Chunk Number');
    ylabel('Noise Level (std. dev. of thresholds)');
    grid on;
    axis tight;

    % Save the figure
    saveas(gcf, fullfile(outputDir, 'detection_analysis.png'));
    fprintf('Figure saved to %s\n', fullfile(outputDir, 'detection_analysis.png'));
end
