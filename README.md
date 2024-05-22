# roms_marbl_example
An example configuration of [ucla-roms](https://github.com/CESR-lab/ucla-roms) with a 24x24, 10km resolution domain of the Welsh coast.
BGC is handled by either [BEC]( https://doi.org/10.1029/2004GB002220) or [MARBL](https://doi.org/10.1029/2021MS002647) with BGC initial and boundary conditions taken from an existing run of CESM.


![Comparison animation showing surface dissolved organic carbon in MARBL and BEC](DOC.gif)

## Installation
It is recommended that you use [C-Star](https://github.com/dafyddstephenson/C-Star/tree/add_setup_scripts) 
to run this configuration. 
C-Star will automatically obtain and compile the external codebases of ROMS and MARBL. See the C-Star README for instructions on setting up C-Star.

With the first time C-Star setup complete, use the command `cstar_get_blueprint roms_marbl_example`  to obtain and compile this blueprint.

If you want to modify the code and recompile at any time, go into the code directory (`${CSTAR_ROOT}/blueprints/roms_marbl_example/code`) and run `make`.

Compile time notes:
- The number of CPUs is set at compile time (see below, default number is 9).
- By default, ROMS will compile with BGC being handled by MARBL.
- To switch to BEC, comment (prepend a `!` to) `#define MARBL` in `code/cppdefs.opt`, uncomment `#define BIOLOGY_BEC2`, run `make` again.
   To run without BGC, comment both cpp keys.

## Running
All of the initial and boundary condition files to run for the year of 2012 are provided in `INPUT` for both BEC and MARBL. 
To run the model from the shell, activate the C-Star environment using `cstar_env` and simply run the script `start_run.sh`. This script will use the environment variable `CSTAR_SYSTEM` (set during C-Star setup) to determine what machine you are running on and start the job. If you are on a supported HPC system, you will need to have your account key set as the environment variable `ACCOUNT_KEY`. The script will determine whether the MARBL cpp key is active and choose the necessary input files and namelists accordingly.

The model will restart on the 3rd of January 2012 (restart files are included for MARBL and BEC, but both runs previously started from identical initial conditions)
The input files are split (one per processor) using the `partit` tool in `$ROMS_ROOT/Tools-Roms` which should be on your path after being added by the `.ROMS` file in Step 3, then the model is run.
The output files are similarly joined using the `ncjoin` tool.

## Controlling output variables 
By default, The model will run for 28 days (set in `roms.in_MARBL`) and 32 MARBL tracers will be written to the output files `MARBL_bgc.??????????????.nc` every 6 hours (set using `output_period_his` in `bgc.opt`). Model state variables unrelated to biogeochemistry are written to `MARBL_his.??????????????.nc` every 6 hours, set using `output_period_his` in `ocean_vars.opt`. To choose which MARBL tracers are written to the file, edit the text file `marbl_tracer_output_list`. 

Additionally, a further 343 diagnostic variables are available in the default MARBL configuration. To run with diagnostic output, edit `code/cppdefs.opt` so the line `#MARBL_DIAGS` is uncommented (delete the `!`), and run `make` in the `code` directory, before running the model. By default, BGC diagnostic output is written to `MARBL_bgc_dia.??????????????.nc` every 6 hours (set using `output_period_his_dia` in `bgc.opt`). To choose which MARBL diagnostics are written to the file, edit the text file `marbl_diagnostic_output_list`. 

## Running with modified settings
The layout of processors is set (`NP_XI`,`NP_ETA`) in `code/param.opt` should you wish to change from the default (3,3), but the model will need to be recompiled, and the `.sh` files will need to be updated before running.
The output frequency is set in `code/ocean_vars.opt`. A recompile will be necessary to change this.
