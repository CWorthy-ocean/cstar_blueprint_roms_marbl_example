#!/bin/bash

MY_SYSTEM=$(uname -s)_$(uname -m)
if [ ! -z ${LMOD_SYSHOST} ];then
    MY_SYSTEM+=_${LMOD_SYSHOST}
elif [ ! -z ${LMOD_SYSTEM_NAME} ];then
    MY_SYSTEM+=_${LMOD_SYSTEM_NAME}
fi

case "$MY_SYSTEM" in
    Darwin_arm64)
        SCHEDULER=NONE
        ;;
    Linux_x86_64_derecho)
        SCHEDULER=PBS
	PARTITION=develop
        ;;
    Linux_x86_64_expanse|Linux_x86_64_perlmutter)
	SCHEDULER=SLURM
	PARTITION=debug
	;;
    *)
        echo "System not recognised"
	exit 1
        ;;
esac

case "$SCHEDULER" in
    NONE)
        ./start_run.sh
        ;;
    PBS)
        if [ -z "${ACCOUNT_KEY}" ];then
            echo "ACCOUNT_KEY environment variable empty. Set using export ACCOUNT_KEY=<your_account_key>."
            exit 1
        fi
	qsub -N "roms_marbl_example_2" \
	     -o "roms_marbl_example.out" \
	     -A ${ACCOUNT_KEY} \
	     -l select=1:ncpus=9,walltime=00:10:00 \
	     -q ${PARTITION} \
	     -j oe -k eod \
	     -V \
	     start_run.sh	
        ;;
    SLURM)
	if [ -z "${ACCOUNT_KEY}" ];then
            echo "ACCOUNT_KEY environment variable empty. Set using export ACCOUNT_KEY=<your_account_key>."
            exit 1
        fi
        sbatch --job-name="roms_marbl_example" \
               --output="roms_marbl_example.out" \
               --partition=${PARTITION} \
               --nodes=1 \
               --ntasks-per-node=9 \
               --account=${ACCOUNT_KEY} \
               --export=ALL \
               --mail-type=ALL \
               -t 00:30:00 \
               start_run.sh
        ;;
esac



