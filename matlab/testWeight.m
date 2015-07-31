

clc
clear all
close all

addpath('.\data');

load inputn_test.mat
load inputn_train.mat
load output_test.mat
load output_train.mat
load output_test_class.mat

W10 = load('W10result.txt');
W21 = load('W21result.txt');
W10 = reshape(W10, [401, 32])';
W21 = reshape(W21, [32, 10])';

% �ź�
classNum = 10;
trainNum = 4160;
testNum = 840;

% break
% ���ز���� 
hOut = 1 ./ (1 + exp(- W10 * inputn_test));

% ��������
fore = W21 * hOut;

%% �������
% ������������ҳ�������������
[output_fore, ~] = find(bsxfun(@eq, fore, max(fore)) ~= 0);

%BP����Ԥ�����
error = output_fore' - output_test_class;

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

%% ��ͼ

% �������ͼ
figure
stem(error, '.')
title('BP����������', 'fontsize',12)
xlabel('�ź�', 'fontsize',12)
ylabel('�������', 'fontsize',12)


