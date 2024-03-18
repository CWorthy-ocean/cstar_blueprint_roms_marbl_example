#!/bin/bash

################################################################################
# This "fromrestart" run begins one day later than the "fromscratch" run,
# allowing the use of a ROMS-generated restart file. It is assumed the user has
# already run ./fromscratch_run.sh to produce {MARBL,BEC}_rst.20120102120000.nc
################################################################################

## Set environment variables
source ~/.ROMS 
NP_XI=3; # from code/param.opt
NP_ETA=3;

if grep -q "\!\# define BIOLOGY_BEC2" code/cppdefs.opt;
then
    if grep -q "\!\# define MARBL\b" code/cppdefs.opt;
    then
	PREFIX=NOBGC # No biology
    elif grep -q "\# define MARBL\b" code/cppdefs.opt;
    then
	 PREFIX=MARBL # BGC with MARBL
    fi
elif grep -q "\# define BIOLOGY_BEC2" code/cppdefs.opt;
then
    PREFIX=BEC # BGC with BEC
fi


# Split the initial and boundary conditions for use on multiple CPUs (default 8)
rundir=$(pwd)
cd INPUT/
mkdir PARTED/
for X in {\
roms_bry_2012.nc,roms_bry_bgc_"${PREFIX}".nc,roms_frc.201112.nc,\
roms_frc.2012??.nc,roms_frc_bgc.nc,roms_grd.nc,\
"${PREFIX}"_rst.20120103120000.nc};do

    if [ "${X}" = "roms_bry_bgc_NOBGC.nc" ];then continue;fi
    
    if [ -e PARTED/"${X/.nc}".0.nc ];then
	echo "INPUT/${X} appears to have already been partitioned. Continuing."
	continue
    else
    partit "${NP_XI}" "${NP_ETA}" "${X}";
    mv -v "${X/.nc}".?.nc PARTED/
    fi
done
cd ${rundir}
if [ ! -d RST ];then mkdir RST;fi
ln -s ${rundir}/INPUT/PARTED/${PREFIX}_rst.20120103120000.?.nc RST/

mpirun -n 9 ./roms ./roms.in_"${PREFIX}"


echo "MAIN RUN DONE"
echo "########################################################################"

cp ${PREFIX}_rst.*.?.nc RST/

for X in ${PREFIX}_???.*.0.nc; do
    ncjoin ${X/.0.nc}.?.nc
    if [ -e ${X/.0.nc}.nc ]; then
	rm ${X/.0.nc}.?.nc
    fi
done
