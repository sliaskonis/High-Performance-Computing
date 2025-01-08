#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "timer.h"

#define SOFTENING 1e-9f  /* Will guard against denormals */
#define THREADS_PER_BLOCK 1024

typedef struct { float *x, *y, *z, *vx, *vy, *vz;} Body;

/****************************** Helper Functions ******************************/
void checkCudaError(const char *step) {
	cudaError_t err = cudaGetLastError();
	if (err != cudaSuccess) {
		printf("Error in %s: %s\n", step, cudaGetErrorString(err));
		cudaDeviceReset();
		exit(1);
	}
}

void randomizeBodies(Body *bodies, int n) {
  	for (int i = 0; i < n; i++) {
    	bodies->x[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
    	bodies->y[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
    	bodies->z[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
    	bodies->vx[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
    	bodies->vy[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
    	bodies->vz[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
  	}
}

/***************** KERNEL CODE *****************/
__global__ void bodyForce(Body p, float dt, int n) {
	int tid = threadIdx.x + blockIdx.x*blockDim.x;

	float dx, dy, dz;
	float distSqr, invDist, invDist3;
	float Fx = 0.0f;
	float Fy = 0.0f;
	float Fz = 0.0f;

	for (int i = 0; i < n; i++) {
		dx = p.x[i] - p.x[tid];
		dy = p.y[i] - p.y[tid];
		dz = p.z[i] - p.z[tid];
		distSqr = dx*dx + dy*dy + dz*dz + SOFTENING;
		invDist = 1.0f / sqrtf(distSqr);
		invDist3 = invDist * invDist * invDist;

		Fx += dx * invDist3; 
        Fy += dy * invDist3; 
        Fz += dz * invDist3;
	}

    p.vx[tid] += dt*Fx;
	p.vy[tid] += dt*Fy;
	p.vz[tid] += dt*Fz;
}

int main(const int argc, const char** argv) {

  	int nBodies = 30000;
  	if (argc > 1) nBodies = atoi(argv[1]);

  	const float dt = 0.01f; // time step
  	const int nIters = 10;  // simulation iterations

	float totalTime = 0.0f, elapsed_time = 0.0f;
	Body bodies, d_bodies;

	cudaEvent_t iter_start, iter_end;

	cudaEventCreate(&iter_start);
	cudaEventCreate(&iter_end);

	/****************************** Host memory allocation ******************************/
	int bytes = sizeof(float)*nBodies;
	bodies.x = (float *)malloc(bytes);
	bodies.y = (float *)malloc(bytes);
	bodies.z = (float *)malloc(bytes);
	bodies.vx = (float *)malloc(bytes);
	bodies.vy = (float *)malloc(bytes);
	bodies.vz = (float *)malloc(bytes);

  	randomizeBodies(&bodies, nBodies); // Init pos / vel data

	// Set geometry
	dim3 block(THREADS_PER_BLOCK, 1, 1);
	dim3 grid((int)(ceil(nBodies/THREADS_PER_BLOCK)), 1, 1);

	/****************************** Data transfers ******************************/
	cudaMalloc((void **) &d_bodies.x, bytes);
	cudaMalloc((void **) &d_bodies.y, bytes);
	cudaMalloc((void **) &d_bodies.z, bytes);
	cudaMalloc((void **) &d_bodies.vx, bytes);
	cudaMalloc((void **) &d_bodies.vy, bytes);
	cudaMalloc((void **) &d_bodies.vz, bytes);

	cudaMemcpy(d_bodies.x,  bodies.x,  bytes, cudaMemcpyHostToDevice);
	cudaMemcpy(d_bodies.y,  bodies.y,  bytes, cudaMemcpyHostToDevice);
	cudaMemcpy(d_bodies.z,  bodies.z,  bytes, cudaMemcpyHostToDevice);
	cudaMemcpy(d_bodies.vx, bodies.vx, bytes, cudaMemcpyHostToDevice);
	cudaMemcpy(d_bodies.vy, bodies.vy, bytes, cudaMemcpyHostToDevice);
	cudaMemcpy(d_bodies.vz, bodies.vz, bytes, cudaMemcpyHostToDevice);

	/****************************** Real Computation ******************************/
  	for (int iter = 1; iter <= nIters; iter++) {
		cudaEventRecord(iter_start, 0);
		
		bodyForce<<<grid, block>>>(d_bodies, dt, nBodies);
		checkCudaError("bodyForce");
        cudaDeviceSynchronize();

        // Transfer data back to host in order to compute new coordinates
	    cudaMemcpy(bodies.vx, d_bodies.vx, bytes, cudaMemcpyDeviceToHost);
	    cudaMemcpy(bodies.vy, d_bodies.vy, bytes, cudaMemcpyDeviceToHost);
	    cudaMemcpy(bodies.vz, d_bodies.vz, bytes, cudaMemcpyDeviceToHost);


        for (int i = 0 ; i < nBodies; i++) { // integrate position
            bodies.x[i] += bodies.vx[i]*dt;
            bodies.y[i] += bodies.vy[i]*dt;
            bodies.z[i] += bodies.vz[i]*dt;
        }

        // Tranfer new coordinates back to device for next computations
		cudaMemcpy(d_bodies.x, bodies.x, bytes, cudaMemcpyHostToDevice);
	    cudaMemcpy(d_bodies.y, bodies.y, bytes, cudaMemcpyHostToDevice);
	    cudaMemcpy(d_bodies.z, bodies.z, bytes, cudaMemcpyHostToDevice);

        cudaEventRecord(iter_end, 0);
		cudaEventSynchronize(iter_end);

		cudaEventElapsedTime(&elapsed_time, iter_start, iter_end);
    	if (iter > 1) { // First iter is warm up
      		totalTime += elapsed_time/1000.0f;
    	}
    	printf("Iteration %d: %.3f seconds\n", iter, elapsed_time/1000.0f);
  	}

  	float avgTime = totalTime / (float)(nIters-1);

  	printf("%d Bodies: average %0.3f Billion Interactions / second\n", nBodies, 1e-9 * nBodies * nBodies / avgTime);
	printf("Total time: %.3f\n", totalTime);

#ifdef SAVE_FINAL_COORDINATES
	/****************************** Save Final Coordinates ******************************/
	char filename[256];

	sprintf(filename, "cuda_coordinates_%d.txt", nBodies);

	printf("Writing final coordinates to %s\n", filename);
	FILE *fd = fopen(filename, "w");

	if (!fd) {
		perror("Failed opening file");
		return -1;
	}

	for (int i = 0; i < nBodies; i++) {
		fprintf(fd, "%f\n", bodies.x[i]);
		fprintf(fd, "%f\n", bodies.y[i]);
		fprintf(fd, "%f\n", bodies.z[i]);
	}

	fclose(fd);

	printf("Data written successfully\n");
#endif

	/****************************** Cleanup ******************************/
	// Device
	cudaFree(d_bodies.x);
	cudaFree(d_bodies.y);
	cudaFree(d_bodies.z);
	cudaFree(d_bodies.vx);
	cudaFree(d_bodies.vy);
	cudaFree(d_bodies.vz);	
	
	// Host
	free(bodies.x);
	free(bodies.y);
	free(bodies.z);
	free(bodies.vx);
	free(bodies.vy);
	free(bodies.vz);	

	cudaDeviceReset();
}