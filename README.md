# roms_marbl_example
An example configuration of [ucla-roms](https://github.com/CESR-lab/ucla-roms) with a 24x24, 10km resolution domain of the Welsh coast.
BGC is handled by either [BEC]( https://doi.org/10.1029/2004GB002220) or [MARBL](https://doi.org/10.1029/2021MS002647) with BGC initial and boundary conditions taken from an existing run of CESM.


![Comparison animation showing surface oxygen in MARBL and BEC](wales.gif)

## Installation
It is recommended that you use [C-Star](https://github.com/dafyddstephenson/C-Star/tree/add_setup_scripts) 
to run this configuration. 
C-Star will automatically obtain and compile the external codebases of ROMS and MARBL. See the C-Star README for instructions on setting up C-Star.

With the first time C-Star setup complete, use the command `cstar_get_config roms_marbl_example`  to obtain and compile this configuration.

If you want to modify the code and recompile at any time, go into the code directory (`${CSTAR_ROOT}/configurations/roms_marbl_example/code`) and run `make`.

Compile time notes:
- The number of CPUs is set at compile time (see below, default number is 9).
- By default, ROMS will compile with BGC being handled by MARBL.
- To switch to BEC, comment (prepend a `!` to) `#define MARBL` in `code/cppdefs.opt`, uncomment `#define BIOLOGY_BEC2`, run `make` again.
   To run without BGC, comment both cpp keys.

## Running
All of the initial and boundary condition files to run for the year of 2012 are provided in `INPUT` for both BEC and MARBL. 
To run the model from the shell, simply run the script `fromrestart_run.sh`, which will determine whether the MARBL cpp key is active and choose the necessary input files and namelists accordingly.

If you are on a system with a job scheduler you will need to modify `fromrestart_run.sh` to include any scheduler commands.

The model will restart on the 3rd of January 2012 (restart files are included for MARBL and BEC, but both runs previously started from identical initial conditions)
The input files are split (one per processor) using the `partit` tool in `$ROMS_ROOT/Tools-Roms` which should be on your path after being added by the `.ROMS` file in Step 3, then the model is run.
The output files are similarly joined using the `ncjoin` tool.

## Running with modified settings
The layout of processors is set (`NP_XI`,`NP_ETA`) in `code/param.opt` should you wish to change from the default (3,3), but the model will need to be recompiled, and the `.sh` files will need to be updated before running.
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
