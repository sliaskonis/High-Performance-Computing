#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include "hist-equ.h"

void run_cpu_gray_test(PGM_IMG img_in, char *out_filename);
void run_gpu_gray_test(PGM_IMG img_in, char *out_filename);

int main(int argc, char *argv[]){
    PGM_IMG img_ibuf_g;
    PGM_IMG img_ibuf_cpu;
    PGM_IMG img_ibuf_gpu;

	if (argc != 4) {
		printf("Run with input file name and output file name as arguments\n");
		exit(1);
	}

    printf("Running contrast enhancement for gray-scale images.\n");
    img_ibuf_g = read_pgm(argv[1]);
    run_cpu_gray_test(img_ibuf_g, argv[2]);
    free_pgm(img_ibuf_g);

    printf("Running contrast enhancement for gray-scale images on gpu.\n");
    img_ibuf_g = read_pgm(argv[1]);
    run_gpu_gray_test(img_ibuf_g, argv[3]);
    free_pgm(img_ibuf_g);

#ifdef DEBUG
    img_ibuf_cpu = read_pgm(argv[2]);
    img_ibuf_gpu = read_pgm(argv[3]);
    
    int errors = 0;
    for (int i = 0; i < img_ibuf_g.h*img_ibuf_g.w; i++) {
        if (img_ibuf_cpu.img[i] != img_ibuf_gpu.img[i]) {
            if (errors < 100) {
                printf("Error in [%d]: cpu[%d] = %d gpu[%d] = %d\n", i, i, img_ibuf_cpu.img[i], i, img_ibuf_gpu.img[i]);
            }
            errors++;
        }
    }

    printf("Number of errors: %d\n", errors);
#endif

    free_pgm(img_ibuf_cpu);
    free_pgm(img_ibuf_gpu);
    return 0;
}

void run_cpu_gray_test(PGM_IMG img_in, char *out_filename)
{
    unsigned int timer = 0;
    PGM_IMG img_obuf;
    clock_t start, end;

    printf("Starting CPU processing...\n");
    start = clock();
    img_obuf = contrast_enhancement_cpu(img_in);
    end = clock();

    double time_taken = (double)(end - start) / CLOCKS_PER_SEC;
    printf("CPU time: %f\n", time_taken);
    
    write_pgm(img_obuf, out_filename);
    free_pgm(img_obuf);
}

void run_gpu_gray_test(PGM_IMG img_in, char *out_filename)
{
    unsigned int timer = 0;
    PGM_IMG img_obuf;
    clock_t start, end;

    printf("Starting GPU processing...\n");
    start = clock();
    img_obuf = contrast_enhancement_gpu(img_in);
    end = clock();

    double time_taken = (double)(end - start) / CLOCKS_PER_SEC;
    printf("GPU time: %f\n", time_taken);
    
    write_pgm(img_obuf, out_filename);
    free_pgm(img_obuf);
}

PGM_IMG read_pgm(const char * path){
    FILE * in_file;
    char sbuf[256];

    PGM_IMG result;
    int v_max;//, i;
    in_file = fopen(path, "r");
    if (in_file == NULL){
        printf("Input file not found!\n");
        exit(1);
    }

    fscanf(in_file, "%s", sbuf); /*Skip the magic number*/
    fscanf(in_file, "%d",&result.w);
    fscanf(in_file, "%d",&result.h);
    fscanf(in_file, "%d\n",&v_max);
#ifndef DEBUG
    printf("Image size: %d x %d\n", result.w, result.h);
#endif
    result.img = (unsigned char *)malloc(result.w * result.h * sizeof(unsigned char));

    fread(result.img,sizeof(unsigned char), result.w*result.h, in_file);
    fclose(in_file);

    return result;
}

void write_pgm(PGM_IMG img, const char * path){
    FILE * out_file;
    out_file = fopen(path, "wb");
    fprintf(out_file, "P5\n");
    fprintf(out_file, "%d %d\n255\n",img.w, img.h);
    fwrite(img.img,sizeof(unsigned char), img.w*img.h, out_file);
    fclose(out_file);
}

void free_pgm(PGM_IMG img)
{
    free(img.img);
}

