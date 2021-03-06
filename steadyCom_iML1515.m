%% Tutorial for SteadyCom
% This script accompanies the Advanced Technologies in Bioscience report for 
% instruction on the use of SteadyCom module on the COBRA Toolbox. The steps,
% originally found on the tutorial script for the tool has been adapted to
% the updated E. coli GEM, iML1515. Many thanks to Dr. Joshua Chan for the
% original tutorial. The original publication can be accessed at:
% https://doi.org/10.1371/journal.pcbi.1005539
%%
% Cheewin Kittikunapong 2020-02-24

%% EQUIPMENT SETUP
% If necessary, initialize the COBRA toolbox and select a solver by running:
clear;
initCobraToolbox(0) % false, as we don't want to update

% All SteadyCom functions involve only solving linear programming problems. 
% Any solvers supported by the COBRA toolbox will work. But SteadyCom contains 
% specialized codes for IBM ILOG Cplex which was tested to run significantly faster 
% for SteadyComFVA and SteadyComPOA for larger problems through calling the Cplex 
% object in Matlab directly. 
% 

changeCobraSolver('ibm_cplex', 'LP');

%% Model Construction
% Load the _E. coli_ iML1515 model in the COBRA toolbox.

modelEco = readCbModel(['models' filesep 'iML1515.xml']);

% set the uptake bounds to closely replicate the original study as possible
% This information can be found on the tutorial and S2 Text

% These boundaries are based on the original study
modelEco = changeRxnBounds(modelEco, 'EX_glc__D_e', -8, 'l');
modelEco = changeRxnBounds(modelEco, 'EX_o2_e', -18.5, 'l');
modelEco = changeRxnBounds(modelEco, 'EX_cbl1_e', -0.01, 'l');

% These bounds were added to iML1515
modelEco = changeRxnBounds(modelEco, 'EX_slnt_e', 0, 'l');
modelEco = changeRxnBounds(modelEco, 'EX_sel_e', 0, 'l');

% Nickel uptake is essential in iML1515, so we will leave the bounds as is
% modelEco = changeRxnBounds(modelEco, 'EX_ni2_e', -1000, 'l');

%% Check model structure for consistency

% make all empty cells in cell arrays to be empty string

fieldToBeCellStr = {'metFormulas'; 'genes'; 'rules'; 'metNames'; 'rxnNames'; 'subSystems'};

for j = 1:numel(fieldToBeCellStr)

modelEco.(fieldToBeCellStr{j})(cellfun(@isempty, modelEco.(fieldToBeCellStr{j}))) = {''};

end

%% Defining the gene-associated reactions for knockout

% Reactions to be knocked-out for amino acid auxotrophy:

argH = {'ARGSL'};  % essential for arginine biosynthesis
lysA = {'DAPDC'};  % essential for lysine biosynthesis
metA = {'HSST'};  % essential for methionine biosynthesis
ilvE = {'PPNDH'};  % essential for phenylalanine biosynthesis

% Reactions essential for exporting amino acids:

argO = {'ARGt3pp'};  % Evidence for an arginine exporter encoded by yggA (argO
lysO = {'LYSt3pp'};  % YbjE (LysO) mediates export of L-lysine
yjeH = {'METt3pp'};  % YjeH is a novel L-methionine and BCAA exporter in E. coli
yddG = {'PHEt2rpp'; 'PHEtipp'};  % YddG from E. coli promotes export of aromatic amino acids

%% Producing auxotrophic strains

% Now we will make four copies of the model with auxotrophy for different 
% amino  acids and incapacity for export of certain amino acids:

% NOTE:
% It was later found that the iML1515 has an additional reaction capable of
% transporting phenylalanine to the periplasm, which had to be addressed
% in order to ensure Ec1 was unable to export Phe as designed.

% Were this not addressed, Ec1 would be able to provide both crucial
% metabolites for Ec2 and Ec3 in the consortium, negating the essential
% role of Ec4. You can observe this in the resulting FVA where the relative
% abundance of Ec4 has a lower bound of zero up and only becoming
% "essential" or having a non-zero lower boundary near to the maximal
% growth rate of the commmunity.

% If you would like to replicate the results before addressing this issue,
% you can run the line below before proceeding:
% yddG = {'PHEt2rpp'}; 

% auxotrophic for Lys and Met, not exporting Phe
Ec1 = modelEco;
Ec1 = changeRxnBounds(Ec1, [lysA; metA; yddG;], 0, 'b');

% auxotrophic for Arg and Phe, not exporting Met
Ec2 = modelEco;
Ec2 = changeRxnBounds(Ec2, [argH; yjeH; ilvE], 0, 'b');

% Auxotrophic for Arg and Phe, not exporting Lys
Ec3 = modelEco;
Ec3 = changeRxnBounds(Ec3, [argH; lysO; ilvE], 0, 'b');

% Auxotrophic for Lys and Met, not exporting Arg
Ec4 = modelEco;
Ec4 = changeRxnBounds(Ec4, [argO; lysA; metA], 0, 'b');

%% Defining the community model boundaries
% Now none of the four organisms can grow alone and they must cross feed 
% each other to survive. 
% 
% We will now have to identify the extracellular metabolites, their 
% corresponding exchange reactions and uptake rates for the E. coli model, 
% which are used later to constrain the community model:

% identify the extracellular metabolites (met[e])
metEx = strcmp(getCompartment(modelEco.mets),'e');
% find the corresponding exchange reactions
rxnExAll = find(sum(modelEco.S ~= 0, 1) == 1);
[rxnEx, ~] = find(modelEco.S(metEx, rxnExAll)');  % need to be in the same order as metEx
rxnEx = rxnExAll(rxnEx);

%% Additional step for iML1515 update
% The following steps are to address a number of new extracellular
% metabolites that have been added since the first release of iAF1260 used
% in the original tutorial. If there are extracellular metabolites ([e]) that
% do not have a corresponding exchange reaction, the following generation of 
% the community model with createMultipleSpeciesModel will not work. 

% Below is a quick way to identify those unaccounted metabolites:
modelEco = buildRxnEquations(modelEco);
% Display list of all exchange reactions by equation:
% modelEco.rxnEquations(rxnEx)

% List of all extracellular metabolites with an exchange reaction
extMetsExc = strrep(modelEco.rxnEquations(rxnEx), ' -->', '');
extMetsExc = strrep(extMetsExc, ' <==>', '');

% List all extracellular metabolites and filter out unaccounted ones 
extMets = modelEco.mets(metEx);
extMets = setdiff(extMets,extMetsExc)

% Uncomment the following to see which reactions the unaccounted 
% extracellular are involved in:
% extMetsRxns = find(contains(modelEco.rxnEquations, extMets))
% modelEco.rxnEquations(extMetsRxns)

% Now add the exchange reactions but set bounds to zero to not confound the
% following results as our intention is to compare with the original study.
% We may adjust these later if needed.
modelEco = addExchangeRxn(modelEco, extMets, zeros(1,10), zeros(1,10));

%% Obtaining the exchange rates to constrain the community model

% Update the indices for the corresponding exchange reactions
rxnExAll = find(sum(modelEco.S ~= 0, 1) == 1);
[rxnEx, ~] = find(modelEco.S(metEx, rxnExAll)');  % need to be in the same order as metEx
rxnEx = rxnExAll(rxnEx);

% Obtain the exchange rate for each reaction
lbEx = modelEco.lb(rxnEx);

%% Creating the community model structure

% Create a community model with the four _E. coli_ tagged as 'Ec1', 'Ec2', 
% 'Ec3', 'Ec4' respectively by calling |createMultipleSpeciesModel|.

nameTagsModel = {'Ec1'; 'Ec2'; 'Ec3'; 'Ec4'};

EcCom = createMultipleSpeciesModel({Ec1; Ec2; Ec3; Ec4}, nameTagsModel);
EcCom.csense = char('E' * ones(1,numel(EcCom.mets)))';

% The model |EcCom| contains a community compartment denoted by |[u]| to 
% allow exchange between organisms. Each organism-specific reaction/metabolite 
% is prepended with the corresponding tag.
% 
% Retrieve the names and ids for organism/community exchange reactions/metabolites 
% which are necessary for computation:

[EcCom.infoCom, EcCom.indCom] = getMultiSpeciesModelId(EcCom, nameTagsModel);
disp(EcCom.infoCom);

%% Identify the biomass reaction
% |EcCom.infoCom |contains reaction/metabolite names (from |EcCom.rxns|/|EcCom.mets|) 
% for the community exchange reactions (|*.EXcom|), organism-community exchange 
% reactions (|*.EXsp|), community metabolites (|*.Mcom|), organism-specific extracellular 
% metabolite (|*.Msp|). If a host model is specified, there will also be non-empty 
% |*.EXhost| and |*.Mhost |for the host-specific exchange reactions and metabolites. 
% The fields |*.rxnSps|/|*.metSps| give information on which organism a reaction/metabolite 
% belongs to.
% 
% |indCom |has the same structure as |infoCom| but contains the indices rather 
% than names. |infoCom| and |indCom| are attached as fields of the model |EcCom| 
% because SteadyCom requires this information from the input model for computation. 
% Incorporate also the names and indices for the biomass reactions which are necessary 
% for computing growth:

rxnBiomass = strcat(nameTagsModel, 'BIOMASS_Ec_iML1515_core_75p37M');  % biomass reaction names
rxnBiomassId = findRxnIDs(EcCom, rxnBiomass);  % ids
EcCom.infoCom.spBm = rxnBiomass;  % .spBm for organism biomass reactions
EcCom.indCom.spBm = rxnBiomassId;

%% Setting the boundaries of the community model structure 
% Before we find the max growth rate, we will first set community and 
% organism-specific uptake rates to be the same as in the original model:

[yn, id] = ismember(strrep(modelEco.mets(metEx), '[e]', '[u]'), EcCom.infoCom.Mcom);  % map the metabolite name
assert(all(yn));  % make sure it is a 1-to-1 mapping
EcCom.lb(EcCom.indCom.EXcom(:,1)) = lbEx(id);  % assign community uptake bounds
EcCom.ub(EcCom.indCom.EXcom(:,1)) = 1e5;
EcCom.lb(EcCom.indCom.EXsp) = repmat(lbEx(id), 1, 4);  % assign organism-specific uptake bounds

%% Setting the boundaries of the individual memebrs 
% Set maximum allowed organism-specific uptake rates for the cross-feeding 
% amino acids:

% only allow to take up the amino acids that one is auxotrophic for
exRate = 1;  % maximum uptake rate for cross feeding AAs

% Ec1
EcCom = changeRxnBounds(EcCom, {'Ec1IEX_arg__L[u]tr'; 'Ec1IEX_phe__L[u]tr'}, 0, 'l');
EcCom = changeRxnBounds(EcCom, {'Ec1IEX_met__L[u]tr'; 'Ec1IEX_lys__L[u]tr'}, -exRate, 'l');

% Ec2
EcCom = changeRxnBounds(EcCom, {'Ec2IEX_arg__L[u]tr'; 'Ec2IEX_phe__L[u]tr'}, -exRate, 'l');
EcCom = changeRxnBounds(EcCom, {'Ec2IEX_met__L[u]tr'; 'Ec2IEX_lys__L[u]tr'}, 0, 'l');

% Ec3
EcCom = changeRxnBounds(EcCom, {'Ec3IEX_arg__L[u]tr'; 'Ec3IEX_phe__L[u]tr'}, -exRate, 'l');
EcCom = changeRxnBounds(EcCom, {'Ec3IEX_met__L[u]tr'; 'Ec3IEX_lys__L[u]tr'}, 0, 'l');

% Ec4
EcCom = changeRxnBounds(EcCom, {'Ec4IEX_arg__L[u]tr'; 'Ec4IEX_phe__L[u]tr'}, 0, 'l');
EcCom = changeRxnBounds(EcCom, {'Ec4IEX_met__L[u]tr'; 'Ec4IEX_lys__L[u]tr'}, -exRate, 'l');

% allow production of anything for each member
EcCom.ub(EcCom.indCom.EXsp(:)) = 1000;
 
% print the community uptake bounds to check
printUptakeBoundCom(EcCom, 1);

%% Finding the max growth rate using SteadyCom
% Values under 'Comm.' are the community uptake bounds (+ve for uptake) 
% and values under 'Ec1' are the Ec1-specific uptake bounds (-ve for uptake). 
% 
% Create an option structure for calling SteadyCom and call the function. 
% There are a range of options available, including setting algorithmic parameters, 
% fixing growth rates for members, adding additional linear constraints in a general 
% format, e.g., for molecular crowding effect. See |help SteadyCom |for more options.

options = struct();
options.GRguess = 0.5;  % initial guess for max. growth rate in the bisection
options.GRtol = 1e-6;  % tolerance for final growth rate
options.algorithm = 1;  % use the default algorithm (simple guessing for bounds, followed by matlab fzero)
% options.algorithm = 2;  % use the simple guessing algorithm
% options.algorithm = 3;  % use the bisection algorithm

[sol, result] = SteadyCom(EcCom,options);

% The algorithm is an iterative procedure to find the maximum biomass at 
% a given growth rate and to determine the maximum growth rate that is feasible 
% for the required total biomass (default 1 gdw). Here the algorithm used is the 
% simple guessing for find upper and lower bounds (Iter 1 to 4 in the output) 
% followed by Matlab |fzero| (starting from the line '|Func-count|') to locate 
% the root. The maximum growth rate calculated is 0.73599 /h, stored in |result.GRmax|._ 
% 
% The biomass for each organism (in gdw) is given by_ |_result.BM|:

for jSp = 1:4
    fprintf('X_%s:  %.6f\n', EcCom.infoCom.spAbbr{jSp}, result.BM(jSp));
end
disp(result);

%% 
% |result.vBM| contains the biomass production rates (in gdw / h), equal 
% to |result.BM * result.GRmax. |Since the total community biomass is defaulted 
% to be 1 gdw, the biomass for each organism coincides with its relative abundance. 
% Note that the community uptake bounds in this sense are normalized per gdw of 
% the community biomass. So the lower bound for the exchange reaction |EX_glc__D[u]| 
% being 8 can be interpreted as the maximum amount of glucose available to the 
% community being at a rate of 8 mmol per hour for 1 gdw of community biomass. 
% Similarly, all fluxes in |result.flux |($V^k_j$)| |has the unit mmol / h / [gdw 
% of comm. biomass]. It differs from the specific rate (traditionally denoted 
% by $v^k_j$) of an organism in the usual sense (in the unit of mmol / h / [gdw 
% of organism biomass]) by $V^k_j=X^kv^k_j$ where $X^k$ is the biomass of the 
% organism. |result.Ut|_ _and_ |_result.Ex |are the community uptake and export 
% rates respectively, corresponding to the exchange reactions in |EcCom.infoCom.EXcom|.| 
% |
% 
% |result.iter0 |is the info for solving the model at zero growth rate and 
% |result.iter |records the info during iteration of the algorithm:


iter = [0, result.iter0, NaN; result.iter];
for j = 0 : size(iter, 1)
    if j == 0
        fprintf('#iter\tgrowth rate (mu)\tmax. biomass (sum(X))\tmu * sum(X)\tmax. infeasibility\tguess method\n');
    else
        fprintf('%5d\t%16.6f\t%21.6f\t%11.6f\t%18.6e\t%d\n', iter(j,:))
    end
end

%% 
% |mu * sum(X)| in the forth column is equal to the biomass production rate. 
% 
% The fifth column contains the maximum infeasibility of the solutions in 
% each iteration.
% 
% Guess method in the last column represents the method used for guessing 
% the growth rate solved in the current iteration:
% 
% 0: the default simple guess by $\mu_{next} =\mu_{current} \text{ }\sum_{k=1}^K 
% X_k^{current}$ (_K_ is the total number of organisms)
% 
% 1: bisection method
% 
% 2: bisection or at least 1% away from the bounds if the simple guess is 
% too close to the bounds (<1%)
% 
% 3. 1% away from the current growth rate if the simple guess is too close 
% to the current growth rate
% 
% From the table, we can see that at the growth rate 0.742726 (iter 4), the 
% max. biomass is 0, while at growth rate 0.735372, max. biomass = 1.0008 > 1. 
% Therefore we have both an lower and upper bound for the max. growth rate. Then 
% fzero is initiated to solve for the max. growth rate that gives max. biomass 
% >= 1.
% 

%% Analyze flux variability with SteadyComFVA
% To analyze the variability of the organism abundance at various  growth 
% rates, we will use function |SteadyComFVA|.

% percentage of maximum total biomass of the community required. 
% 100 for sum(biomass) = 1 (1 is the default total biomass)
options.optBMpercent = 100;  
n = size(EcCom.S, 2);  % number of reactions in the model

% options.rxnNameList is the list of reactions subject to FVA. Can be 
% reaction names or indices. Use n + j for the biomass variable of the 
% j-th organism. Alternatively, use {'X_j'} for biomass variable of the 
% j-th organism or {'X_Ec1'} for Ec1 (the abbreviation in EcCom.infoCom.spAbbr)

options.rxnNameList = {'X_Ec1'; 'X_Ec2'; 'X_Ec3'; 'X_Ec4'};

% define the growth rates we would like to perform FVA for
options.optGRpercent = [89:0.2:99, 99.1:0.1:100];

% perform FVA at various fractions of the maximum growth rate
[fvaComMin,fvaComMax] = SteadyComFVA(EcCom, options);

% Similar to the output by |fluxVariability|, |fvaComMin| contains the minimum 
% fluxes corresponding to the reactions in |options.rxnNameList|. |fvaComMax| 
% contains the maximum fluxes. options.rxnNameList can be supplied as a (#rxns 
% + #organism)-by-K matrix to analyze the variability of the K linear combinations 
% of flux/biomass variables in the columns of the matrix. See |help SteadyComFVA| 
% for more details.

%% Analyze flux variability using standard FBA-FVA method
% We would also like to compare the results against the direct use of FBA 
% and FVA by calling |optimizeCbModel| and |fluxVariability|:

% less dense interval to save time because the results are always the same for < 99%
optGRpercentFBA = [89:2:99 99.1:0.1:100];  
nGr = numel(optGRpercentFBA);

[fvaFBAMin, fvaFBAMax] = deal(zeros(numel(options.rxnNameList), nGr));
% change the objective function to the sum of all biomass reactions
EcCom.c(:) = 0;
EcCom.c(EcCom.indCom.spBm) = 1;
EcCom.csense = char('E' * ones(1, numel(EcCom.mets)))';
s = optimizeCbModel(EcCom);  % run FBA
grFBA = s.f;
for jGr = 1:nGr
    fprintf('Growth rate %.4f :\n', grFBA * optGRpercentFBA(jGr)/100);
    [fvaFBAMin(:, jGr), fvaFBAMax(:, jGr)] = fluxVariability(EcCom, optGRpercentFBA(jGr), 'max', EcCom.infoCom.spBm, 2);
end

%% Comparing the results of each FVA method
% Plot the results to visualize the difference (see also Figure 2 in ref. 
% [1]):

grComV = result.GRmax * options.optGRpercent / 100;  % vector of growth rates tested
lgLabel = {'{\itEc1 }';'{\itEc2 }';'{\itEc3 }';'{\itEc4 }'};
col = [ 95 135 255; 255 0 0; 0 235 0;; 235 135 255 ]/255;  % color
f = figure;
% SteadyCom
subplot(2, 1, 1);
hold on
x = [grComV(:); flipud(grComV(:))];
for j = 1:4
    y = [fvaComMin(j, :), fliplr(fvaComMax(j, :))];
    p(j, 1) = plot(x(~isnan(y)), y(~isnan(y)), 'LineWidth', 2);
    p(j, 1).Color = col(j, :);
end
tl(1) = title('\underline{SteadyCom}', 'Interpreter', 'latex');
tl(1).Position = [0.7 1.01 0];
ax(1) = gca;
ax(1).XTick = grComV(1):0.02:grComV(end);
ax(1).YTick = 0:0.2:1;
xlim([grComV(1) grComV(end)])
ylim([0 1])

lg = legend(lgLabel);
lg.Box = 'off';
yl(1) = ylabel('Relative abundance');
xl(1) = xlabel('Community growth rate (h^{-1})');
% FBA
grFBAV = grFBA * optGRpercentFBA / 100;
x = [grFBAV(:); flipud(grFBAV(:))];
subplot(2, 1, 2);
hold on
% plot j=1:2 only because 3:4 overlap with 1:2
for j = 1:2
    y = [fvaFBAMin(j, :), fliplr(fvaFBAMax(j, :))] ./ x';
    % it is possible some values > 1 because the total biomass produced is
    % only bounded below when calling fluxVariability. Would be strictly
    % equal to 1 if sum(biomass) = optGRpercentFBA(jGr) * grFBA is constrained. Treat them as 1.
    y(y>1) = 1;
    p(j, 2)= plot(x(~isnan(y)), y(~isnan(y)), 'LineWidth', 2);
    p(j, 2).Color = col(j, :);
end
tl(2) = title('\underline{Joint FBA}', 'Interpreter', 'latex');
tl(2).Position = [0.55 1.01 0];
ax(2) = gca;
ax(2).XTick = grFBAV(1):0.02:grFBAV(end);
ax(2).YTick = 0:0.2:1;
xlim([grFBAV(1) grFBAV(end)])
ylim([0 1])
xl(2) = xlabel('Community growth rate (h^{-1})');
yl(2) = ylabel('Relative abundance');
ax(1).Position = [0.1 0.6 0.5 0.32];
ax(2).Position = [0.1 0.1 0.5 0.32];
lg.Position = [0.65 0.65 0.1 0.27];
%% If you want to just plot SteadyComFVA results

grComV = result.GRmax * options.optGRpercent / 100;  % vector of growth rates tested
lgLabel = {'{\itEc1 }';'{\itEc2 }';'{\itEc3 }';'{\itEc4 }'};
col = [ 95 135 255; 255 0 0; 0 235 0;; 235 135 255 ]/255;  % color
f = figure;
% SteadyCom
hold on
x = [grComV(:); flipud(grComV(:))];
for j = 1:4
    y = [fvaComMin(j, :), fliplr(fvaComMax(j, :))];
    p(j, 1) = plot(x(~isnan(y)), y(~isnan(y)), 'LineWidth', 2);
    p(j, 1).Color = col(j, :);
end
tl(1) = title('\underline{SteadyCom}', 'Interpreter', 'latex');
tl(1).Position = [0.7 2 0];
ax(1) = gca;
ax(1).XTick = grComV(1):0.02:grComV(end);
ax(1).YTick = 0:0.2:1;
xlim([grComV(1) grComV(end)])
ylim([0 1])

lg = legend(lgLabel);
lg.Box = 'off';
yl(1) = ylabel('Relative abundance');
xl(1) = xlabel('Community growth rate (h^{-1})');
 
% The direct use of FVA compared to FVA under the SteadyCom framework gives 
% very little information on the organism's abundance. The ranges for almost all 
% growth rates span from 0 to 1. In contrast, |SteadyComFVA| returns results with 
% the expected co-existence of all four mutants. When the growth rates get closer 
% to the maximum, the ranges shrink to unique values.
% 
% 
%% Analyze Pairwise Relationship Using SteadyComPOA

% Now we would like to see at a given growth rate, how the abundance of an organism 
% influences the abundance of another organism. We check this by iteratively fixing 
% the abundance of an organism at a level (independent variable) and optimizing 
% for the maximum and minimum allowable abundance of another organism (dependent 
% variable). This is what |SteadyComPOA| does.
% 
% Set up the option structure and call |SteadyComPOA|. |Nstep| is an important 
% parameter to designate how many intermediate steps are used or which values 
% between the min and max values of the independent variable are used for optimizing 
% the dependent variable. |savePOA| options must be supplied with a non-empty 
% string or a default name will be used for saving the POA results. By default, 
% the function analyzes all possible pairs in |options.rxnNameList|. To analyze 
% only particular pairs, use |options.pairList|. See |help SteadyComPOA |for more 
% details.

options.savePOA = ['POA/iML1515/EcCom'];  % directory and fila name for saving POA results
options.optGRpercent = [99.9 99 90 75 50 0];  % analyze at these percentages of max. growth rate
% Nstep is the number of intermediate steps that the independent variable will take different values
% or directly the vector of values, e.g. Nsetp = [0, 0.5, 1] implies fixing the independent variable at the minimum,
% 50% from the min to the max and the maximum value respectively to find the attainable range of the dependent variable.
% Here use small step sizes when getting close to either ends of the flux range
a = 0.001*(1000.^((0:14)/14));
options.Nstep = sort([a (1-a)]);

[POAtable, fluxRange, Stat, GRvector] = SteadyComPOA(EcCom, options);
%% Plotting the results of the pareto optimality analysis

% POAtable is a _n_-by-_n_ cell if there are _n_ targets in |options.rxnNameList|. 
% |POAtable{i, i}| is a _Nstep_-by-1-by-_Ngr_ matrix where _Nstep _is the number 
% of intermediate steps detemined by |options.Nstep| and _Ngr _is the number of 
% growth rates analyzed. |POAtable{i, i}(:, :, k)| is the values at which the 
% _i_-th target is fixed for the community growing at the growth rate |GRvector(k)|. 
% POAtable{i, j} is a _Nstep_-by-2-by-_Ngr_ matrix where |POAtable{i, j}(:, 1, 
% k)| and |POAtable{i, j}(:, 2, k)| are respectively the min. and max. values 
% of the _j_-th target when fixing the _i_-th target at the corresponding values 
% in |POAtable{i, i}(:, :, k)|. |fluxRange |contains the min. and max. values 
% for each target (found by calling |SteadyComFVA|). |Stat |is a _n_-by-_n-by-Ngr_ 
% structure array, each containing two fields: |*.cor|, the correlatiion coefficient 
% between the max/min values of the dependent variable and the independent variable, 
% and |*.r2|, the R-squred of linear regression. They are also outputed in the 
% command window during computation. All the computed results are also saved in 
% the folder 'POA' starting with the name 'EcCom', followed by 'GRxxxx' denoting 
% the growth rate at which the analysis is performed.
% 
% Plot the results (see also Figure 3 in ref. [1]):

nSp = 4;
spLab = {'{\it Ec1 }';'{\it Ec2 }';'{\it Ec3 }';'{\it Ec4 }'};
mark = {'A', 'B', 'D', 'C', 'E', 'F'};
nPlot = 0;
for j = 1:nSp
    for k = 1:nSp
        if k > j
            nPlot = nPlot + 1;
            ax(j, k) = subplot(nSp-1, nSp-1, (k - 2) * (nSp - 1) + j);
            hold on
            for p = 1:size(POAtable{1, 1}, 3)
                x = [POAtable{j, j}(:, :, p);POAtable{j, j}(end:-1:1, :, p);...
                    POAtable{j, j}(1, 1, p)];
                y = [POAtable{j, k}(:, 1, p);POAtable{j, k}(end:-1:1, 2, p);...
                        POAtable{j, k}(1, 1, p)];
                plot(x(~isnan(y)), y(~isnan(y)), 'LineWidth', 2)
            end
            xlim([0.001 1])
            ylim([0.001 1])
            ax(j, k).XScale = 'log';
            ax(j, k).YScale = 'log';
            ax(j, k).XTick = [0.001 0.01 0.1 1];
            ax(j, k).YTick = [0.001 0.01 0.1 1];
            ax(j, k).YAxis.MinorTickValues=[];
            ax(j, k).XAxis.MinorTickValues=[];
            ax(j, k).TickLength = [0.03 0.01];
            xlabel(spLab{j});
            ylabel(spLab{k});
            tx(j, k) = text(10^(-5), 10^(0.1), mark{nPlot}, 'FontSize', 12, 'FontWeight', 'bold');
        end
    end
end
lg = legend(strcat(strtrim(cellstr(num2str(options.optGRpercent(:)))), '%'));
lg.Position = [0.7246 0.6380 0.1700 0.2015];
lg.Box='off';
subplot(3, 3, 3, 'visible', 'off');
t = text(0.2, 0.8, {'% maximum';'growth rate'});
for j = 1:nSp
    for k = 1:nSp
        if k>j
            ax(j, k).Position = [0.15 + (j - 1) * 0.3, 0.8 - (k - 2) * 0.3, 0.16, 0.17];
            ax(j, k).Color = 'none';
        end
    end
end

% There are two patterns observed. The two pairs showing negative correlations, 
% namely Ec1 vs Ec4 (panel D) and Ec2 vs Ec3 (panel C) are indeed competing for 
% the same amino acids with each other (Ec1 and Ec4 competing for Lys and Met; 
% Ec2 and Ec4 competing for Arg and Phe). Each of the other pairs showing positive 
% correlations are indeed the cross feeding pairs, e.g., Ec1 and Ec2 (panel A) 
% cross feeding on Arg and Lys. See ref. [1] for more detailed discussion.
% 

