function test_threshold_detection(prm_file)
% TEST_THRESHOLD_DETECTION - Diagnostic script to understand why no spikes are detected
%
% Usage: test_threshold_detection('my_recording.prm')
%
% This script loads a small chunk of data and visualizes:
% 1. Raw signal
% 2. Filtered signal
% 3. Threshold levels
% 4. Detection points

if nargin < 1
    error('Usage: test_threshold_detection(''prm_file.prm'')');
end

% Load parameters
P = irc('loadprm', prm_file);
fprintf('Loaded parameters from: %s\n', prm_file);
fprintf('qqFactor: %.2f\n', P.qqFactor);
fprintf('Filter type: %s\n', P.vcFilter);

% Load first chunk of data
fprintf('\nLoading first chunk of data...\n');
[fid, nBytes] = fopen_(P.vcFile, 'r');
if fid == -1
    error('Cannot open file: %s', P.vcFile);
end

% Read 10 seconds of data or less
nSamples = min(10 * P.sRateHz, nBytes / (P.nChans * 2));  % 10 seconds or full file
mnWav_raw = fread(fid, [P.nChans, nSamples], 'int16=>int16')';
fclose(fid);

fprintf('Loaded %d samples from %d channels\n', nSamples, P.nChans);

% Apply common average reference if needed
if P.vcCommonRef ~= 'none'
    fprintf('Applying CAR: %s\n', P.vcCommonRef);
    mnWav_car = int16(car_(single(mnWav_raw), P.vcCommonRef, P.miSites));
else
    mnWav_car = mnWav_raw;
end

% Apply filtering
fprintf('Applying filter: %s\n', P.vcFilter);
mnWav_filt = filt_car_(mnWav_car, P);

% Compute thresholds using the actual function
fprintf('\nComputing thresholds...\n');
vnThresh = mr2thresh_(mnWav_filt, P, true);  % true = apply qqFactor

% Compute noise estimates
vnNoise = zeros(P.nChans, 1);
for iChan = 1:P.nChans
    vnNoise(iChan) = median(abs(mnWav_filt(:,iChan))) / 0.6745;
end

% Count potential spike crossings
viCrossings = zeros(P.nChans, 1);
for iChan = 1:P.nChans
    viCrossings(iChan) = sum(abs(mnWav_filt(:,iChan)) > vnThresh(iChan));
end

% Print statistics
fprintf('\n========== DETECTION STATISTICS ==========\n');
fprintf('Channel\tSignal_Max\tNoise_Est\tThreshold\tSNR\tCrossings\n');
for iChan = 1:min(10, P.nChans)  % Show first 10 channels
    vrSignal = mnWav_filt(:,iChan);
    fprintf('%d\t%.1f\t\t%.1f\t\t%.1f\t\t%.2f\t%d\n', ...
        iChan, max(abs(vrSignal)), vnNoise(iChan), vnThresh(iChan), ...
        vnThresh(iChan)/vnNoise(iChan), viCrossings(iChan));
end

% Create visualization
figure('Name', 'Threshold Detection Diagnostics', 'Position', [100, 100, 1200, 800]);

% Select a representative channel with median activity
[~, iChan_rep] = min(abs(viCrossings - median(viCrossings)));
fprintf('\nVisualizing channel %d (median activity)\n', iChan_rep);

% Plot 1: Raw signal
subplot(3,1,1);
t_sec = (1:min(nSamples, P.sRateHz))/P.sRateHz;  % First second
plot(t_sec, mnWav_raw(1:length(t_sec), iChan_rep));
ylabel('Raw Signal (ADC)');
title(sprintf('Channel %d - Raw Signal', iChan_rep));
grid on;

% Plot 2: Filtered signal with threshold
subplot(3,1,2);
vrFilt_plot = mnWav_filt(1:length(t_sec), iChan_rep);
plot(t_sec, vrFilt_plot, 'b');
hold on;
plot(t_sec([1 end]), vnThresh(iChan_rep)*[1 1], 'r--', 'LineWidth', 2);
plot(t_sec([1 end]), -vnThresh(iChan_rep)*[1 1], 'r--', 'LineWidth', 2);
ylabel('Filtered Signal (ADC)');
title(sprintf('Filtered Signal with Threshold (±%.1f)', vnThresh(iChan_rep)));
legend('Filtered Signal', 'Threshold', 'Location', 'best');
grid on;

% Plot 3: Threshold vs noise across all channels
subplot(3,1,3);
bar(1:P.nChans, [vnNoise, vnThresh], 'grouped');
xlabel('Channel');
ylabel('Amplitude (ADC)');
title('Noise Estimate vs Threshold for All Channels');
legend('Noise Estimate', 'Threshold', 'Location', 'best');
grid on;

% Save diagnostic data
vcDiagFile = [P.vcFile_prm, '.threshold_diagnostics.mat'];
save(vcDiagFile, 'vnThresh', 'vnNoise', 'viCrossings', 'P');
fprintf('\nDiagnostic data saved to: %s\n', vcDiagFile);

% Recommendations
fprintf('\n========== RECOMMENDATIONS ==========\n');
if median(viCrossings) == 0
    fprintf('WARNING: No threshold crossings detected on most channels!\n');
    fprintf('Consider:\n');
    fprintf('  1. Reducing qqFactor (currently %.1f) to lower thresholds\n', P.qqFactor);
    fprintf('  2. Check if data scaling is correct (uV_per_bit = %.4f)\n', P.uV_per_bit);
    fprintf('  3. Verify filter settings are appropriate for your data\n');
elseif median(viCrossings) < 10
    fprintf('Very few threshold crossings detected.\n');
    fprintf('Consider reducing qqFactor from %.1f to %.1f\n', P.qqFactor, P.qqFactor*0.8);
elseif median(viCrossings) > 1000
    fprintf('Many threshold crossings detected.\n');
    fprintf('Consider increasing qqFactor from %.1f to %.1f\n', P.qqFactor, P.qqFactor*1.2);
else
    fprintf('Detection seems reasonable. Check if spikes are being merged properly.\n');
end

end

% Helper functions (simplified versions)
function mnWav_filt = filt_car_(mnWav, P)
    % Simple filtering for diagnostic purposes
    if strcmpi(P.vcFilter, 'ndiff')
        % Simple differentiation filter
        mnWav_filt = int16([zeros(1, size(mnWav,2)); diff(single(mnWav))]);
    else
        mnWav_filt = mnWav;  % No filtering for diagnostics
    end
end

function vnThresh = mr2thresh_(mnWav, P, fApplyQQ)
    % Compute thresholds
    if nargin < 3, fApplyQQ = true; end

    nChans = size(mnWav, 2);
    vnThresh = zeros(nChans, 1);

    for iChan = 1:nChans
        vrWav = mnWav(:, iChan);
        noise_est = median(abs(vrWav)) / 0.6745;
        if fApplyQQ
            vnThresh(iChan) = noise_est * P.qqFactor;
        else
            vnThresh(iChan) = noise_est;
        end
    end
end

function mnWav_car = car_(mnWav, vcMode, miSites)
    % Simple CAR implementation
    if strcmpi(vcMode, 'mean')
        vrMean = mean(mnWav, 2);
        mnWav_car = bsxfun(@minus, mnWav, vrMean);
    else
        mnWav_car = mnWav;
    end
end

function [fid, nBytes] = fopen_(vcFile, vcMode)
    fid = fopen(vcFile, vcMode);
    if fid ~= -1
        fseek(fid, 0, 'eof');
        nBytes = ftell(fid);
        fseek(fid, 0, 'bof');
    else
        nBytes = 0;
    end
end