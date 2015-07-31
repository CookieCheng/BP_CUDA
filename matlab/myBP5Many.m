clc
clear all
close all

addpath('../')
%% ѵ������Ԥ��������ȡ����һ��

% �ź�
load HW1503data X y
[row, col] = size(X);
classNum = 10;
trainNum = 4096;
testNum = 908;

% �����������,��1άΪ����ʶ����24άΪ���������ź�
input = ones(row, col+1);
input(:,2:end) = X;

outputClass = y;
output = zeros(1, classNum * row);
output(classNum .* (0:row-1)' + outputClass) = 1;
output = (reshape(output, [classNum, row]))';

% �����ȡ4000������Ϊѵ��������1000������ΪԤ������
nPerm = randperm(row); % ��1��5000���������
input_train = input(nPerm(1 : trainNum), :)';
output_train = output(nPerm(1 : trainNum), :)';
input_test = input(nPerm(trainNum+1 : row), :)';
output_test = output(nPerm(trainNum+1 : row), :)';

% �������ݹ�һ��
[inputn_train, inputps] = mapminmax(input_train);

save inputn_train inputn_train
save output_train output_train

%% ����ṹ��ʼ��
inNum = col + 1;
midNum = 32;
outNum = classNum;
 
% Ȩֵ��ʼ��
epsilonInit = sqrt(6) / sqrt(inNum + outNum);
W10 = (rand(midNum, inNum) - 0.5) * epsilonInit;
W21 = (rand(outNum, midNum) - 0.5) * epsilonInit;

save W10 W10
save W21 W21

tic

% ѧϰ��
eta = 0.2;
etaMax = 0.02;
etaMin = 0.01;
%% ����ѵ��
iterMax = 50;
eIter = zeros(iterMax, 1);
step = 32;
for iter = 1:iterMax
    for n = 1:step:trainNum
        % ȡһ������
        oneIn = inputn_train(:, n:n+step-1);
        oneOut = output_train(:, n:n+step-1);
        oneIn = oneIn';
        oneOut = oneOut';
        
        % ���ز���� 
        hOut = 1 ./ (1 + exp(- oneIn * W10'));

        % ��������
        yOut = hOut * W21';
        
        % �������
        eOut = oneOut - yOut;     
        eIter(iter) = eIter(iter) + sum(sum(abs(eOut)));
        
        % �������������� delta2
        delta2 = eOut;
        
        % �������ز������ delta1
        FI = hOut .* (1 - hOut);
        delta1 = (FI .* (eOut * W21));

        % ����Ȩ��
        W21 = W21 + eta / step * delta2' * hOut;
        W10 = W10 + eta / step * delta1' * oneIn;
    end
end
 
%% ����
inputn_test = mapminmax('apply', input_test, inputps);

% ���ز���� 
hOut = 1 ./ (1 + exp(- W10 * inputn_test));

% ��������
fore = W21 * hOut;

%% �������
% ������������ҳ�������������
[output_fore, ~] = find(bsxfun(@eq, fore, max(fore)) ~= 0);
save inputn_test inputn_test
save output_test output_test

%BP����Ԥ�����
output_test_class = outputClass(nPerm(trainNum+1 : row))';
error = output_fore' - output_test_class;


save output_test_class output_test_class
%% ������ȷ��
% �ҳ�ÿ���жϴ���Ĳ���������
kError = zeros(1, classNum);  
outPutError = bsxfun(@and, output_test, error);
[indexError, ~] = find(outPutError ~= 0);

for class = 1:classNum
    kError(class) = sum(indexError == class);
end

% �ҳ�ÿ����ܲ���������
kReal = zeros(1, classNum);
[indexRight, ~] = find(output_test ~= 0);
for class = 1:classNum
    kReal(class) = sum(indexRight == class);
end

% ��ȷ��
rightridio = (kReal-kError) ./ kReal
meanRightRidio = mean(rightridio)
%}
toc
%% ��ͼ

% �������ͼ
figure
stem(error, '.')
title('BP����������', 'fontsize',12)
xlabel('�ź�', 'fontsize',12)
ylabel('�������', 'fontsize',12)

% ��Ŀ�꺯��
figure
plot(eIter)
title('ÿ�ε����ܵ����', 'fontsize', 12)
xlabel('��������', 'fontsize', 12)
ylabel('������������', 'fontsize', 12)
