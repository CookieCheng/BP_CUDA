function saveMatToText(data, saveFileName)
% �����ݱ���Ϊ�ı��ļ�

data = single(data);

fid=fopen(saveFileName, 'wt');

% һ��һ��д�룬�ո�����������
for i = 1:size(data, 1)
    fprintf(fid, '%f ', data(i, 1:end-1));
    fprintf(fid, '%f\n', data(i, end));
end

fclose(fid);