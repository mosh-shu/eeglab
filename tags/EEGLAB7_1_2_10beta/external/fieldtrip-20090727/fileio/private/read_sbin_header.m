function [header_array, CateNames, CatLengths, preBaseline] = read_sbin_header(filename)

% READ_SBIN_HEADER reads the header information from an EGI segmented simple binary format file
%
% Use as
%   [header_array, CateNames, CatLengths, preBaseline] = read_sbin_header(filename)
% with
%   header_array     - differs between versions, read code for details
%   CateNames        - category names
%   CatLengths       - length of category names
%   preBaseline      - number of samples in the baseline prior to the baseline event
% and
%   filename    - the name of the data file
%
% Since there is no unique event code for the segmentation event, and hence the baseline period,
% the first event code in the list will be assumed to be the segmentation event.
% NetStation itself simply ignores possible baseline information when importing simple binary files.
%_______________________________________________________________________
%
%
% Modified from EGI's readEGLY.m with permission 2008-03-31 Joseph Dien
%

% $Log: not supported by cvs2svn $
% Revision 1.5  2009/05/14 18:00:13  josdie
% Added error message to read_sbin_header to handle case where version is an empty set.
%
% Revision 1.4  2009/04/29 10:55:16  jansch
% incorporated handling of unsegmented files
%
% Revision 1.3  2009/03/11 16:12:09  josdie
% Changed category names to cell variables to better support names with differing lengths.
%
% Revision 1.2  2009/03/05 01:03:13  josdie
% Improved process of deducing what the stimulus onset latency is in files with multiple events.
%
% Revision 1.1  2009/01/14 09:12:15  roboos
% The directory layout of fileio in cvs sofar did not include a
% private directory, but for the release of fileio all the low-level
% functions were moved to the private directory to make the distinction
% between the public API and the private low level functions. To fix
% this, I have created a private directory and moved all appropriate
% files from fileio to fileio/private.
%
% Revision 1.4  2008/12/08 09:36:49  roboos
% added cvs log to the matlab files
%

fid=fopen([filename],'r');
if fid==-1
    error('wrong filename')
end

version		= fread(fid,1,'int32');
if isempty(version)
    error('ERROR:  This is not a simple binary file.  Note that NetStation does not successfully directly convert EGIS files to simple binary format.');
end;

%check byteorder
[str,maxsize,cEndian]=computer;
if version < 7
    if cEndian == 'B'
        endian = 'ieee-be';
    elseif cEndian == 'L'
        endian = 'ieee-le';
    end;
elseif (version > 6) && ~bitand(version,6)
    if cEndian == 'B'
        endian = 'ieee-le';
    elseif cEndian == 'L'
        endian = 'ieee-be';
    end;
    version = swapbytes(uint32(version));
else
    error('ERROR:  This is not a simple binary file.  Note that NetStation does not successfully directly convert EGIS files to simple binary format.');
end;

if bitand(version,1) == 0
    %error('ERROR:  This is an unsegmented file, which is not supported.');
    unsegmented = 1;
else
    unsegmented = 0;
end;

precision = bitand(version,6);
if precision == 0
    error('File precision is not defined.');
end;

%		read header...
year		= fread(fid,1,'int16',endian);
month		= fread(fid,1,'int16',endian);
day			= fread(fid,1,'int16',endian);
hour		= fread(fid,1,'int16',endian);
minute		= fread(fid,1,'int16',endian);
second		= fread(fid,1,'int16',endian);
millisecond = fread(fid,1,'int32',endian);
Samp_Rate	= fread(fid,1,'int16',endian);
NChan		= fread(fid,1,'int16',endian);
Gain 		= fread(fid,1,'int16',endian);
Bits 		= fread(fid,1,'int16',endian);
Range 		= fread(fid,1,'int16',endian);

if unsegmented,
    NumCategors = 0;
    NSegments   = 1;
    NSamples    = fread(fid,1,'int32',endian);
    NEvent      = fread(fid,1,'int16',endian);
    for j = 1:NEvent
        EventCodes(j,1:4) = char(fread(fid,[1,4],'char',endian));
    end
    CateNames   = [];
    CatLengths  = [];
    preBaseline = [];
else
    NumCategors	= fread(fid,1,'int16',endian);
    for j = 1:NumCategors
        CatLengths(j)	= fread(fid,1,'int8',endian);
        for i = 1:CatLengths(j)
            CateNames{j}(i)	= char(fread(fid,1,'char',endian));
        end
    end
    NSegments	= fread(fid,1,'int16',endian);
    NSamples	= fread(fid,1,'int32',endian);			% samples per segment
    NEvent		= fread(fid,1,'int16',endian);			% num events per segment
    EventCodes = [];
    for j = 1:NEvent
        EventCodes(j,1:4)	= char(fread(fid,[1,4],'char',endian));
    end



    preBaseline=0;
    if NEvent > 0

        for j = 1:NSegments
            [segHdr(j,1), count]	= fread(fid, 1,'int16',endian);    %cell
            [segHdr(j,2), count]	= fread(fid, 1,'int32',endian);    %time stamp
            switch precision
                case 2
                    [temp,count]	= fread(fid,[NChan+NEvent, NSamples],'int16',endian);
                case 4
                    [temp,count]	= fread(fid,[NChan+NEvent, NSamples],'single',endian);
                case 6
                    [temp,count]	= fread(fid,[NChan+NEvent, NSamples],'double',endian);
            end
            if (NEvent ~= 0)
                eventData(:,((j-1)*NSamples+1):j*NSamples)	= temp( (NChan+1):(NChan+NEvent), 1:NSamples);
            end
        end

        if NEvent == 1
            %assume this is the segmentation event
            theEvent=find(eventData(1,:)>0);
            theEvent=mod(theEvent(1),NSamples);
        else
            %assume the sample that always has an event is the baseline
            %if more than one, choose the earliest one
            baselineCandidates = unique(mod(find(eventData(:,:)'),NSamples));
            counters=zeros(1,length(baselineCandidates));
            totalEventSamples=mod(find(eventData(:,:)'),NSamples);

            for i = 1:length(totalEventSamples)
                theMatch=find(ismember(baselineCandidates,totalEventSamples(i)));
                counters(theMatch)=counters(theMatch)+1;
            end;
            theEvent=min(baselineCandidates(find(ismember(counters,NSegments))));
        end;

        preBaseline=theEvent-1;
        if preBaseline == -1
            preBaseline =0;
        end;
    end
end

fclose(fid);

header_array 	= double([version year month day hour minute second millisecond Samp_Rate NChan Gain Bits Range NumCategors, NSegments, NSamples, NEvent]);


