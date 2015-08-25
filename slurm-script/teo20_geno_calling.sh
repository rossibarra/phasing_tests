#!/bin/bash
#SBATCH -D /Users/yangjl/Documents/Github/phasing_tests
#SBATCH -o /Users/yangjl/Documents/Github/phasing_tests/slurm-log/testout-%j.txt
#SBATCH -e /Users/yangjl/Documents/Github/phasing_tests/slurm-log/err-%j.txt
#SBATCH -J align_test
#SBATCH--mail-user=yangjl0930@gmail.com
#SBATCH--mail-type=END
#SBATCH--mail-type=FAIL #email if fails
set -e
set -u

angsd -nThreads 10 -doMajorMinor 3 -sites largedata/genotype_calls/head10_gbs_sites_v2.txt -GL 2 -bam largedata/genotype_calls/teo20_bamfiles_v2.txt -doGeno 5 -out largedata/genotype_calls/geno_call
