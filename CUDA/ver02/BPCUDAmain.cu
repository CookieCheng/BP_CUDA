#include "BPCUDAmain.h"
#include "Parameter.h"
#include "ReadSaveImage.h"

#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <curand_kernel.h>

/**
* ���ܣ���ʼ�� BP �����Ȩ��
* �����weight_D Ȩ��
* ���룺row Ȩ�ص�����
* ���룺col Ȩ�ص�����
* ���룺maxNum Ȩ�ص����ֵ
*/
__global__ void Bp_Init_Weight(float *weight_D, int row, int col, float maxNum, int seed)
{
	int x_id = blockDim.x * blockIdx.x + threadIdx.x; // ������
	int y_id = blockDim.y * blockIdx.y + threadIdx.y; // ������
	int index = y_id * col + x_id;

	curandState s;
	curand_init(index + seed, 0, 0, &s);

	if (x_id < col && y_id < row) weight_D[index] = (curand_uniform(&s) - 0.5f) * maxNum;
}


/**
* ���ܣ����� C = A * B'
* ���룺dev_A �����ͷָ��
* ���룺dev_B �����ͷָ��
* �����dev_C ��������ͷָ��
* ���룺heightA A ���������
* ���룺widthA A ���������
* ���룺heightB B ���������
*/
__global__ void MatMulCUDATB(float *dev_A, float *dev_B, float *dev_C, const int heightA, const int widthA, const int heightB)
{
	int x_id = blockDim.x * blockIdx.x + threadIdx.x; // ������
	int y_id = blockDim.y * blockIdx.y + threadIdx.y; // ������

	// ÿһ���̼߳���Csub�е�һ��Ԫ�أ����������Cvalue
	float Cvalue = 0;

	// A�����ӿ� * B�����ӿ� = ��ӦC���ӿ�Csub
	for (int m = 0; m < widthA; m += BLOCKSIZE)
	{
		int colA = m + threadIdx.x; // ��ǰ�߳��� A �е�������
		int rowB = m + threadIdx.y; // ��ǰ�߳��� B �е�������

		// ���乲���ڴ�ռ䣬�������Asub��Bsub
		__shared__ float As[BLOCKSIZE][BLOCKSIZE];
		__shared__ float Bs[BLOCKSIZE][BLOCKSIZE];

		// ��Asub��Bsub�����������ڴ���
		if ((colA < widthA) && (y_id < heightA))
			As[threadIdx.y][threadIdx.x] = dev_A[y_id * widthA + colA]; // A(y_id, colA)
		else
			As[threadIdx.y][threadIdx.x] = 0.0f;

		if ((x_id < heightB) && (rowB <widthA))
			Bs[threadIdx.y][threadIdx.x] = dev_B[x_id * widthA + rowB]; // B(rowB, x_id)
		else
			Bs[threadIdx.y][threadIdx.x] = 0.0f;

		__syncthreads();

		// A�ӿ����*B�ӿ����
		// �ӿ��ڵ�ѭ��
		for (int idx = 0; idx < BLOCKSIZE; ++idx)
		{
			Cvalue += As[threadIdx.y][idx] * Bs[idx][threadIdx.x];
		}

		// ͬ��,ȷ����ǰA�ӿ���B�ӿ�ļ������
		__syncthreads();
	}


	if (x_id < heightB && y_id < heightA)
	{
		dev_C[y_id * heightB + x_id] = Cvalue;
	}
}

/**
* ���ܣ����������������ڻ�
* ���룺As ���� A
* ���룺Bs ���� B
* ���룺length ��������
*/
__device__ inline static float BP_Dot(float *As, float *Bs, int length)
{
	float dot = 0.0f;

	for (int i = 0; i < length; i++)
	{
		dot += As[i] * Bs[i];
	}

	return(dot);
}

__global__ void BP_Calculate_HideIn(float *dev_A, float *dev_B, float *dev_C, const int heightA, const int widthA, const int widthB)
{
	int x_id = blockDim.x * blockIdx.x + threadIdx.x; // ������
	int y_id = blockDim.y * blockIdx.y + threadIdx.y; // ������

	__shared__ float As[BLOCKSIZE_32][BLOCKSIZE_32];
	__shared__ float Bs[BLOCKSIZE_32][BLOCKSIZE_32];
	As[threadIdx.y][threadIdx.x] = 0.0f;
	Bs[threadIdx.y][threadIdx.x] = 0.0f;

	if (y_id < heightA && x_id < widthA)
	{
		As[threadIdx.y][threadIdx.x] = dev_A[threadIdx.y * widthA + x_id];
		Bs[threadIdx.y][threadIdx.x] = dev_B[threadIdx.y * widthA + x_id];
	}
	__syncthreads();

	float dot = BP_Dot(As[threadIdx.y], Bs[threadIdx.x], BLOCKSIZE_32);
	atomicAdd(&dev_C[threadIdx.y * widthB + threadIdx.x], dot);
}

/**
* ���ܣ��������ز�����
* ���룺hideOut_D ���ز�����
* �����hideOut_D ���ز����
* ���룺row Ȩ�ص�����
* ���룺col Ȩ�ص�����
*/
__global__ void BP_Calculate_HideOut(float *hideOut_D, int row, int col)
{
	int x_id = blockDim.x * blockIdx.x + threadIdx.x; // ������
	int y_id = blockDim.y * blockIdx.y + threadIdx.y; // ������
	int index = y_id * col + x_id;

	if (x_id < col && y_id < row)
	{
		hideOut_D[index] = 1.0f / (1.0f + exp(-hideOut_D[index]));
	}
}

/**
* ���ܣ����� delta2_D = x_Out - A * B'
* ���룺dev_A �����ͷָ��
* ���룺dev_B �����ͷָ��
* �����delta2_D ���ز���������Ȩ������
* ���룺xOut_D �����ͷָ��
* ���룺heightA A ���������
* ���룺widthA A ���������
* ���룺heightB B ���������
*/
__global__ void BP_Calculate_Delta2(float *dev_A, float *dev_B, float *delta2_D, float *xOut_D, const int heightA, const int widthA, const int heightB)
{
	int x_id = blockDim.x * blockIdx.x + threadIdx.x; // ������
	int y_id = blockDim.y * blockIdx.y + threadIdx.y; // ������

	// ÿһ���̼߳���Csub�е�һ��Ԫ�أ����������Cvalue
	float Cvalue = 0;

	// A�����ӿ� * B�����ӿ� = ��ӦC���ӿ�Csub
	for (int m = 0; m < widthA; m += BLOCKSIZE)
	{
		int colA = m + threadIdx.x; // ��ǰ�߳��� A �е�������
		int rowB = m + threadIdx.y; // ��ǰ�߳��� B �е�������

		// ���乲���ڴ�ռ䣬�������Asub��Bsub
		__shared__ float As[BLOCKSIZE][BLOCKSIZE];
		__shared__ float Bs[BLOCKSIZE][BLOCKSIZE];

		// ��Asub��Bsub�����������ڴ���
		if ((colA < widthA) && (y_id < heightA))
			As[threadIdx.y][threadIdx.x] = dev_A[y_id * widthA + colA]; // A(y_id, colA)
		else
			As[threadIdx.y][threadIdx.x] = 0.0f;

		if ((x_id < heightB) && (rowB <widthA))
			Bs[threadIdx.y][threadIdx.x] = dev_B[x_id * widthA + rowB]; // B(rowB, x_id)
		else
			Bs[threadIdx.y][threadIdx.x] = 0.0f;

		__syncthreads();

		// A�ӿ����*B�ӿ����
		// �ӿ��ڵ�ѭ��
		for (int idx = 0; idx < BLOCKSIZE; ++idx)
		{
			Cvalue += As[threadIdx.y][idx] * Bs[idx][threadIdx.x];
		}

		// ͬ��,ȷ����ǰA�ӿ���B�ӿ�ļ������
		__syncthreads();
	}


	if (x_id < heightB && y_id < heightA)
	{
		int index = y_id * heightB + x_id;
		delta2_D[index] = xOut_D[index] - Cvalue;
	}
}



/**
* ���ܣ����� C = (hOut .* (1 - hOut)) .* (A * B)
* ���룺dev_A �����ͷָ��
* ���룺dev_B �����ͷָ��
* �����dev_C ��������ͷָ��
* ���룺hideOut_D ����ͷָ��
* ���룺heightA A ���������
* ���룺widthA A ���������
* ���룺widthB B ���������
*/
__global__ void BP_Calculate_Delta1(float *dev_A, float *dev_B, float *dev_C, float *hideOut_D, const int heightA, const int widthA, const int widthB)
{
	int x_id = blockDim.x * blockIdx.x + threadIdx.x; // ������
	int y_id = blockDim.y * blockIdx.y + threadIdx.y; // ������

	// ÿһ���̼߳���Csub�е�һ��Ԫ�أ����������Cvalue
	float Cvalue = 0;

	// A�����ӿ� * B�����ӿ� = ��ӦC���ӿ�Csub
	for (int m = 0; m < widthA; m += BLOCKSIZE)
	{
		int colA = m + threadIdx.x; // ��ǰ�߳��� A �е�������
		int rowB = m + threadIdx.y; // ��ǰ�߳��� B �е�������

		// ���乲���ڴ�ռ䣬�������Asub��Bsub
		__shared__ float As[BLOCKSIZE][BLOCKSIZE];
		__shared__ float Bs[BLOCKSIZE][BLOCKSIZE];

		// ��Asub��Bsub�����������ڴ���
		if ((colA < widthA) && (y_id < heightA))
			As[threadIdx.y][threadIdx.x] = dev_A[y_id * widthA + colA]; // A(y_id, colA)
		else
			As[threadIdx.y][threadIdx.x] = 0.0f;

		if ((x_id < widthB) && (rowB <widthA))
			Bs[threadIdx.y][threadIdx.x] = dev_B[rowB * widthB + x_id]; // B(rowB, x_id)
		else
			Bs[threadIdx.y][threadIdx.x] = 0.0f;

		__syncthreads();

		// A�ӿ����*B�ӿ����
		// �ӿ��ڵ�ѭ��
		for (int idx = 0; idx < BLOCKSIZE; ++idx)
		{
			Cvalue += As[threadIdx.y][idx] * Bs[idx][threadIdx.x];
		}

		// ͬ��,ȷ����ǰA�ӿ���B�ӿ�ļ������
		__syncthreads();
	}

	if (x_id < widthB && y_id < heightA)
	{
		int index = y_id * widthB + x_id;
		float data = hideOut_D[index];
		dev_C[index] = data * (1.0f - data) * Cvalue;
	}
}

/**
* ���ܣ�����Ȩ�� C = C + eta/batchNum .* (A' * B)
* ���룺dev_A �����ͷָ��
* ���룺dev_B �����ͷָ��
* �����dev_C ��������ͷָ��
* ���룺heightA A ���������
* ���룺widthA A ���������
* ���룺heightB B ���������
*/
__global__ void BP_Update_Weight(float *dev_A, float *dev_B, float *dev_C, const int heightA, const int widthA, const int widthB)
{
	int x_id = blockDim.x * blockIdx.x + threadIdx.x; // ������
	int y_id = blockDim.y * blockIdx.y + threadIdx.y; // ������

	// ÿһ���̼߳���Csub�е�һ��Ԫ�أ����������Cvalue
	float Cvalue = 0;

	// A�����ӿ� * B�����ӿ� = ��ӦC���ӿ�Csub
	for (int m = 0; m < heightA; m += BLOCKSIZE)
	{
		int colA = m + threadIdx.x; // ��ǰ�߳��� A �е�������
		int rowB = m + threadIdx.y; // ��ǰ�߳��� B �е�������

		// ���乲���ڴ�ռ䣬�������Asub��Bsub
		__shared__ float As[BLOCKSIZE][BLOCKSIZE];
		__shared__ float Bs[BLOCKSIZE][BLOCKSIZE];

		// ��Asub��Bsub�����������ڴ���
		if ((colA < heightA) && (y_id < widthA))
			As[threadIdx.y][threadIdx.x] = dev_A[colA * widthA + y_id]; // A(y_id, colA)
		else
			As[threadIdx.y][threadIdx.x] = 0.0f;

		if ((x_id < widthB) && (rowB < heightA))
			Bs[threadIdx.y][threadIdx.x] = dev_B[rowB * widthB + x_id]; // B(rowB, x_id)
		else
			Bs[threadIdx.y][threadIdx.x] = 0.0f;

		__syncthreads();

		// A�ӿ����*B�ӿ����
		// �ӿ��ڵ�ѭ��
		for (int idx = 0; idx < BLOCKSIZE; ++idx)
		{
			Cvalue += As[threadIdx.y][idx] * Bs[idx][threadIdx.x];
		}

		// ͬ��,ȷ����ǰA�ӿ���B�ӿ�ļ������
		__syncthreads();
	}

	if (x_id < widthB && y_id < widthA)
	{
		dev_C[y_id * widthB + x_id] += eta  * Cvalue / float(batchNum);
	}
}

/**
* ���ܣ�������������ݸ������ǩ
* �����yOutTestClass_D ÿ���������������
* ���룺yOutTest_D ÿ��������Ӧ�����
* ���룺row ������
* ���룺col ���������˴�Ϊ 10
*/
__global__ void BP_Calculate_Class(int *yOutTestClass_D, float *yOutTest_D, int row, int col)
{
	int y_id = blockDim.y * blockIdx.y + threadIdx.y; // ������

	__shared__ float sData[BLOCKSIZE][BLOCKSIZE]; // ÿ�����������
	__shared__ int sIndx[BLOCKSIZE][BLOCKSIZE]; // �����Ӧ������

	if (threadIdx.x < BLOCKSIZE / 2)
	{
		sData[threadIdx.y][threadIdx.x] = 0;
		sIndx[threadIdx.y][threadIdx.x] = threadIdx.x;
		sData[threadIdx.y][threadIdx.x + BLOCKSIZE / 2] = -2e30;
		sIndx[threadIdx.y][threadIdx.x + BLOCKSIZE / 2] = threadIdx.x + BLOCKSIZE / 2;
	}

	__syncthreads();

	if (y_id < row && threadIdx.x < col)
	{
		float *objIndex = &yOutTest_D[y_id * col];
		sData[threadIdx.y][threadIdx.x] = objIndex[threadIdx.x];

		__syncthreads();

		/* BLOCKSIZE �����ڲ���Լ����ֻʣ 2 �� */
		for (int step = BLOCKSIZE / 2; step > 1; step = step >> 1)
		{
			int idxStep = threadIdx.x + step;
			if (threadIdx.x < step && sData[threadIdx.y][threadIdx.x] < sData[threadIdx.y][idxStep])
			{
				sData[threadIdx.y][threadIdx.x] = sData[threadIdx.y][idxStep];
				sIndx[threadIdx.y][threadIdx.x] = sIndx[threadIdx.y][idxStep];
			}
		}

		if (threadIdx.x == 0)
		{
			yOutTestClass_D[y_id] = sData[threadIdx.y][0] > sData[threadIdx.y][1] ? sIndx[threadIdx.y][0] : sIndx[threadIdx.y][1];
		}
	}
}

/**
* ���ܣ�������������ݸ������ǩ
* �����yOutTestClass_D ÿ���������������
* ���룺yOutTest_D ÿ��������Ӧ�����
* ���룺row ������
* ���룺col ���������˴�Ϊ 10
*/
__global__ void BP_Calculate_RightRidio(int *yOutTestClass_D, int *outputTestClass_D, int row, int *wrongNum)
{
	int x_id = blockDim.x * blockIdx.x + threadIdx.x; // ������

	if (x_id < row && yOutTestClass_D[x_id] != outputTestClass_D[x_id])
	{
		//printf("x_id = %d, real = %d, test = %d\n", x_id, outputTestClass_D[x_id], yOutTestClass_D[x_id]);
		atomicAdd((int*)&wrongNum[0], 1);
	}
}

/*
* ���ܣ�BP �㷨ʵ����������д����ʶ��
* ���룺inputTrain_H �����ѵ������
* ���룺inputTest_H ����Ĳ�������
* ���룺outputTrain_H ѵ���������������ǩ��
* ���룺outputTest_H  �����������������ǩ��
*/
void BpMain(float *inputTrain_H, float *inputTest_H, float *outputTrain_H, float *outputTest_H)
{
	/* �����豸���ڴ� */
	float *inputTrain_D, *inputTest_D, *outputTrain_D, *outputTest_D;
	cudaMalloc((void**)&inputTrain_D, trainNum * inLayout * sizeof(float));
	cudaMalloc((void**)&inputTest_D, testNum * inLayout * sizeof(float));
	cudaMalloc((void**)&outputTrain_D, trainNum * outLayout * sizeof(float));
	cudaMalloc((void**)&outputTest_D, testNum * outLayout * sizeof(float));

	float *weightHideIn_D, *weightOutHide_D;
	cudaMalloc((void**)&weightHideIn_D, hideLayout * inLayout * sizeof(float));
	cudaMalloc((void**)&weightOutHide_D, outLayout * hideLayout * sizeof(float));

	float *weightHideInT_D;
	cudaMalloc((void**)&weightHideInT_D, hideLayout * inLayout * sizeof(float));

	float *deltaHideIn_D, *deltaOutHide_D;
	cudaMalloc((void**)&deltaHideIn_D, hideLayout * batchNum * sizeof(float));
	cudaMalloc((void**)&deltaOutHide_D, outLayout * batchNum * sizeof(float));

	float *hideOut_D, *hideOutTest_D;
	cudaMalloc((void**)&hideOut_D, hideLayout * batchNum * sizeof(float));
	cudaMemset(hideOut_D, 0, hideLayout * batchNum * sizeof(float));
	cudaMalloc((void**)&hideOutTest_D, hideLayout * testNum * sizeof(float));

	float *phi_D;
	cudaMalloc((void**)&phi_D, hideLayout * batchNum * sizeof(float));

	float *yOut_D, *yOutTest_D;
	cudaMalloc((void**)&yOut_D, outLayout * batchNum * sizeof(float));
	cudaMalloc((void**)&yOutTest_D, outLayout * testNum * sizeof(float));

	int *yOutTestClass_D, *outputTestClass_D;
	cudaMalloc((void**)&yOutTestClass_D, testNum * sizeof(int));
	cudaMalloc((void**)&outputTestClass_D, testNum * sizeof(int));

	float *w10 = (float*)malloc(hideLayout * inLayout * sizeof(float));
	float *w21 = (float*)malloc(outLayout * hideLayout * sizeof(float));

	int *wrongNum_H = (int*)malloc(sizeof(int));
	int *wrongNum_D;
	cudaMalloc((void**)&wrongNum_D, sizeof(int));
	cudaMemset(wrongNum_D, 0, sizeof(int));

	/* ���ݴ������˿������豸�� */
	cudaMemcpy(inputTrain_D, inputTrain_H, trainNum * inLayout * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(inputTest_D, inputTest_H, testNum * inLayout * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(outputTrain_D, outputTrain_H, trainNum * outLayout * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(outputTest_D, outputTest_H, testNum * outLayout * sizeof(float), cudaMemcpyHostToDevice);


	//std::string strW10 = "D:\\Document\\vidpic\\CUDA\\BP\\data\\6000\\W10.txt";
	//std::string strW21 = "D:\\Document\\vidpic\\CUDA\\BP\\data\\6000\\W21.txt";

	//ReadFile(w10, strW10, hideLayout * inLayout);
	//ReadFile(w21, strW21, outLayout * hideLayout);

	//cudaMemcpy(weightHideIn_D, w10, hideLayout * inLayout * sizeof(float), cudaMemcpyHostToDevice);
	//cudaMemcpy(weightOutHide_D, w21, outLayout * hideLayout * sizeof(float), cudaMemcpyHostToDevice);

	/* �����̸߳���߳̿� */
	dim3 dimBlock2D(BLOCKSIZE, BLOCKSIZE);
	dim3 dimBlock2D_32(BLOCKSIZE_32, BLOCKSIZE_32);
	dim3 dimBlock1D(BLOCKSIZE * BLOCKSIZE);
	dim3 dimGrid2D_hide_in((inLayout + BLOCKSIZE - 1) / dimBlock2D.x, (hideLayout + BLOCKSIZE - 1) / dimBlock2D.y);
	dim3 dimGrid2D_out_hide((hideLayout + BLOCKSIZE - 1) / dimBlock2D.x, (outLayout + BLOCKSIZE - 1) / dimBlock2D.y);
	dim3 dimGrid2D_batch_hide((hideLayout + BLOCKSIZE - 1) / dimBlock2D.x, (batchNum + BLOCKSIZE - 1) / dimBlock2D.y);
	dim3 dimGrid2D_batch_out((outLayout + BLOCKSIZE - 1) / dimBlock2D.x, (batchNum + BLOCKSIZE - 1) / dimBlock2D.y);
	dim3 dimGrid2D_testNum_hide((hideLayout + BLOCKSIZE - 1) / dimBlock2D.x, (testNum + BLOCKSIZE - 1) / dimBlock2D.y);
	dim3 dimGrid2D_testNum_out((outLayout + BLOCKSIZE - 1) / dimBlock2D.x, (testNum + BLOCKSIZE - 1) / dimBlock2D.y);
	dim3 dimGrid1D_testNum(((testNum + BLOCKSIZE - 1) / dimBlock2D.x));
	dim3 dimGrid2D_32_batch_in((inLayout + BLOCKSIZE_32 - 1) / dimBlock2D_32.x, (batchNum + BLOCKSIZE_32 - 1) / dimBlock2D_32.y);

	/* ��¼ʱ�� */
	cudaEvent_t start_GPU, end_GPU;
	float elaspsedTime;
	cudaEventCreate(&start_GPU);
	cudaEventCreate(&end_GPU);
	cudaEventRecord(start_GPU, 0);

	/* Ȩ�س�ʼ�� */
	Bp_Init_Weight<<<dimGrid2D_hide_in, dimBlock2D>>>(weightHideIn_D, hideLayout, inLayout, initWeightMax, 0);
	Bp_Init_Weight<<<dimGrid2D_out_hide, dimBlock2D>>>(weightOutHide_D, outLayout, hideLayout, initWeightMax, 393);

	for (int i = 0; i < 50; i++)
	{
		for (int batch = 0; batch < trainNum; batch += batchNum)
		{
			/* hIn = X * W01' */
			BP_Calculate_HideIn<<<dimGrid2D_32_batch_in, dimBlock2D_32>>>(&inputTrain_D[batch * inLayout], weightHideIn_D, hideOut_D, batchNum, inLayout, hideLayout);

			/* hOut = h(hIn) */
			BP_Calculate_HideOut<<<dimGrid2D_batch_hide, dimBlock2D>>>(hideOut_D, batchNum, hideLayout);

			/* delta2 = xOut - hOut * W21' */
			BP_Calculate_Delta2<<<dimGrid2D_batch_out, dimBlock2D>>>(hideOut_D, weightOutHide_D, deltaOutHide_D, &outputTrain_D[batch * outLayout], batchNum, hideLayout, outLayout);

			/* delta1 = (hOut .* (1 - hOut)) .* (delta2 * W21) */
			BP_Calculate_Delta1<<<dimGrid2D_batch_hide, dimBlock2D>>>(deltaOutHide_D, weightOutHide_D, deltaHideIn_D, hideOut_D, batchNum, outLayout, hideLayout);

			/* W21 = W21 + eta / batchNum * delta2' * hOut */
			BP_Update_Weight<<<dimGrid2D_out_hide, dimBlock2D>>>(deltaOutHide_D, hideOut_D, weightOutHide_D, batchNum, outLayout, hideLayout);

			/* W10 = W10 + eta / batchNum * delta1' * X */
			BP_Update_Weight<<<dimGrid2D_hide_in, dimBlock2D>>>(deltaHideIn_D, &inputTrain_D[batch * inLayout], weightHideIn_D, batchNum, hideLayout, inLayout);
		}
	}

	/* ������� */
	/* hIn = X * W01' */
	MatMulCUDATB<<<dimGrid2D_testNum_hide, dimBlock2D>>>(inputTest_D, weightHideIn_D, hideOutTest_D, testNum, inLayout, hideLayout);

	/* hOut = h(hIn) */
	BP_Calculate_HideOut<<<dimGrid2D_testNum_hide, dimBlock2D>>>(hideOutTest_D, testNum, hideLayout);

	/* yOut = hOut * W21' */
	MatMulCUDATB<<<dimGrid2D_testNum_out, dimBlock2D>>>(hideOutTest_D, weightOutHide_D, yOutTest_D, testNum, hideLayout, outLayout);

	/* [output_result, ~] = find(bsxfun(@eq, yOut, max(yOut)) ~= 0); */
	BP_Calculate_Class<<<dimGrid2D_testNum_out, dimBlock2D>>>(yOutTestClass_D, yOutTest_D, testNum, outLayout);
	BP_Calculate_Class<<<dimGrid2D_testNum_out, dimBlock2D>>>(outputTestClass_D, outputTest_D, testNum, outLayout);
	
	/* ����׼ȷ�� */
	BP_Calculate_RightRidio<<<dimGrid1D_testNum, dimBlock1D>>>(yOutTestClass_D, outputTestClass_D, testNum, wrongNum_D);

	/* ��ʱ���� */
	cudaEventRecord(end_GPU, 0);
	cudaEventSynchronize(end_GPU);
	cudaEventElapsedTime(&elaspsedTime, start_GPU, end_GPU);

	/* ��ӡ��Ϣ */
	std::cout << "BP ��ʱ��Ϊ��" << elaspsedTime << "ms." << std::endl;

	cudaMemcpy(wrongNum_H, wrongNum_D, sizeof(int), cudaMemcpyDeviceToHost);
	printf("BP �ľ���Ϊ��%.2f%%\n", 100.0f*float(testNum - *wrongNum_H) / float(testNum));

	cudaMemcpy(w10, weightHideIn_D, hideLayout * inLayout * sizeof(float), cudaMemcpyDeviceToHost);
	cudaMemcpy(w21, weightOutHide_D, outLayout * hideLayout * sizeof(float), cudaMemcpyDeviceToHost);

	std::string strW10result = "D:\\Document\\vidpic\\CUDA\\BP\\data\\6000\\W10result.txt";
	std::string strW21result = "D:\\Document\\vidpic\\CUDA\\BP\\data\\6000\\W21result.txt";

	SaveFile(w10, strW10result, hideLayout * inLayout);
	SaveFile(w21, strW21result, outLayout * hideLayout);

	/* �ͷ��豸���ڴ� */
	cudaFree(inputTrain_D);
	cudaFree(inputTest_D);
	cudaFree(outputTrain_D);
	cudaFree(outputTest_D);
}