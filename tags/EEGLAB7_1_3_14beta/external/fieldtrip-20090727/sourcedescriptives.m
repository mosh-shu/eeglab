function [source] = sourcedescriptives(cfg, source)

% SOURCEDESCRIPTIVES computes descriptive parameters of the beamformer source
% analysis results.
%
% Use as:
%   [source] = sourcedescriptives(cfg, source)
%
% where cfg is a structure with the configuration details and source is the
% result from a beamformer source estimation. The configuration can contain
%   cfg.cohmethod        = 'regular', 'lambda1', 'canonical'
%   cfg.powmethod        = 'regular', 'lambda1', 'trace', 'none'
%   cfg.supmethod        = string
%   cfg.projectmom       = 'yes' or 'no' (default = 'no')
%   cfg.eta              = 'yes' or 'no' (default = 'no')
%   cfg.kurtosis         = 'yes' or 'no' (default = 'no')
%   cfg.keeptrials       = 'yes' or 'no' (default = 'no')
%   cfg.resolutionmatrix = 'yes' or 'no' (default = 'no')
%   cfg.feedback         = 'no', 'text', 'textbar', 'gui' (default = 'text')
%
% The following option only applies to LCMV single-trial timecourses.
%   cfg.fixedori         = 'within_trials' or 'over_trials' (default = 'over_trials')
%
% You can apply a custom mathematical transformation such as a log-transform
% on the estimated power using
%   cfg.transform  = string describing the transformation (default is [])
% The nai, i.e. neural activity index (power divided by projected noise),
% is computed prior to applying the optional transformation.  Subsequently,
% the transformation is applied on the power and on the projected noise
% using "feval". A usefull transformation is for example 'log' or 'log10'.
%
% If repeated trials are present that have undergone some sort of
% resampling (i.e. jackknife, bootstrap, singletrial or rawtrial), the mean,
% variance and standard error of mean will be computed for all source
% parameters. This is done after applying the optional transformation
% on the power and projected noise.
%
% See also SOURCEANALYSIS, SOURCESTATISTICS

% Copyright (C) 2004-2007, Robert Oostenveld & Jan-Mathijs Schoffelen
%
% $Log: not supported by cvs2svn $
% Revision 1.44  2009/04/08 08:35:50  roboos
% ensure that the nai is based on the vectorised power and noise (otherwise the element-wise division fails)
%
% Revision 1.43  2009/01/20 13:01:31  sashae
% changed configtracking such that it is only enabled when BOTH explicitly allowed at start
% of the fieldtrip function AND requested by the user
% in all other cases configtracking is disabled
%
% Revision 1.42  2008/11/21 13:21:35  sashae
% added call to checkconfig at start and end of fucntion
%
% Revision 1.41  2008/09/22 20:17:44  roboos
% added call to fieldtripdefs to the begin of the function
%
% Revision 1.40  2008/09/11 13:21:13  jansch
% included output of ori if cfg.eta = 'yes'
%
% Revision 1.39  2008/07/21 11:02:51  roboos
% removed a try-catch whose purpose was unclear and that caused a problem with nai computation to remain invisible
%
% Revision 1.38  2008/04/09 14:14:30  roboos
% updated docu
%
% Revision 1.37  2008/02/20 14:22:54  roboos
% in allocating sumdip and sqrdip, only make the ourside voxels nan to start with
%
% Revision 1.36  2007/05/08 21:04:40  roboos
% initialize all new elements with nans instead of with zeros, outside values will remain nan
%
% Revision 1.35  2007/05/08 20:53:35  roboos
% added computation of kurtosis for lcmv dipole moments, default is off
%
% Revision 1.34  2007/04/19 17:14:11  roboos
% adde th projectmom dipole otientation to the output for pcc
% added temporary fix for nai in case of lcmv
%
% Revision 1.33  2007/04/03 15:37:07  roboos
% renamed the checkinput function to checkdata
%
% Revision 1.32  2007/03/30 17:05:40  ingnie
% checkinput; only proceed when input data is allowed datatype
%
% Revision 1.31  2007/01/17 17:07:41  roboos
% implemented support for lcmv beamformer timecourses, added option for powmethod=none, added cfg.fixedori
% when keeptrials=yes then do not output the average and variance (it is either/or)
%
% Revision 1.30  2007/01/17 13:19:14  roboos
% Many changes, mainly a complete redesign of the pcc section, keeptrials/powmethod/submethod/projectmom stuff changed.
% This is a bit a kamikaze commit, since I don't have a complete overview of al changes by jansch and me and not everything has been exhaustively tested.
%
% Revision 1.29  2006/07/04 16:04:50  roboos
% renamed option 'jacknife' into 'jackknife' for consistency, maintain backward compatibility with cfgs and old data
%

fieldtripdefs

cfg = checkconfig(cfg, 'trackconfig', 'on');

% check if the input data is valid for this function
source = checkdata(source, 'datatype', 'source', 'feedback', 'yes');

% set the defaults
if ~isfield(cfg, 'transform'),        cfg.transform        = [];            end
if ~isfield(cfg, 'projectmom'),       cfg.projectmom       = 'no';          end % if yes -> svdfft
if ~isfield(cfg, 'powmethod'),        cfg.powmethod        = [];            end % see below
if ~isfield(cfg, 'cohmethod'),        cfg.cohmethod        = [];            end % see below
if ~isfield(cfg, 'feedback'),         cfg.feedback         = 'textbar';     end
if ~isfield(cfg, 'supmethod'),        cfg.supmethod        = 'none';        end
if ~isfield(cfg, 'resolutionmatrix'), cfg.resolutionmatrix = 'no';          end
if ~isfield(cfg, 'eta'),              cfg.eta              = 'no';          end
if ~isfield(cfg, 'kurtosis'),         cfg.kurtosis         = 'no';          end
if ~isfield(cfg, 'keeptrials'),       cfg.keeptrials       = 'no';          end
if ~isfield(cfg, 'keepcsd'),          cfg.keepcsd          = 'no';          end
if ~isfield(cfg, 'fixedori'),         cfg.fixedori = 'over_trials';         end

% this is required for backward compatibility with the old sourceanalysis
if isfield(source, 'method') && strcmp(source.method, 'randomized')
  source.method = 'randomization';
elseif isfield(source, 'method') && strcmp(source.method, 'permuted')
  source.method = 'permutation';
elseif isfield(source, 'method') && strcmp(source.method, 'jacknife')
  source.method = 'jackknife';
end

% determine the type of data, this is only relevant for a few specific types
ispccdata = isfield(source, 'avg') && isfield(source.avg, 'csdlabel');
islcmvavg = isfield(source, 'avg') && isfield(source, 'time') && isfield(source.avg, 'mom');
islcmvtrl = isfield(source, 'trial') && isfield(source, 'time') && isfield(source.trial, 'mom');

% check the consistency of the defaults
if strcmp(cfg.projectmom, 'yes')
  if isempty(cfg.powmethod)
    cfg.powmethod = 'regular'; % set the default
  elseif ~strcmp(cfg.powmethod, 'regular')
    error('unsupported powmethod in combination with projectmom');
  end
  if isempty(cfg.cohmethod)
    cfg.cohmethod = 'regular';% set the default
  elseif ~strcmp(cfg.cohmethod, 'regular')
    error('unsupported cohmethod in combination with projectmom');
  end
else
  if isempty(cfg.powmethod)
    cfg.powmethod = 'lambda1'; % set the default
  end
  if isempty(cfg.cohmethod)
    cfg.cohmethod = 'lambda1'; % set the default
  end
end

% this is required for backward compatibility with an old version of sourcedescriptives
if isfield(cfg, 'singletrial'), cfg.keeptrials = cfg.singletrial;  end

% do a validity check on the input data and specified options
if strcmp(cfg.resolutionmatrix, 'yes')
  if ~isfield(source.avg, 'filter')
    error('The computation of the resolution matrix requires keepfilter=''yes'' in sourceanalysis.');
  elseif ~isfield(source, 'leadfield')
    error('The computation of the resolution matrix requires keepleadfield=''yes'' in sourceanalysis.');
  end
end

if strcmp(cfg.eta, 'yes') && strcmp(cfg.cohmethod, 'svdfft'),
  error('eta cannot be computed in combination with the application of svdfft');
end

if strcmp(cfg.keeptrials, 'yes') && ~strcmp(cfg.supmethod, 'none'),
  error('you cannot keep trials when you want to partialize something');
end

% set some flags for convenience
isnoise    = isfield(source, 'avg') && isfield(source.avg, 'noisecsd');
keeptrials = strcmp(cfg.keeptrials, 'yes');
projectmom = strcmp(cfg.projectmom, 'yes');

% determine the subfunction used for computing power
switch cfg.powmethod
  case 'regular'
    powmethodfun = @powmethod_regular;
  case 'lambda1'
    powmethodfun = @powmethod_lambda1;
  case 'trace'
    powmethodfun = @powmethod_trace;
  case 'none'
    powmethodfun = [];
  otherwise
    error('unsupported powmethod');
end

if ispccdata
  % the source reconstruction was computed using the pcc beamformer
  Ndipole    = length(source.inside) + length(source.outside);
  dipsel     = match_str(source.avg.csdlabel, 'scandip');
  refchansel = match_str(source.avg.csdlabel, 'refchan');
  refdipsel  = match_str(source.avg.csdlabel, 'refdip');
  supchansel = match_str(source.avg.csdlabel, 'supchan');
  supdipsel  = match_str(source.avg.csdlabel, 'supdip');

  % cannot handle reference channels and reference dipoles simultaneously
  if length(refchansel)>0 && length(refdipsel)>0
    error('cannot simultaneously handle reference channels and reference dipole');
  end

  % these are only used to count the number of reference/suppression dipoles and channels
  refsel = [refdipsel refchansel];
  supsel = [supdipsel supchansel];

  if projectmom
    progress('init', cfg.feedback, 'projecting dipole moment');
    for diplop=1:length(source.inside)
      progress(diplop/length(source.inside), 'projecting dipole moment %d/%d\n', diplop, length(source.inside));
      i       = source.inside(diplop);
      mom     = source.avg.mom{i}(dipsel,     :);
      ref     = source.avg.mom{i}(refdipsel,  :);
      sup     = source.avg.mom{i}(supdipsel,  :);
      refchan = source.avg.mom{i}(refchansel, :);
      supchan = source.avg.mom{i}(supchansel, :);
      % compute the projection of the scanning dipole along the direction of the dominant amplitude
      if length(dipsel)>1, [mom, rmom]  = svdfft(mom, 1, source.cumtapcnt); else rmom = []; end
      source.avg.ori{source.inside(diplop)} = rmom;
      % compute the projection of the reference dipole along the direction of the dominant amplitude
      if length(refdipsel)>1, [ref, rref] = svdfft(ref, 1, source.cumtapcnt); else rref = []; end
      % compute the projection of the supression dipole along the direction of the dominant amplitude
      if length(supdipsel)>1, [sup, rsup] = svdfft(sup, 1, source.cumtapcnt); else rsup = []; end

      % compute voxel-level fourier-matrix
      source.avg.mom{i} = cat(1, mom, ref, sup, refchan, supchan);

      % create rotation-matrix
      rotmat = zeros(0, length(source.avg.csdlabel));
      if ~isempty(rmom),
        rotmat = [rotmat; rmom zeros(1,length([refsel(:);supsel(:)]))];
      end
      if ~isempty(rref),
        rotmat = [rotmat; zeros(1, length([dipsel])), rref, zeros(1,length([refchansel(:);supsel(:)]))];
      end
      if ~isempty(rsup),
        rotmat = [rotmat; zeros(1, length([dipsel(:);refdipsel(:)])), rsup, zeros(1,length([refchansel(:);supchansel(:)]))];
      end
      for j=1:length(supchansel)
        rotmat(end+1,:) = 0;
        rotmat(end,length([dipsel(:);refdipsel(:);supdipsel(:)])+j) = 1;
      end
      for j=1:length(refchansel)
        rotmat(end+1,:) = 0;
        rotmat(end,length([dipsel(:);refdipsel(:);supdipsel(:);supchansel(:)])+j) = 1;
      end

      % compute voxel-level csd-matrix
      source.avg.csd{i}      = rotmat * source.avg.csd{i} * rotmat';
      % compute voxel-level noisecsd-matrix
      if isfield(source.avg, 'noisecsd'), source.avg.noisecsd{i} = rotmat * source.avg.noisecsd{i} * rotmat'; end
      % compute rotated filter
      if isfield(source.avg, 'filter'),   source.avg.filter{i}   = rotmat * source.avg.filter{i}; end
      % compute rotated leadfield
      % FIXME in the presence of a refdip and/or supdip, this does not work; leadfield is Nx3
      if isfield(source,  'leadfield'),   source.leadfield{i}    = source.leadfield{i} * rotmat'; end
    end %for diplop
    progress('close');

    % remember what the interpretation is of all CSD output components
    scandiplabel = repmat({'scandip'}, 1, 1);                    % only one dipole orientation remains
    refdiplabel  = repmat({'refdip'},  1, length(refdipsel)>0);  % for svdfft at max. only one dipole orientation remains
    supdiplabel  = repmat({'supdip'},  1, length(supdipsel)>0);  % for svdfft at max. only one dipole orientation remains
    refchanlabel = repmat({'refchan'}, 1, length(refchansel));
    supchanlabel = repmat({'supchan'}, 1, length(supchansel));
    % concatenate all the labels
    source.avg.csdlabel = cat(2, scandiplabel, refdiplabel, supdiplabel, refchanlabel, supchanlabel);
    % update the indices
    dipsel     = match_str(source.avg.csdlabel, 'scandip');
    refchansel = match_str(source.avg.csdlabel, 'refchan');
    refdipsel  = match_str(source.avg.csdlabel, 'refdip');
    supchansel = match_str(source.avg.csdlabel, 'supchan');
    supdipsel  = match_str(source.avg.csdlabel, 'supdip');
    refsel     = [refdipsel refchansel];
    supsel     = [supdipsel supchansel];
  end % if projectmom

  if keeptrials
    cumtapcnt = source.cumtapcnt(:);
    sumtapcnt = cumsum([0;cumtapcnt]);
    Ntrial = length(cumtapcnt);

    progress('init', cfg.feedback, 'computing singletrial voxel-level cross-spectral densities');
    for triallop = 1:Ntrial
      source.trial(triallop).csd = cell(Ndipole, 1);  % allocate memory for this trial
      source.trial(triallop).mom = cell(Ndipole, 1);  % allocate memory for this trial

      progress(triallop/Ntrial, 'computing singletrial voxel-level cross-spectral densities %d%d\n', triallop, Ntrial);
      for diplop=1:length(source.inside)
        i   = source.inside(diplop);
        dat = source.avg.mom{i};
        tmpmom = dat(:, sumtapcnt(triallop)+1:sumtapcnt(triallop+1));
        tmpcsd = [tmpmom * tmpmom'] ./cumtapcnt(triallop);
        source.trial(triallop).mom{i} = tmpmom;
        source.trial(triallop).csd{i} = tmpcsd;
      end %for diplop
    end % for triallop
    progress('close');
    % remove the average, continue with separate trials
    source = rmfield(source, 'avg');
  else
    fprintf('using average voxel-level cross-spectral densities\n');
  end % if keeptrials

  if keeptrials
    % do the processing of the CSD matrices for each trial
    if ~strcmp(cfg.supmethod, 'none')
      error('suppression is only supported for average CSD');
    end

    progress('init', cfg.feedback, 'computing singletrial voxel-level power');
    for triallop = 1:Ntrial
      % initialize the variables
      source.trial(triallop).pow = zeros(Ndipole, 1);
      if ~isempty(refdipsel),  source.trial(triallop).refdippow     = zeros(Ndipole, 1); end
      if ~isempty(refchansel), source.trial(triallop).refchanpow    = zeros(Ndipole, 1); end
      if ~isempty(supdipsel),  source.trial(triallop).supdippow     = zeros(Ndipole, 1); end
      if ~isempty(supchansel), source.trial(triallop).supchanpow    = zeros(Ndipole, 1); end

      progress(triallop/Ntrial, 'computing singletrial voxel-level power %d%d\n', triallop, Ntrial);
      for diplop = 1:length(source.inside)
        i = source.inside(diplop);
        % compute the power of each source component
        source.trial(triallop).pow(i) = powmethodfun(source.trial(triallop).csd{i}(dipsel,dipsel));
        if ~isempty(refdipsel),  source.trial(triallop).refdippow(i)  = powmethodfun(source.trial(triallop).csd{i}(refdipsel,refdipsel));   end
        if ~isempty(supdipsel),  source.trial(triallop).supdippow(i)  = powmethodfun(source.trial(triallop).csd{i}(supdipsel,supdipsel));   end
        if ~isempty(refchansel), source.trial(triallop).refchanpow(i) = powmethodfun(source.trial(triallop).csd{i}(refchansel,refchansel)); end
        if ~isempty(supchansel), source.trial(triallop).supchanpow(i) = powmethodfun(source.trial(triallop).csd{i}(supchansel,supchansel)); end
        %FIXME kan volgens mij niet
        if isnoise && isfield(source.trial(triallop), 'noisecsd'),
          % compute the power of the noise projected on each source component
          source.trial(triallop).noise(i) = powmethodfun(source.trial(triallop).noisecsd{i}(dipsel,dipsel));
          if ~isempty(refdipsel),  source.trial(triallop).refdipnoise(i)  = powmethodfun(source.trial(triallop).noisecsd{i}(refdipsel,refdipsel));   end
          if ~isempty(supdipsel),  source.trial(triallop).supdipnoise(i)  = powmethodfun(source.trial(triallop).noisecsd{i}(supdipsel,supdipsel));   end
          if ~isempty(refchansel), source.trial(triallop).refchannoise(i) = powmethodfun(source.trial(triallop).noisecsd{i}(refchansel,refchansel)); end
          if ~isempty(supchansel), source.trial(triallop).supchannoise(i) = powmethodfun(source.trial(triallop).noisecsd{i}(supchansel,supchansel)); end
        end % if isnoise
      end % for diplop
    end % for triallop
    progress('close');

    if strcmp(cfg.keepcsd, 'no')
      source.trial = rmfield(source.trial, 'csd');
    end
  else
    % do the processing of the average CSD matrix
    for diplop = 1:length(source.inside)
      i = source.inside(diplop);
      switch cfg.supmethod
        case 'chan_dip'
          supindx = [supdipsel supchansel];
          if diplop==1, refsel  = refsel - length(supdipsel); end%adjust index only once
        case 'chan'
          supindx = [supchansel];
        case 'dip'
          supindx = [supdipsel];
          if diplop==1, refsel  = refsel - length(supdipsel); end
        case 'none'
          % do nothing
          supindx = [];
      end
      tmpcsd  = source.avg.csd{i};
      scnindx = setdiff(1:size(tmpcsd,1), supindx);
      tmpcsd  = tmpcsd(scnindx, scnindx) - [tmpcsd(scnindx, supindx)*pinv(tmpcsd(supindx, supindx))*tmpcsd(supindx, scnindx)];
      source.avg.csd{i}   = tmpcsd;
    end % for diplop
    source.avg.csdlabel = source.avg.csdlabel(scnindx);
    if isnoise && ~strcmp(cfg.supmethod, 'none')
      source.avg = rmfield(source.avg, 'noisecsd');
    end

    % initialize the variables
    source.avg.pow           = nan*zeros(Ndipole, 1);
    if ~isempty(refdipsel),  source.avg.refdippow     = nan*zeros(Ndipole, 1); end
    if ~isempty(refchansel), source.avg.refchanpow    = nan*zeros(Ndipole, 1); end
    if ~isempty(supdipsel),  source.avg.supdippow     = nan*zeros(Ndipole, 1); end
    if ~isempty(supchansel), source.avg.supchanpow    = nan*zeros(Ndipole, 1); end
    if isnoise
      source.avg.noise         = nan*zeros(Ndipole, 1);
      if ~isempty(refdipsel),  source.avg.refdipnoise     = nan*zeros(Ndipole, 1); end
      if ~isempty(refchansel), source.avg.refchannoise    = nan*zeros(Ndipole, 1); end
      if ~isempty(supdipsel),  source.avg.supdipnoise     = nan*zeros(Ndipole, 1); end
      if ~isempty(supchansel), source.avg.supchannoise    = nan*zeros(Ndipole, 1); end
    end % if isnoise
    if ~isempty(refsel),       source.avg.coh           = nan*zeros(Ndipole, 1); end
    if strcmp(cfg.eta, 'yes'), 
      source.avg.eta           = nan*zeros(Ndipole, 1);
      source.avg.ori           = cell(1, Ndipole);
    end

    for diplop = 1:length(source.inside)
      i = source.inside(diplop);

      % compute the power of each source component
      source.avg.pow(i) = powmethodfun(source.avg.csd{i}(dipsel,dipsel));
      if ~isempty(refdipsel),  source.avg.refdippow(i)  = powmethodfun(source.avg.csd{i}(refdipsel,refdipsel));   end
      if ~isempty(supdipsel),  source.avg.supdippow(i)  = powmethodfun(source.avg.csd{i}(supdipsel,supdipsel));   end
      if ~isempty(refchansel), source.avg.refchanpow(i) = powmethodfun(source.avg.csd{i}(refchansel,refchansel)); end
      if ~isempty(supchansel), source.avg.supchanpow(i) = powmethodfun(source.avg.csd{i}(supchansel,supchansel)); end
      if isnoise
        % compute the power of the noise projected on each source component
        source.avg.noise(i) = powmethodfun(source.avg.noisecsd{i}(dipsel,dipsel));
        if ~isempty(refdipsel),  source.avg.refdipnoise(i)  = powmethodfun(source.avg.noisecsd{i}(refdipsel,refdipsel));   end
        if ~isempty(supdipsel),  source.avg.supdipnoise(i)  = powmethodfun(source.avg.noisecsd{i}(supdipsel,supdipsel));   end
        if ~isempty(refchansel), source.avg.refchannoise(i) = powmethodfun(source.avg.noisecsd{i}(refchansel,refchansel)); end
        if ~isempty(supchansel), source.avg.supchannoise(i) = powmethodfun(source.avg.noisecsd{i}(supchansel,supchansel)); end
      end % if isnoise

      if ~isempty(refsel)
        % compute coherence
        csd = source.avg.csd{i};
        switch cfg.cohmethod
          case 'regular'
            % assume that all dipoles have been projected along the direction of maximum power
            Pd                = abs(csd(dipsel, dipsel));
            Pr                = abs(csd(refsel, refsel));
            Cdr               = csd(dipsel, refsel);
            source.avg.coh(i) = (Cdr.^2) ./ (Pd*Pr);
          case 'lambda1'
            %compute coherence on Joachim Gross' way
            Pd                = lambda1(csd(dipsel, dipsel));
            Pr                = lambda1(csd(refsel, refsel));
            Cdr               = lambda1(csd(dipsel, refsel));
            source.avg.coh(i) = abs(Cdr).^2 ./ (Pd*Pr);
          case 'canonical'
            [ccoh, c2, v1, v2] = cancorr(csd, dipsel, refsel);
            [cmax, indmax]     = max(ccoh);
            source.avg.coh(i)  = ccoh(indmax);
          otherwise
            error('unsupported cohmethod');
        end % cohmethod
      end

      % compute eta
      if strcmp(cfg.eta, 'yes')
        [source.avg.eta(i), source.avg.ori{i}] = csd2eta(source.avg.csd{i}(dipsel,dipsel));
      end
    end % for diplop

    if strcmp(cfg.keepcsd, 'no')
      source.avg = rmfield(source.avg, 'csd');
    end
    if strcmp(cfg.keepcsd, 'no') && isnoise
      source.avg = rmfield(source.avg, 'noisecsd');
    end
  end

elseif islcmvavg
  % the source reconstruction was computed using the lcmv beamformer and contains an average timecourse
  
  if projectmom
    progress('init', cfg.feedback, 'projecting dipole moment');
    for diplop=1:length(source.inside)
      progress(diplop/length(source.inside), 'projecting dipole moment %d/%d\n', diplop, length(source.inside));
      mom = source.avg.mom{source.inside(diplop)};
      [mom, rmom] = svdfft(mom, 1);
      source.avg.mom{source.inside(diplop)} = mom;
      source.avg.ori{source.inside(diplop)} = rmom;
    end
    progress('close');
  end

  if ~strcmp(cfg.powmethod, 'none')
    fprintf('recomputing power based on dipole timecourse\n')
    source.avg.pow = nan*zeros(size(source.pos,1),1);
    for diplop=1:length(source.inside)
      mom = source.avg.mom{source.inside(diplop)};
      cov = mom * mom';
      source.avg.pow(source.inside(diplop)) = powmethodfun(cov);
    end
  end

  if strcmp(cfg.kurtosis, 'yes')
    fprintf('computing kurtosis based on dipole timecourse\n');
    source.avg.k2 = nan*zeros(size(source.pos,1),1);
    for diplop=1:length(source.inside)
      mom = source.avg.mom{source.inside(diplop)};
      if length(mom)~=prod(size(mom))
        error('kurtosis can only be computed for projected dipole moment');
      end
      source.avg.k2(source.inside(diplop)) = kurtosis(mom);
    end
  end

elseif islcmvtrl
  % the source reconstruction was computed using the lcmv beamformer and contains a single-trial timecourse
  ntrial = length(source.trial);
  
  if projectmom && strcmp(cfg.fixedori, 'within_trials')
    % the dipole orientation is re-determined for each trial
    progress('init', cfg.feedback, 'projecting dipole moment');
    for trllop=1:ntrial
      progress(trllop/ntrial, 'projecting dipole moment %d/%d\n', trllop, ntrial);
      for diplop=1:length(source.inside)
        mom = source.trial(trllop).mom{source.inside(diplop)};
        [mom, rmom] = svdfft(mom, 1);
        source.trial(trllop).mom{source.inside(diplop)} = mom;
        source.trial(trllop).ori{source.inside(diplop)} = rmom;  % remember the orientation
      end
    end
    progress('close');
  elseif projectmom && strcmp(cfg.fixedori, 'over_trials')
    progress('init', cfg.feedback, 'projecting dipole moment');
    % compute average covariance over all trials
    for trllop=1:ntrial
      for diplop=1:length(source.inside)
        mom = source.trial(trllop).mom{source.inside(diplop)};
        if trllop==1
          cov{diplop} = mom*mom'./size(mom,2);
        else
          cov{diplop} = mom*mom'./size(mom,2) + cov{diplop};
        end
      end
    end
    % compute source orientation over all trials
    for diplop=1:length(source.inside)
      [dum, ori{diplop}] = svdfft(cov{diplop}, 1);
    end
    % project the data in each trial
    for trllop=1:ntrial
      progress(trllop/ntrial, 'projecting dipole moment %d/%d\n', trllop, ntrial);
      for diplop=1:length(source.inside)
        mom = source.trial(trllop).mom{source.inside(diplop)};
        mom = ori{diplop}*mom;
        source.trial(trllop).mom{source.inside(diplop)} = mom;
        source.trial(trllop).ori{source.inside(diplop)} = ori{diplop};
      end
    end
    progress('close');
  end

  if ~strcmp(cfg.powmethod, 'none')
    fprintf('recomputing power based on dipole timecourse\n')
    for trllop=1:ntrial
      for diplop=1:length(source.inside)
        mom = source.trial(trllop).mom{source.inside(diplop)};
        cov = mom * mom';
        source.trial(trllop).pow(source.inside(diplop)) = powmethodfun(cov);
      end
    end
  end

  if strcmp(cfg.kurtosis, 'yes')
    fprintf('computing kurtosis based on dipole timecourse\n');
    for trllop=1:ntrial
      source.trial(trllop).k2 = nan*zeros(size(source.pos,1),1);
      for diplop=1:length(source.inside)
        mom = source.trial(trllop).mom{source.inside(diplop)};
        if length(mom)~=prod(size(mom))
          error('kurtosis can only be computed for projected dipole moment');
        end
        source.trial(trllop).k2(source.inside(diplop)) = kurtosis(mom);
      end
    end
  end

end % dealing with pcc or lcmv input

if isfield(source, 'avg') && isfield(source.avg, 'pow') && isfield(source.avg, 'noise')
  % compute the neural activity index for the average
  source.avg.nai = source.avg.pow(:) ./ source.avg.noise(:);
end

if isfield(source, 'trial') && isfield(source.trial, 'pow') && isfield(source.trial, 'noise')
  % compute the neural activity index for the trials
  ntrials = length(source.trial);
  for trlop=1:ntrials
    source.trial(trlop).nai = source.trial(trlop).pow ./ source.trial(trlop).noise;
  end
end

if strcmp(source.method, 'randomization') || strcmp(source.method, 'permutation')
  % compute the neural activity index for the two randomized conditions
  source.avgA.nai = source.avgA.pow ./ source.avgA.noise;
  source.avgB.nai = source.avgB.pow ./ source.avgB.noise;
  for trlop=1:length(source.trialA)
    source.trialA(trlop).nai = source.trialA(trlop).pow ./ source.trialA(trlop).noise;
  end
  for trlop=1:length(source.trialB)
    source.trialB(trlop).nai = source.trialB(trlop).pow ./ source.trialB(trlop).noise;
  end
end

if ~isempty(cfg.transform)
  fprintf('applying %s transformation on the power and projected noise\n', cfg.transform);
  % apply the specified transformation on the power
  if isfield(source, 'avg'   ) && isfield(source.avg   , 'pow'), source.avg .pow = feval(cfg.transform, source.avg .pow); end
  if isfield(source, 'avgA'  ) && isfield(source.avgA  , 'pow'), source.avgA.pow = feval(cfg.transform, source.avgA.pow); end
  if isfield(source, 'avgB'  ) && isfield(source.avgB  , 'pow'), source.avgB.pow = feval(cfg.transform, source.avgB.pow); end
  if isfield(source, 'trial' ) && isfield(source.trial , 'pow'), for i=1:length(source.trial ), source.trial (i).pow = feval(cfg.transform, source.trial (i).pow); end; end
  if isfield(source, 'trialA') && isfield(source.trialA, 'pow'), for i=1:length(source.trialA), source.trialA(i).pow = feval(cfg.transform, source.trialA(i).pow); end; end
  if isfield(source, 'trialB') && isfield(source.trialB, 'pow'), for i=1:length(source.trialB), source.trialB(i).pow = feval(cfg.transform, source.trialB(i).pow); end; end
  % apply the specified transformation on the projected noise
  if isfield(source, 'avg'   ) && isfield(source.avg   , 'noise'), source.avg .noise = feval(cfg.transform, source.avg .noise); end
  if isfield(source, 'avgA'  ) && isfield(source.avgA  , 'noise'), source.avgA.noise = feval(cfg.transform, source.avgA.noise); end
  if isfield(source, 'avgB'  ) && isfield(source.avgB  , 'noise'), source.avgB.noise = feval(cfg.transform, source.avgB.noise); end
  if isfield(source, 'trial' ) && isfield(source.trial , 'noise'), for i=1:length(source.trial ), source.trial (i).noise = feval(cfg.transform, source.trial (i).noise); end; end
  if isfield(source, 'trialA') && isfield(source.trialA, 'noise'), for i=1:length(source.trialA), source.trialA(i).noise = feval(cfg.transform, source.trialA(i).noise); end; end
  if isfield(source, 'trialB') && isfield(source.trialB, 'noise'), for i=1:length(source.trialB), source.trialB(i).noise = feval(cfg.transform, source.trialB(i).noise); end; end
end

if strcmp(source.method, 'pseudovalue')
  % compute the pseudovalues for the beamformer output
  avg = source.trial(1);		% the first is the complete average
  Ntrials = length(source.trial)-1;	% the remaining are the leave-one-out averages
  pseudoval = [];
  if isfield(source.trial, 'pow')
    allavg = getfield(avg, 'pow');
    for i=1:Ntrials
      thisavg = getfield(source.trial(i+1), 'pow');
      thisval = Ntrials*allavg - (Ntrials-1)*thisavg;
      pseudoval(i).pow = thisval;
    end
  end
  if isfield(source.trial, 'coh')
    allavg = getfield(avg, 'coh');
    for i=1:Ntrials
      thisavg = getfield(source.trial(i+1), 'coh');
      thisval = Ntrials*allavg - (Ntrials-1)*thisavg;
      pseudoval(i).coh = thisval;
    end
  end
  if isfield(source.trial, 'nai')
    allavg = getfield(avg, 'nai');
    for i=1:Ntrials
      thisavg = getfield(source.trial(i+1), 'nai');
      thisval = Ntrials*allavg - (Ntrials-1)*thisavg;
      pseudoval(i).nai = thisval;
    end
  end
  if isfield(source.trial, 'noise')
    allavg = getfield(avg, 'noise');
    for i=1:Ntrials
      thisavg = getfield(source.trial(i+1), 'noise');
      thisval = Ntrials*allavg - (Ntrials-1)*thisavg;
      pseudoval(i).noise = thisval;
    end
  end
  % store the pseudovalues instead of the original values
  source.trial = pseudoval;
end

if strcmp(source.method, 'jackknife') || strcmp(source.method, 'bootstrap') || strcmp(source.method, 'pseudovalue') || strcmp(source.method, 'singletrial') || strcmp(source.method, 'rawtrial')
  % compute descriptive statistics (mean, var, sem) for multiple trial data
  % compute these for as many source parameters as possible

  % for convenience copy the trials out of the source structure
  dip = source.trial;

  % determine the (original) number of trials in the data
  if strcmp(source.method, 'bootstrap') %VERANDERD ER ZAT GEEN .RESAMPLE IN SOURCE
    Ntrials = size(source.trial,2);% WAS size(source.resample, 2);
  else
    Ntrials = length(source.trial);
  end
  fprintf('original data contained %d trials\n', Ntrials);

  % allocate memory for all elements in the dipole structure
  sumdip = [];
  if isfield(dip(1), 'var'),   sumdip.var    = zeros(size(dip(1).var  )); sumdip.var(source.outside)=nan;   end
  if isfield(dip(1), 'pow'),   sumdip.pow    = zeros(size(dip(1).pow  )); sumdip.pow(source.outside)=nan;   end
  if isfield(dip(1), 'coh'),   sumdip.coh    = zeros(size(dip(1).coh  )); sumdip.coh(source.outside)=nan;   end
  if isfield(dip(1), 'rv'),    sumdip.rv     = zeros(size(dip(1).rv   )); sumdip.rv(source.outside)=nan;    end
  if isfield(dip(1), 'noise'), sumdip.noise  = zeros(size(dip(1).noise)); sumdip.noise(source.outside)=nan; end
  if isfield(dip(1), 'nai'),   sumdip.nai    = zeros(size(dip(1).nai  )); sumdip.nai(source.outside)=nan;   end
  sqrdip = [];
  if isfield(dip(1), 'var'),   sqrdip.var    = zeros(size(dip(1).var  )); sqrdip.var(source.outside)=nan;   end
  if isfield(dip(1), 'pow'),   sqrdip.pow    = zeros(size(dip(1).pow  )); sqrdip.pow(source.outside)=nan;   end
  if isfield(dip(1), 'coh'),   sqrdip.coh    = zeros(size(dip(1).coh  )); sqrdip.coh(source.outside)=nan;   end
  if isfield(dip(1), 'rv'),    sqrdip.rv     = zeros(size(dip(1).rv   )); sqrdip.rv(source.outside)=nan;    end
  if isfield(dip(1), 'noise'), sqrdip.noise  = zeros(size(dip(1).noise)); sqrdip.noise(source.outside)=nan; end
  if isfield(dip(1), 'nai'),   sqrdip.nai    = zeros(size(dip(1).nai  )); sqrdip.nai(source.outside)=nan;   end
  if isfield(dip(1), 'mom')
    sumdip.mom = cell(size(dip(1).mom));
    sqrdip.mom = cell(size(dip(1).mom));
    for i=1:length(dip(1).mom)
      sumdip.mom{i} = nan*zeros(size(dip(1).mom{i}));
      sqrdip.mom{i} = nan*zeros(size(dip(1).mom{i}));
    end
  end
  if isfield(dip(1), 'csd')
    sumdip.csd = cell(size(dip(1).csd));
    sqrdip.csd = cell(size(dip(1).csd));
    for i=1:length(dip(1).csd)
      sumdip.csd{i} = nan*zeros(size(dip(1).csd{i}));
      sqrdip.csd{i} = nan*zeros(size(dip(1).csd{i}));
    end
  end

  for trial=1:length(dip)
    % compute the sum of all values
    if isfield(dip(trial), 'var'),    sumdip.var   = sumdip.var    + dip(trial).var;    end
    if isfield(dip(trial), 'pow'),    sumdip.pow   = sumdip.pow    + dip(trial).pow;    end
    if isfield(dip(trial), 'coh'),    sumdip.coh   = sumdip.coh    + dip(trial).coh;    end
    if isfield(dip(trial), 'rv'),     sumdip.rv    = sumdip.rv     + dip(trial).rv;     end
    if isfield(dip(trial), 'noise'),  sumdip.noise = sumdip.noise  + dip(trial).noise;  end
    if isfield(dip(trial), 'nai'),    sumdip.nai   = sumdip.nai    + dip(trial).nai;    end
    % compute the sum of squared values
    if isfield(dip(trial), 'var'),    sqrdip.var    = sqrdip.var   + (dip(trial).var  ).^2; end
    if isfield(dip(trial), 'pow'),    sqrdip.pow    = sqrdip.pow   + (dip(trial).pow  ).^2; end
    if isfield(dip(trial), 'coh'),    sqrdip.coh    = sqrdip.coh   + (dip(trial).coh  ).^2; end
    if isfield(dip(trial), 'rv'),     sqrdip.rv     = sqrdip.rv    + (dip(trial).rv   ).^2; end
    if isfield(dip(trial), 'noise'),  sqrdip.noise  = sqrdip.noise + (dip(trial).noise).^2; end
    if isfield(dip(trial), 'nai'),    sqrdip.nai    = sqrdip.nai   + (dip(trial).nai  ).^2; end
    % do the same for the cell array with mom
    if isfield(dip(trial), 'mom')
      for i=1:length(dip(1).mom)
        sumdip.mom{i} = sumdip.mom{i} +  dip(trial).mom{i};
        sqrdip.mom{i} = sqrdip.mom{i} + (dip(trial).mom{i}).^2;
      end
    end
    % do the same for the cell array with csd
    if isfield(dip(trial), 'csd')
      for i=1:length(dip(1).csd)
        sumdip.csd{i} = sumdip.csd{i} +  dip(trial).csd{i};
        sqrdip.csd{i} = sqrdip.csd{i} + (dip(trial).csd{i}).^2;
      end
    end
  end

  % compute the mean over all repetitions
  if isfield(sumdip, 'var'),    dipmean.var    = sumdip.var   / length(dip); end
  if isfield(sumdip, 'pow'),    dipmean.pow    = sumdip.pow   / length(dip); end
  if isfield(sumdip, 'coh'),    dipmean.coh    = sumdip.coh   / length(dip); end
  if isfield(sumdip, 'rv'),     dipmean.rv     = sumdip.rv    / length(dip); end
  if isfield(sumdip, 'noise'),  dipmean.noise  = sumdip.noise / length(dip); end
  if isfield(sumdip, 'nai'),    dipmean.nai    = sumdip.nai   / length(dip); end
  % for the cell array with mom, this is done further below
  % for the cell array with csd, this is done further below

  % the estimates for variance and SEM are biased if we are working with the jackknife/bootstrap
  % determine the proper variance scaling that corrects for this bias
  % note that Ntrials is not always the same as the length of dip, especially in case of the bootstrap
  if strcmp(source.method, 'singletrial')
    bias = 1;
  elseif strcmp(source.method, 'rawtrial')
    bias = 1;
  elseif strcmp(source.method, 'jackknife')
    % Effron gives SEM estimate for the jackknife method in equation 11.5 (paragraph 11.2)
    % to get the variance instead of SEM, we also have to multiply with the number of trials
    bias = (Ntrials - 1)^2;
  elseif strcmp(source.method, 'bootstrap')
    % Effron gives SEM estimate for the bootstrap method in algorithm 6.1 (equation 6.6)
    % to get the variance instead of SEM, we also have to multiply with the number of trials
    bias = Ntrials;
  elseif strcmp(source.method, 'pseudovalue')
    % note that I have not put any thought in this aspect yet
    warning('don''t know how to compute bias for pseudovalue resampling');
    bias = 1;
  end

  % compute the variance over all repetitions
  if isfield(sumdip, 'var'),    dipvar.var    = bias*(sqrdip.var    - (sumdip.var   .^2)/length(dip))/(length(dip)-1); end
  if isfield(sumdip, 'pow'),    dipvar.pow    = bias*(sqrdip.pow    - (sumdip.pow   .^2)/length(dip))/(length(dip)-1); end
  if isfield(sumdip, 'coh'),    dipvar.coh    = bias*(sqrdip.coh    - (sumdip.coh   .^2)/length(dip))/(length(dip)-1); end
  if isfield(sumdip, 'rv' ),    dipvar.rv     = bias*(sqrdip.rv     - (sumdip.rv    .^2)/length(dip))/(length(dip)-1); end
  if isfield(sumdip, 'noise' ), dipvar.noise  = bias*(sqrdip.noise  - (sumdip.noise .^2)/length(dip))/(length(dip)-1); end
  if isfield(sumdip, 'nai' ),   dipvar.nai    = bias*(sqrdip.nai    - (sumdip.nai   .^2)/length(dip))/(length(dip)-1); end

  % compute the SEM over all repetitions
  if isfield(sumdip, 'var'),    dipsem.var    = (dipvar.var   /Ntrials).^0.5; end
  if isfield(sumdip, 'pow'),    dipsem.pow    = (dipvar.pow   /Ntrials).^0.5; end
  if isfield(sumdip, 'coh'),    dipsem.coh    = (dipvar.coh   /Ntrials).^0.5; end
  if isfield(sumdip, 'rv' ),    dipsem.rv     = (dipvar.rv    /Ntrials).^0.5; end
  if isfield(sumdip, 'noise' ), dipsem.noise  = (dipvar.noise /Ntrials).^0.5; end
  if isfield(sumdip, 'nai' ),   dipsem.nai    = (dipvar.nai   /Ntrials).^0.5; end

  % compute the mean and SEM over all repetitions for the cell array with mom
  if isfield(dip(trial), 'mom')
    for i=1:length(dip(1).mom)
      dipmean.mom{i} = sumdip.mom{i}/length(dip);
      dipvar.mom{i} = bias*(sqrdip.mom{i} - (sumdip.mom{i}.^2)/length(dip))/(length(dip)-1);
      dipsem.mom{i} = (dipvar.mom{i}/Ntrials).^0.5;
    end
  end

  % compute the mean and SEM over all repetitions for the cell array with csd
  if isfield(dip(trial), 'csd')
    for i=1:length(dip(1).csd)
      dipmean.csd{i} = sumdip.csd{i}/length(dip);
      dipvar.csd{i} = bias*(sqrdip.csd{i} - (sumdip.csd{i}.^2)/length(dip))/(length(dip)-1);
      dipsem.csd{i} = (dipvar.csd{i}/Ntrials).^0.5;
    end
  end

  if strcmp(source.method, 'pseudovalue')
    % keep the trials, since they have been converted to pseudovalues
    % and hence the trials contain the interesting data
  elseif keeptrials
    % keep the trials upon request
  else
    % remove the original trials
    source = rmfield(source, 'trial');
    % assign the descriptive statistics to the output source structure
    source.avg = dipmean;
    source.var = dipvar;
    source.sem = dipsem;
  end
end

if strcmp(cfg.resolutionmatrix, 'yes')
  % this is only implemented for pcc and no refdips/chans at the moment
  Nchan        = size(source.leadfield{source.inside(1)}, 1);
  Ninside      = length(source.inside);
  allfilter    = zeros(Ninside,Nchan);
  allleadfield = zeros(Nchan,Ninside);
  dipsel       = match_str(source.avg.csdlabel, 'scandip');
  progress('init', cfg.feedback, 'computing resolution matrix');
  for diplop=1:length(source.inside)
    progress(diplop/length(source.inside), 'computing resolution matrix %d/%d\n', diplop, length(source.inside));
    i = source.inside(diplop);
    % concatenate all filters
    allfilter(diplop,:) = source.avg.filter{i}(dipsel,:);
    % concatenate all leadfields
    allleadfield(:,diplop) = source.leadfield{i};
  end
  progress('close');
  % multiply the filters and leadfields to obtain the resolution matrix
  % see equation 1 and 2 in De Peralta-Menendez RG, Gonzalez-Andino SL: A critical analysis of linear inverse solutions to the neuroelectromagnetic inverse problem. IEEE Transactions on Biomedical Engineering 45: 440-448, 1998.
  source.resolution = nan*zeros(Ndipole, Ndipole);
  source.resolution(source.inside, source.inside) = allfilter*allleadfield;
end

% get the output cfg
cfg = checkconfig(cfg, 'trackconfig', 'off', 'checksize', 'yes'); 

% add version information to the configuration
try
  % get the full name of the function
  cfg.version.name = mfilename('fullpath');
catch
  % required for compatibility with Matlab versions prior to release 13 (6.5)
  [st, i] = dbstack;
  cfg.version.name = st(i);
end
cfg.version.id = '$Id: sourcedescriptives.m,v 1.1 2009-07-07 02:23:16 arno Exp $';
% remember the configuration details of the input data
try, cfg.previous = source.cfg; end
% remember the exact configuration details in the output
source.cfg = cfg;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% helper function to compute eta from a csd-matrix
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function [eta, u] = csd2eta(csd)
[u,s,v] = svd(real(csd));
eta     = s(2,2)./s(1,1);
u       = u'; %orientation is defined in the rows

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% helper function to compute power
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function p = powmethod_lambda1(x);
s = svd(x);
p = s(1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% helper function to compute power
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function p = powmethod_trace(x);
p = trace(x);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% helper function to compute power
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function p = powmethod_regular(x);
p = abs(x);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% helper function to obtain the largest singular value or trace of the
% source CSD matrices resulting from DICS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function s = lambda1(x);
s = svd(x);
s = s(1);
