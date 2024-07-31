# roms_marbl_example
An example configuration of [ucla-roms](https://github.com/CESR-lab/ucla-roms) with a 24x24, 10km resolution domain of the Welsh coast.
BGC is handled by either [BEC]( https://doi.org/10.1029/2004GB002220) or [MARBL](https://doi.org/10.1029/2021MS002647) with BGC initial and boundary conditions taken from an existing run of CESM.


![Comparison animation showing surface dissolved organic carbon in MARBL and BEC](DOC.gif)

## Installation
You are viewing the `main` branch, which is designed to be accessed by the [C-Star python package](https://github.com/CWorthy-Ocean/C-Star), which is currently under development.

In the meantime, if you are interested in manually setting up the `roms_marbl_example` case, please see the [`no_cstar` branch](https://github.com/CWorthy-ocean/cstar_blueprint_roms_marbl_example/tree/no_cstar) for installation instructions.
