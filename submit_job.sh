#!/bin/bash                                                                                                                                                                                                            

cstar_env # activate C-Star environment                                                                                                                                                                                

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
        ;;
    *)
        echo "System $CSTAR_SYSTEM not recognised. Configure your ROMS-MARBL environment using C-Star (https://github.com/CWorthy-ocean/C-Star)"
        ;;
esac

case "$SCHEDULER" in
    NONE)
        ./fromrestart_run.sh
        ;;
    PBS)
        echo "todo next"
        ;;
    SLURM)
        sbatch --job-name="roms_marbl_example" \
               --output="roms_marbl_example.out" \
               --partition=${PARTITION} \
               --nodes=1 \
               --ntasks-per-node=9 \
               --account=${ACCOUNT_KEY} \
               --export=ALL \
               --mail-type=ALL \
               -t 00:10:00 \
               --wrap="./fromrestart_run.sh"
        ;;
esac



