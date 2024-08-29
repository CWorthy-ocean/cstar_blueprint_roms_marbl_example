#!/bin/bash


SCRIPT_DIR=$(dirname "$(realpath "$0")") # location of this .sh file
CASEROOT=$(realpath "$SCRIPT_DIR/../..")
ROMS_EXE=${CASEROOT}/source_mods/ROMS/roms
INPUT_DIR=${CASEROOT}/input_datasets
OUTPUT_DIR=${CASEROOT}/output
if [ ! -d ${OUTPUT_DIR} ];then
    mkdir ${OUTPUT_DIR};
fi
ROMS_NAMELIST_DIR=${CASEROOT}/namelists/ROMS
MARBL_NAMELIST_DIR=${CASEROOT}/namelists/MARBL

if [ ! -e ${ROMS_EXE} ];then
    echo "ROMS executable (${ROMS_EXE}) not found. Ensure your case root directory (${CASEROOT}) is correct \n
    and that the model has been successfully compiled in ${CASEROOT}/source_mods/ROMS/"
    exit 1
fi

if [ -z ${CSTAR_SYSTEM} ];then
    if [ ! -z ${LMOD_SYSHOST} ];then
	case ${LMOD_SYSHOST} in
	    expanse)
		CSTAR_SYSTEM=sdsc_expanse_intel
		;;
	    derecho)
		CSTAR_SYSTEM=ncar_derecho_intel
		;;
	    perlmutter)
		CSTAR_SYSTEM=nersc_perlmutter_gnu
		;;
	esac
    elif [[ "$(uname)" == "Darwin" ]] && [[ "$(uname -m)" == "arm64" ]]; then
	CSTAR_SYSTEM=osx_arm64_gnu
    fi
fi



case "$CSTAR_SYSTEM" in
    osx_arm64_gnu)
        ROMS_EXEC_CMD() {
            mpirun -n 9 ${ROMS_EXE} ${ROMS_NAMELIST_DIR}/roms.in
        }
        ;;
    sdsc_expanse_intel)
        ROMS_EXEC_CMD() {
            srun --mpi=pmi2 -n 9 ${ROMS_EXE} ${ROMS_NAMELIST_DIR}/roms.in
        }
        ;;
    ncar_derecho_intel)
	cd $PBS_O_WORKDIR
        ROMS_EXEC_CMD() {
            mpirun -n 9 ${ROMS_EXE} ${ROMS_NAMELIST_DIR}/roms.in
        }
        ;;
    *)
        echo "System $CSTAR_SYSTEM not recognised. Configure your ROMS-MARBL environment using C-Star (https://github.com/CWorthy-ocean/C-Star)"
	exit 1
	;;
esac


NP_XI=3; # from code/param.opt
NP_ETA=3;

if grep -q "\!\# define BIOLOGY_BEC2" ${CASEROOT}/source_mods/ROMS/cppdefs.opt;
then
    if grep -q "\!\# define MARBL\b" ${CASEROOT}/source_mods/ROMS/cppdefs.opt;
    then
	PREFIX=ROMS_NOBGC # No biology
    elif grep -q "\# define MARBL\b" ${CASEROOT}/source_mods/ROMS/cppdefs.opt;
    then
	 PREFIX=ROMS_MARBL # BGC with MARBL
    fi
elif grep -q "\# define BIOLOGY_BEC2" ${CASEROOT}/source_mods/ROMS/cppdefs.opt;
then
    PREFIX=ROMS_BEC # BGC with BEC
fi


# Split the initial and boundary conditions for use on multiple CPUs (default 8)
#rundir=$(pwd)
#if [ -e roms ];then rm roms;fi
#ln -s code/roms .

cd ${ROMS_NAMELIST_DIR}
cp roms.in_${PREFIX/"ROMS_"} roms.in
perl -pi -e "s|INPUT_DIR|$INPUT_DIR|g"                   roms.in
perl -pi -e "s|MARBL_NAMELIST_DIR|$MARBL_NAMELIST_DIR|g" roms.in

cd ${INPUT_DIR}/
mkdir PARTED/
for X in {\
roms_bry_2012.nc,roms_bry_bgc_"${PREFIX/'ROMS_'}".nc,roms_frc.201112.nc,\
roms_frc.2012??.nc,roms_frc_bgc.nc,roms_grd.nc,\
"${PREFIX/'ROMS_'}"_rst.20120103120000.nc};do

    if [ "${X}" = "roms_bry_bgc_NOBGC.nc" ];then continue;fi
    
    if [ -e PARTED/"${X/.nc}".0.nc ];then
	echo "INPUT/${X} appears to have already been partitioned. Continuing."
	continue
    else
    partit "${NP_XI}" "${NP_ETA}" "${X}";
    mv -v "${X/.nc}".?.nc PARTED/
    fi
done
cd ${OUTPUT_DIR}
#if [ ! -d RST ];then mkdir RST;fi
#ln -s ${rundir}/INPUT/PARTED/${PREFIX}_rst.20120103120000.?.nc RST/

#mpirun -n 9 ./roms ./roms.in_"${PREFIX}"
ROMS_EXEC_CMD


echo "MAIN RUN DONE"
echo "########################################################################"
if [ ! -d RST ];then mkdir RST;fi
cp ${PREFIX}_rst.*.?.nc RST/

for X in ${PREFIX}_*.*.0.nc; do
    ncjoin ${X/.0.nc}.?.nc
    if [ -e ${X/.0.nc}.nc ]; then
	rm ${X/.0.nc}.?.nc
    fi
done
