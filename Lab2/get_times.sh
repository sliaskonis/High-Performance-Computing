#!/bin/bash

cd opt_src
make 

# Directory to store results
mkdir -p ../results

# Execute the sequential test 10 times and save results
for i in {1..22}
do 
    ./seq_main -o -b -n 2000 -i ../Image_data/color17695.bin
done > ../results/seq_times.txt

# Execute each parallel version 10 times and save the results
for j in {1..8}
do
    for i in {1..22}
    do 
        ./par_main_$j -o -b -n 2000 -i ../Image_data/color17695.bin
    done > ../results/parallel_${j}_times.txt
done

make clean
