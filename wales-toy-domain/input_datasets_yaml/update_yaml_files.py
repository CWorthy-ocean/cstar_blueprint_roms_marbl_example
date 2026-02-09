import roms_tools as rt
from pathlib import Path

update_netcdf = True

dataset_dir = Path("roms_tools_datasets")

Path("updated").mkdir(parents=True,exist_ok=True)

## Grid
print("grid")
roms_grd = rt.Grid.from_yaml("roms_grd.yaml")
roms_grd.to_yaml("updated/roms_grd.yaml")

## Tides
print("tides")
roms_tides = rt.TidalForcing.from_yaml("roms_tides.yaml",use_dask=True)
roms_tides.to_yaml("updated/roms_tides.yaml")

## Initial Conditions
print("IC")
roms_ini = rt.InitialConditions.from_yaml("roms_ini.yaml",use_dask=True)
roms_ini.to_yaml("updated/roms_ini.yaml")

## Surface Forcing
print("surface")
roms_frc = rt.SurfaceForcing.from_yaml("roms_frc.yaml",use_dask=True)
roms_frc.to_yaml("updated/roms_frc.yaml")

## BGC Surface Forcing
print("BGC forcing")
roms_frc_bgc = rt.SurfaceForcing.from_yaml("roms_frc_bgc.yaml",use_dask=True)
roms_frc_bgc.to_yaml("updated/roms_frc_bgc.yaml")

## Boundary Forcing
print("boundary")
roms_bry = rt.BoundaryForcing.from_yaml("roms_bry.yaml",use_dask=True)
roms_bry.to_yaml("updated/roms_bry.yaml")

## BGC Boundary Forcing
print("BGC boundary")
roms_bry_bgc = rt.BoundaryForcing.from_yaml("roms_bry_bgc.yaml",use_dask=True)
roms_bry_bgc.to_yaml("updated/roms_bry_bgc.yaml")

## River Forcing
print("River")
roms_riv_frc = rt.RiverForcing.from_yaml("roms_riv_frc.yaml")
roms_riv_frc.to_yaml("updated/roms_riv_frc.yaml")

## Update netcdf

netcdf_dir = Path("../input_datasets/ROMS/updated")
netcdf_dir.mkdir(parents=True, exist_ok=True)

if update_netcdf:
    roms_grd.save(netcdf_dir/"roms_grd")
    roms_tides.save(netcdf_dir/"roms_tides")
    roms_ini.save(netcdf_dir/"roms_ini")
    roms_frc.save(netcdf_dir/"roms_frc",group=False)
    roms_frc_bgc.save(netcdf_dir/"roms_frc_bgc",group=False)
    roms_bry.save(netcdf_dir/"roms_bry",group=False)
    roms_bry_bgc.save(netcdf_dir/"roms_bry_bgc",group=False)
    roms_riv_frc.save(netcdf_dir/"roms_riv_frc")
