# roms_marbl_example
An example configuration of [ucla-roms](https://github.com/CESR-lab/ucla-roms) with a 24x24 domain of the Welsh coast.
BGC is handled by either [BEC]( https://doi.org/10.1029/2004GB002220) or [MARBL](https://doi.org/10.1029/2021MS002647) with BGC initial and boundary conditions taken from an existing run of CESM.


## Installation
This configuration can be run wherever you are already running ROMS, but has been set up to be run on Mac OSX with ARM64 architecture (2020 or later Macs with Apple silicon). 
ROMS can be compiled on OSX using the following steps

1. Set up a conda environment 

```
conda create -n roms_marbl
conda install -c conda-forge compilers
conda install netcdf-fortran -c conda-forge
conda install -c conda-forge nco ncview
```
(Any python packages should also be installed from `conda-forge` to prevent clashes).

2. [MARBL](https://github.com/marbl-ecosys/MARBL/) should be obtained and compiled using this environment (this configuration is working with [`marbl0.45`](https://github.com/marbl-ecosys/MARBL/releases/tag/marbl0.45.0)).
Checkout the [`development` branch](https://github.com/marbl-ecosys/MARBL/tree/development). In `$MARBL_ROOT/src/Makefile` set `USEMPI=TRUE` and run `make`, which should produce the file `libmarbl-gnu-mpi.a` at `$MARBL_ROOT/lib/`.

3. Create a `.ROMS` file in your home directory (this is the convention used in the running scripts contained in this repo), and `source` it so as to set certain environment variables:
```
CONDA_ENV=roms_marbl

export ROMS_ROOT=<the local location of the [ucla-roms repo](https://github.com/CESR-lab/ucla-roms)>
export MPIHOME=${CONDA_PREFIX} #e.g. /Users/you/miniconda3/envs/roms_marbl
export NETCDFHOME=${CONDA_PREFIX}
export MARBL_ROOT=<the local location of the [MARBL repo](https://github.com/marbl-ecosys/MARBL/)>
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$NETCDFHOME/lib"
export PATH="./:$PATH"
export PATH=$PATH:$ROMS_ROOT/Tools-Roms
```
4. copy this repo into a subdirectory of `ucla-roms` (`$ROMS_ROOT/Examples/` is recommended)
5. go to `code` and run `make`, which should produce an executable (`roms`) locally. This configuration is set to run on 8 CPUs.
   By default, ROMS will compile with BGC being handled by MARBL.
   To switch to BEC, comment (prepend a `!` to) `#define MARBL` in `code/cppdefs.opt` and run `make` again.
   To run without BGC, additionally undefine the `BIOLOGY_BEC2` cpp key.

## Running
All of the initial and boundary condition files to run for the month of January 2012 are provided in `INPUT` for both BEC and MARBL. 
To run the model, simply run the script `fromscratch_run.sh` in a terminal, which will determine whether the MARBL cpp key is active and choose the necessary input files and namelists accordingly.
The input files are split (one per processor) using the `partit` tool in `$ROMS_ROOT/Tools-Roms` which should be on your path after being added by the `.ROMS` file in Step 3, then the model is run.
The output files are similarly joined using the `ncjoin` tool.
The `fromscratch_run.sh` script chooses the corresponding `roms.in` file to run for 1 day with a 36 second timestep while the model stabilises after being initialised from external data. 
The `fromrestart_run.sh` script can then be used, utilising a restart file created by the previous run and increasing the time step to 6 minutes and the run length to 28 days.

## Running with modified settings
The layout of processors is set (`NP_XI`,`NP_ETA`) in `code/param.opt` should you wish to change from the default (4,2), but the model will need to be recompiled, and the `.sh` files will need to be updated before running.
The output frequency is set in `code/ocean_vars.opt`. A recompile will be necessary to change this.

## MODIFICATIONS FROM ROMS SOURCE CODE
- addition of the `marbl_driver` module, which interfaces between MARBL and ROMS
- addition of the `bulk_wnd` module, which prevents a circular dependency when providing wind to MARBL. Largely mirrors `bulk_frc`.
- Modifications to `grid`,`bgc`,`tracers`, and `read_write` modules to allow compilation with `gfortran` (ensuring character arrays have entries of equal length, and `.eqv.` is used over `==`)
- addition of a `#MARBL` cpp key
- activation of `NOX` and `NHY` forcing (previously incomplete but needed for MARBL; activated with `#NOX_FORCING` and `NHY_FORCING`)
- modifications to `step3d_t_ISO` and `tracers` modules to interface with MARBL
- Changes to `Makefile` and `Makedefs.inc` to allow compilation on non-case-sensitive file systems (OSX default behaviour):
     - Preprocessed `.F` files now use a `.fpp` extension and are not deleted.
     - `Make.depend` is not generated at compile time, but fixed and copied from `code`. `makedepf90` does not appear to work in the above conda environment.
     - Compiler flags added to incorporate MARBL.
