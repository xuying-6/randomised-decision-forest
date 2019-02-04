function [data_train, data_query] = getData(MODE, nClusters, showImg)
% Generate training and testing data

% Data Options:
%   1. Toy_Gaussian
%   2. Toy_Spiral
%   3. Toy_Circle
%   4. Caltech 101

% Multi-resolution, these values determine the scale of each layer
phowSize = [4 8 10]; 
% The lower the denser. Select from {2,4,8,16}
phowStep = 8; 

switch MODE
    case 'Toy_Gaussian'
        % Gaussian distributed 2D points
        N= 150;
        D= 2;
        
        cov1 = randi(4);
        cov2 = randi(4);
        cov3 = randi(4);
        
        X1 = mgd(N, D, [randi(4)-1 randi(4)-1], [cov1 0;0 cov1]);
        X2 = mgd(N, D, [randi(4)-1 randi(4)-1], [cov2 0;0 cov2]);
        X3 = mgd(N, D, [randi(4)-1 randi(4)-1], [cov3 0;0 cov3]);
        
        X= real([X1; X2; X3]);
        X= bsxfun(@rdivide, bsxfun(@minus, X, mean(X)), var(X));
        Y= [ones(N, 1); ones(N, 1)*2; ones(N, 1)*3];
        
        data_train = [X Y];
        
    case 'Toy_Spiral' % Spiral (from Karpathy's matlab toolbox)
        
        N= 50;
        t = linspace(0.5, 2*pi, N);
        x = t.*cos(t);
        y = t.*sin(t);
        
        t = linspace(0.5, 2*pi, N);
        x2 = t.*cos(t+2);
        y2 = t.*sin(t+2);
        
        t = linspace(0.5, 2*pi, N);
        x3 = t.*cos(t+4);
        y3 = t.*sin(t+4);
        
        X= [[x' y']; [x2' y2']; [x3' y3']];
        X= bsxfun(@rdivide, bsxfun(@minus, X, mean(X)), var(X));
        Y= [ones(N, 1); ones(N, 1)*2; ones(N, 1)*3];
        
        data_train = [X Y];
        
    case 'Toy_Circle' % Circle
        
        N= 50;
        t = linspace(0, 2*pi, N);
        r = 0.4;
        x = r*cos(t);
        y = r*sin(t);
        
        r = 0.8;
        t = linspace(0, 2*pi, N);
        x2 = r*cos(t);
        y2 = r*sin(t);
        
        r = 1.2;
        t = linspace(0, 2*pi, N);
        x3 = r*cos(t);
        y3 = r*sin(t);
        
        X= [[x' y']; [x2' y2']; [x3' y3']];
        Y= [ones(N, 1); ones(N, 1)*2; ones(N, 1)*3];
        
        data_train = [X Y];
        
    case 'Caltech' % Caltech dataset
        %% Initialisation
        % the number of images each class for training and testing without replacement
        imgSel = [15 15];
        % size of descriptors for clustering
        nWords = 1e4;
        % number of samples for train and test per class
        nSamplesTrain = imgSel(1);
        nSamplesTest = imgSel(2);
        % image directory
        folderName = './Caltech_101/101_ObjectCategories';
        classList = dir(folderName);
        % choose classes
        classList = {classList(3:end).name};
        %% Training data: feature detection and descriptors extraction
        type = 'train';
        disp('Loading training images...')
        [descTrain, imgIdxTrain] = feature_detection(classList, folderName, nSamplesTrain, phowSize, phowStep, type);
        %% Build visual vocabulary (codebook) for 'Bag-of-Words' method
        disp('Building visual codebook...')
        % randomly select SIFT descriptors for clustering
        descSelect = single(vl_colsubset(cat(2,descTrain{:}), nWords)); 
        %% K-means clustering
        % compute the centroids position
        [centroid, ~] = vl_kmeans(descSelect, nClusters);
        centroid = centroid';
        %% Training data: assign patch descriptors to the visual codebook (vector quantisation)
        disp('Encoding training images...')
        [data_train] = vector_quantisation_knn(classList, folderName, nSamplesTrain, nClusters, imgIdxTrain, centroid, descTrain, type, showImg);
end
%% Testing data: Feature detection and descriptors extraction
switch MODE
    case 'Caltech'
        % initialisation
        descTest = cell(nClasses, nSamplesTest);
        imgIdxTest = zeros(nClasses, nSamplesTest);
        
        disp('Loading testing images...')
        for iClass = 1: nClasses
            subFolderName = fullfile(folderName, classList{iClass});
            % class directory
            imgList = dir(fullfile(subFolderName,'*.jpg'));
            % randomly choose images from the class
            imgIdx{iClass} = randperm(length(imgList));
            % obtain image index (first nSamplesTrain for training, next nSamplesTest for testing)
            imgIdxTest(iClass, :) = imgIdx{iClass}(nSamplesTrain + 1: nSamplesTrain + nSamplesTest);
            for iSample = 1: nSamplesTest
                % read image
                imgTest = imread(fullfile(subFolderName,imgList(imgIdxTest(iClass, iSample)).name));
                % if the image is not in gray scale
                if size(imgTest,3) == 3
                    % PHOW work on gray scale image
                    imgTest = rgb2gray(imgTest); 
                end
                % obtain testing descriptors
                [~, descTest{iClass, iSample}] = vl_phow(single(imgTest),'Sizes',phowSize,'Step',phowStep); %  extracts PHOW features (multi-scaled Dense SIFT)
            end
        end
        %% Testing data: assign patch descriptors to the visual codebook (vector quantisation)
        disp('Analysing testing images...')
        % frequency of descriptors for testing dataset (for histogram)
        freqTest = zeros(nClasses * nSamplesTest, nClusters);
        % Assign patch descriptors to the visual codebook (vector quantisation)
        for iClass = 1: nClasses
            subFolderName = fullfile(folderName, classList{iClass});
            % get image directory
            imgList = dir(fullfile(subFolderName, '*.jpg'));
            if showImg
                figure;
                suptitle('Testing image representations: 256-D histograms');
            end
            for iSample = 1: nSamplesTest
                % update current descriptor
                descCurr = single(descTest{iClass, iSample});
                % categorise by KNN based on obtained centroids
                indexTest = knnsearch(centroid, descCurr');
                % compute frequency of clusters for histogram
                freqTest((iClass - 1) * nSamplesTest + iSample, :) = histcounts(indexTest, nClusters) / length(indexTest);
                % display testing images and corresponding histograms
                if showImg
                    I = imread(fullfile(subFolderName, imgList(imgIdxTest(iClass, iSample)).name));
                    subplot(ceil(nSamplesTest / 3), 6 ,2 * iSample - 1);
                    imshow(I);
                    subplot(ceil(nSamplesTest / 3), 6 ,2 * iSample);
                    histogram(indexTest, nClusters);
                    xlim([0 nClusters + 1]);
                    drawnow;
                end
            end
        end
        % label the testing data (with zeros)
        data_query = [freqTest, zeros(nClasses * nSamplesTest, 1)];
        % clear unused varibles to save memory
        clearvars descTest descCurr
    otherwise
        % Dense point for 2D toy data
        xrange = [-1.5 1.5];
        yrange = [-1.5 1.5];
        inc = 0.02;
        [x, y] = meshgrid(xrange(1):inc:xrange(2), yrange(1):inc:yrange(2));
        data_query = [x(:) y(:) zeros(length(x)^2,1)];
end
end

