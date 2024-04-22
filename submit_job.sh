#!/bin/bash

case "$CSTAR_SYSTEM" in
    osx_arm64_gnu)
        SCHEDULER=NONE
        ;;
    sdsc_expanse_intel)
        SCHEDULER=SLURM
        PARTITION=debug
         ;;
    ncar_derecho_intel)
        SCHEDULER=PBS
	PARTITION=develop
        ;;
    *)
        echo "System $CSTAR_SYSTEM not recognised. Configure your ROMS-MARBL environment using C-Star (https://github.com/CWorthy-ocean/C-Star)"
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



