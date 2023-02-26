#!/bin/bash
#
# The data download process will be done on the local Desktop
#
cd /home/goitomk/HU_WRF/_mars
#
#
for YYYY in 2022; do   # e.g for the selected years 
for MM in {10..12..1}; do        # months of the season       
for DD in {25..31..1}; do        # days of the months 
#
Z_dt=${YYYY}${MM}${DD}
export mardir=${WRF}/MARS_DATA   # Daily MARS data directory
# When the directory are not aviliable, they will be created as below.
[ ! -d "$mardir" ] && mkdir -p $mardir
#
mars MARS_PL_00.req
mars MARS_SFC_00.req
#mars MARS_Test_00.req
#
mkdir $mardir/${Z_dt}
#
grib_copy _PL_${DATE}_\[DATE\]_\[TIME\]_israel.grb ECMWF_IFS_pl_[validityDate][validityTime].grib
#
mv ECMWF_* ${mardir}/${Z_dt}
#
done 
done 
done 
# 




