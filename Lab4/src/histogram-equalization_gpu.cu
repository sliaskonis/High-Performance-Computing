extern "C" {
    #include <stdio.h>
    #include <cuda_runtime.h>
    #include <time.h>
    #include "hist-equ.h"

    #define MAX_THREADS_PER_BLOCK 1024
    #define GRID_DIM ceil(((float)img_size/MAX_THREADS_PER_BLOCK))

	/****************************** Helper Functions ******************************/
	bool checkCudaError(const char *step) {
		cudaError_t err = cudaGetLastError();
		if (err != cudaSuccess) {
			printf("Error in %s: %s\n", step, cudaGetErrorString(err));
			return true;
		}
		return false;
	}

	/****************************** Kernels ******************************/

    // Histogram calculation: stride implementation
	// __global__ void histogram_calc(int *hist_out, unsigned char *img_in, int img_size, int nbr_bin) {
    //     __shared__ int private_hist[256];

    //     int i = threadIdx.x + blockIdx.x*blockDim.x,
    //         stride = blockDim.x * gridDim.x;

    //     if (threadIdx.x < nbr_bin) {
    //         private_hist[threadIdx.x] = 0;
    //     }
    //     __syncthreads();
		
    //     while (i < img_size) {
    //         atomicAdd(&(private_hist[img_in[i]]), 1);
    //         i += stride;
    //     }
    //     __syncthreads();
        
    //     if (threadIdx.x < nbr_bin) {
    //         atomicAdd(&(hist_out[threadIdx.x]), private_hist[threadIdx.x]);
    //     }
    // }

    // Histogram calculation: naive implementation
    __global__ void histogram_calc(int *d_hist_out, unsigned char *d_img_in, int nbr_bin) {
        int tid = threadIdx.x + blockIdx.x*blockDim.x;
		
        atomicAdd(&(d_hist_out[d_img_in[tid]]), 1);
    }

    // Histogram equalization application: naive implementation
    __global__ void histogram_equ(unsigned char *d_img_in, int *d_lut) {
        int tid = threadIdx.x + blockIdx.x*blockDim.x;
        
        if (d_lut[d_img_in[tid]] > 255) {
            d_img_in[tid] = 255;
        }
        else {
            d_img_in[tid] = (unsigned char)d_lut[d_img_in[tid]];
        }
    }

	// Kernel wrapper
    void histogram_gpu(unsigned char *img_in,
                                int img_size, int nbr_bin) {
        int padding = 0, padded_size = 0;
        float elapsed_time;
        int i, cdf, min, d;
        int *lut = (int *)malloc(sizeof(int)*nbr_bin);
        int *hist_out = (int *)malloc(sizeof(int)*nbr_bin);

		unsigned char *d_img_in;
        int *d_hist_out;
        int *d_lut;

        cudaEvent_t gpu_start, gpu_stop, memory_transfers, hist_kernel, hist_equ_kernel;
        cudaEventCreate(&gpu_start);
        cudaEventCreate(&gpu_stop);
        cudaEventCreate(&memory_transfers);
        cudaEventCreate(&hist_kernel);
        cudaEventCreate(&hist_equ_kernel);

        dim3 block(MAX_THREADS_PER_BLOCK, 1, 1);
        dim3 grid(GRID_DIM, 1, 1);

        cudaEventRecord(gpu_start, 0);
        /************************* Device Memory Allocation *************************/
        padding = (img_size%MAX_THREADS_PER_BLOCK) ? (MAX_THREADS_PER_BLOCK - (img_size%MAX_THREADS_PER_BLOCK)) : 0;

		padded_size = img_size + padding;
		cudaMalloc((void**) &d_img_in,	 sizeof(unsigned char)*padded_size);
        cudaMalloc((void**) &d_hist_out, sizeof(int)*nbr_bin);
        cudaMalloc((void**) &d_lut,      sizeof(int)*nbr_bin);

        cudaMemset (d_img_in,   0, sizeof(unsigned char)*padded_size);
        cudaMemset (d_hist_out, 0, sizeof(int)*nbr_bin);
        
		cudaMemcpy(d_img_in, img_in, sizeof(unsigned char)*img_size, cudaMemcpyHostToDevice);

        cudaEventRecord(memory_transfers, 0);

        /************************* Histogram calculation kernel launch *************************/
        histogram_calc<<<grid, block>>>(d_hist_out, d_img_in, nbr_bin);
		
        cudaEventRecord(hist_kernel, 0);
        cudaEventSynchronize(hist_kernel);

		checkCudaError("Histogram calculation");

		// Copy calculated histogram back to host 
        cudaMemcpy(hist_out, d_hist_out, sizeof(int)*nbr_bin, cudaMemcpyDeviceToHost);

        // Clean histogram counts added by the padding elements
		// Padding elements are set to 0
        hist_out[0] = hist_out[0] - padding;
		
        // Construct the LUT by calculating the CDF
        cdf = 0;
        min = 0;
        i = 0;
        while(min == 0){
            min = hist_out[i++];
        }
        d = img_size - min;
        for(i = 0; i < nbr_bin; i ++){
            cdf += hist_out[i];
            lut[i] = (int)(((float)cdf - min)*255/d + 0.5);
            if(lut[i] < 0){
                lut[i] = 0;
            }
        }    
        
        cudaMemcpy(d_lut, lut, sizeof(int)*nbr_bin, cudaMemcpyHostToDevice);
        
        /************************* Histogram equalization kernel launch *************************/
        histogram_equ<<<grid, block>>>(d_img_in, d_lut);
        
        cudaEventRecord(hist_equ_kernel, 0);
        cudaEventSynchronize(hist_equ_kernel);

        cudaDeviceSynchronize();
        checkCudaError("Histogram equalization");

        // Copy img back to host
        cudaMemcpy(img_in, d_img_in, sizeof(unsigned char)*img_size, cudaMemcpyDeviceToHost);

        // Free non-wanted memory
        cudaFree(d_lut);
        cudaFree(d_img_in);
        cudaFree(d_hist_out);

        cudaEventRecord(gpu_stop, 0);
        cudaEventSynchronize(gpu_stop);
        
        // Calculate elapsed time for all events
        cudaEventElapsedTime(&elapsed_time, gpu_start, gpu_stop);
        printf("Total GPU time: %f sec, consists of:\n", elapsed_time/1000);

        cudaEventElapsedTime(&elapsed_time, gpu_start, memory_transfers);
        printf("\t%f (memory transfers)\n", elapsed_time/1000);

        cudaEventElapsedTime(&elapsed_time, memory_transfers, hist_kernel);
        printf("\t%f (histogram kernel)\n", elapsed_time/1000);

        cudaEventElapsedTime(&elapsed_time, hist_kernel, hist_equ_kernel);
        printf("\t%f (histogram equalization kernel)\n", elapsed_time/1000);

        cudaEventElapsedTime(&elapsed_time, hist_equ_kernel, gpu_stop);
        printf("\t%f (memory transfers + cleanup)\n", elapsed_time/1000);

        // Reset the device
        cudaDeviceReset();
    }
}