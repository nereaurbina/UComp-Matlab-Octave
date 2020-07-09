function m = UCsetup(y,frequency,varargin)
% UCsetup - Sets up UC general univariate models 
%   
%   UCsetup sets up the model with a number of control variables that govern the
%   way the rest of functions in the package will work.
%
%   m = UCsetup(y,frequency)
%   m = UCsetup(y,frequency,'optionalvar1',optvar1,...,'optionalvarN',optvarN)
%
%   Inputs:
%       y: a time series to forecast.
%       frequency: fundamental period, number of observations per year.
%       periods: (opt) vector of fundamental period and harmonics. If not entered as input, 
%           it will be calculated from frequency.
%       u: (opt) a matrix of input time series. If the output wanted to be
%           forecast, matrix u should contain future values of inputs.
%           Default: []
%       model: (opt) the model to estimate. It is a single string indicating the
%           type of model for each component. It allows two formats
%           'trend/seasonal/irregular' or 'trend/cycle/seasonal/irregular'. The
%           possibilities available for each component are:
%           - Trend: ? / none / rw / irw / llt / dt   
%           - Seasonal: ? / none / equal / different 
%           - Irregular: ? / none / arma(0,0) / arma(p,q) - with p and q
%               integer positive orders
%           - Cycles: ? / none / combination of positive or negative numbers.
%           Positive numbers fix the period of the cycle while negative
%           values estimate the period taking as initial condition the
%           absolute value of the period supplied.
%           Several cycles with positive or negative values are possible
%           and if a question mark is included, the model test for the
%           existence of the cycles specified (check the examples below).
%           Default: '?/none/?/?'
%       outlier: (opt) critical level of outlier tests. If NaN it does not
%           carry out any outlier detection (default). A negative value
%           indicates critical minimum t test for one run of outlier detection after
%           identification. A positive value indicates the critical
%           minimum t test for outlier detection in any model during identification.
%           Default: NaN
%       stepwise: (opt) stepwise identification procedure (true,false). 
%           Default: false.
%       tTest: (opt) augmented Dickey Fuller test for unit roots (true/false).
%           The number of models to search for is reduced, depending on the
%           result of this test. Default: false
%       p0: (opt) initial condition for parameter estimates. Default: NaN
%       h: (opt) forecast horizon. If the model includes inputs h is not used,
%           the length of u is used intead. Default: NaN
%       criterion: (opt) information criterion for identification ('aic','bic' or
%           'aicc'). Default: 'aic'
%       verbose: (opt) intermediate results shown about progress of estimation
%           (true/false). Default: true
%       arma: (opt) check for arma models for irregular components (true/false).
%           Default: true
%       cLlik: (opt) reserved input
%
%   Output:
%       An object of class UComp. It is a struct with fields including all
%       the inputs and the fields listed below as outputs. All the
%       functions in this package fill in part of the fields of any UComp
%       object as specified in what follows (function UC fills in all of
%       them at once):
%           After running UCmodel or UCestim:
%               p: Estimated parameters
%               v: Estimated innovations (white noise correctly specified
%                   models)
%               yFor: Forecasted values of output
%               yForV: Variance of forecasted values of output
%               criteria: Value of criteria for estimated model
% 
%           After running UCvalidate:
%               table: Estimation and validation table
%               v: Estimated innovations (white noise correctly specified
%                   models)                    
%
%           After running UCcomponents:
%               comp: Estimated components in struct form
%               compV: Estimated components variance in struct form
%             
%           After running UCfilter, UCsmooth or UCdisturb:
%               yFit: Fitted values of output
%               yFitV: Variance of fitted values of output
%               a: State estimates
%               P: Variance of state estimates
%             
%           After running UCdisturb:
%               eta: State perturbations estimates
%               eps: Observed perturbations estimates
%
%   Authors: Diego J. Pedregal, Nerea Urbina
%
%   Examples:
%       load 'airpassengers' - contains 2 variables: y, frequency
%       m = UCsetup(log(y),frequency)
%       m = UCsetup(log(y),frequency,'model','llt/equal/arma(0,0)')
%       m = UCsetup(log(y),frequency,'outlier',4)
%
%   See also UC, UCcomponents, UCdisturb, UCestim, UCfilter, UCmodel, UCsmooth, UCvalidate

    %Set default values
    p = inputParser;
    addRequired(p,'y',@isfloat);
    addRequired(p,'frequency',@isfloat);
    defaultU = []; addParameter(p,'u',defaultU,@isfloat);
    defaultPeriods = NaN; addParameter(p,'periods',defaultPeriods,@isfloat);
    defaultModel = '?/none/?/?'; addParameter(p,'model',defaultModel,@ischar);
    defaultH = NaN; addParameter(p,'h',defaultH,@isfloat);
    defaultOutlier = NaN; addParameter(p,'outlier',defaultOutlier,@isfloat);
    defaultTTest = false; addParameter(p,'tTest',defaultTTest,@islogical);
    defaultCriterion = 'aic'; addParameter(p,'criterion',defaultCriterion,@ischar);
    defaultVerbose = true; addParameter(p,'verbose',defaultVerbose,@islogical);
    defaultStepwise = false; addParameter(p,'stepwise',defaultStepwise,@islogical);
    defaultP0 = NaN; addParameter(p,'p0',defaultP0,@isfloat);
    defaultCLlik = true; addParameter(p,'cLlik',defaultCLlik,@islogical);
    defaultArma = true; addParameter(p,'arma',defaultArma,@islogical);

    parse(p,y,frequency,varargin{:});

    h = p.Results.h;
    if(~isnan(h) && floor(h) ~= h)
        warning('h must be integer. It will be used its integer part.')
        h = floor(h);
    end
    
    u = p.Results.u;
    periods = p.Results.periods;
    if(frequency>1 && isnan(periods(1)))
        periods = frequency./(1:floor(frequency/2));
    elseif(isnan(periods(1)) && frequency<=1)
        periods=1;
    end
    periods=periods';
    model = p.Results.model;
    h = p.Results.h;
    outlier = p.Results.outlier;
    tTest = p.Results.tTest;
    criterion = p.Results.criterion;
    verbose = p.Results.verbose;
    stepwise = p.Results.stepwise;
    p0 = p.Results.p0;
    cLlik = p.Results.cLlik;
    arma = p.Results.arma;

    rhos = NaN;
    p = NaN;

    %Converting u vector to matrix
    n = length(y);
    [k, cu] = size(u);
    if (cu > 0 && cu < k)
        u = u';
    end
    if (isempty(u)) 
        u = zeros(1, 2);
    else
        h = size(u, 2) - n;
    end
    if(size(u, 2) > 2 && n > size(u, 2))
        error('Length of output data never could be greater than length of inputs');
    end
    
    % Removing nans at beginning or end
    if(isnan(y(1)) || isnan(y(n)))
        ind = find(~isnan(y));
        minInd = min(ind);
        maxInd = max(ind);
        y = y(minInd:maxInd);
        if(size(u,2) > 2)
            u = u(:,minInd:maxInd);
        end
    end

    %Checking periods
    if(isnan(periods(1)))
        error('Input "periods" should be supplied');
    end  

    %If period == 1 (anual) then change seasonal model to "none"
    if(periods(1) == 1)
        comps = strsplit(lower(model),'/');
        if(length(comps) == 3)
            model = strcat(comps{1},'/none/',comps{3});
        else
            model = strcat(comps{1},'/',comps{2},'/none/',comps{4});
        end
    end
    
    %Adding cycle in case of T/S/I model specification
    nComp = length(regexp(model,'/'));
    if(nComp == 2)
        aux = strsplit(model,'/'); 
        model = strcat(char(aux(1)),'/none/',char(aux(2)),'/',char(aux(3)));
    end
    
    %Checking model
    model = lower(model);
    if(noModel(model,periods))
        error('No model specified');
    end
    if(any(uint8(model) == uint8('?')) && ~isnan(p0(1)))
        p0 = NaN; 
    end
    if(any(uint8(model) == uint8('?')) && ~isnan(p(1)))
       p = NaN;
    end
    if(strchr(model,'arma') && isempty(strchr(model,'(')))
        model = strcat(model,'(0,0)');
    end
    if(strchr(model,'arma') && isempty(strchr(model(length(model)-1:length(model)),')')))
        model = strcat(model,')');
    end
    
    %Checking horizon 
    if(isnan(h))
        h = 18;
    end
    
    %Set rhos
    if(isnan(rhos(1)))
        rhos = ones(length(periods),1);
    end
    
    %Checking cycle
    mC0 = strsplit(lower(model),'/');
    mC0 = mC0{2}; mC = mC0;
    if(mC0 == '?')
        freq = 1;
        mC = strcat(num2str(-4*freq),'?');
    elseif(mC0(1) ~= '+' && mC0(1) ~= '-' && mC0(1) ~= 'n')
        mC = strcat('+',mC0);
    end
    model = strrep(model,strcat('/',mC0,'/'),strcat('/',mC,'/'));

    %Output:
    hidden = struct('grad',NaN,'d_t',NaN,'estimOk','Not estimated','objFunValue',0,...
        'innVariance',1,'nonStationaryTerms',NaN,'ns',NaN,'nPar',NaN,'harmonics',NaN,...
        'constPar',NaN,'typePar',NaN,'cycleLimits',NaN,'typeOutliers',-ones(1,2), ...
        'beta',NaN,'betaV',NaN);
    m = struct('y',y,'u',u,'model',model,'h',h,'comp',NaN,'compV',NaN,'p',p,'v',NaN, ...
        'yFit',NaN,'yFor',NaN,'yFitV',NaN,'yForV',NaN,'a',NaN,'P',NaN,'eta',NaN,'eps',NaN,...
        'table','','arma',arma,'outlier',-outlier,'tTest',tTest,'criterion',criterion,...
        'periods',periods,'rhos',rhos,'verbose',verbose,'stepwise',stepwise,'p0',p0,...
        'cLlik',cLlik,'criteria',NaN,'hidden',hidden);

end