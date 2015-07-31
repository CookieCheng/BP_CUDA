#ifndef PARAMETER_H
#define PARAMETER_H

#include <iostream>

#define classNum 10 // �����
#define trainNum 4160 // ѵ��������
#define testNum 840 // ����������

#define inLayout 401 // �������
#define hideLayout 32 // �м����
#define outLayout classNum // �������

#define initWeightMax sqrt(6.0f / (inLayout + hideLayout)) // ��ʼȨ�����ֵ

#define eta (0.2f) // ѧϰ��

#define iterMax 50 // ��������ʱ

#define batchNum 32 // ������������

#define BLOCKSIZE 16 // �߳̿�ά��
#define BLOCKSIZE_32 32 // �߳̿�ά��

#endif //PARAMETER_H