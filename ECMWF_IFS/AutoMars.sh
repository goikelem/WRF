#!/bin/bash
#
# The data download process will be done on the local Desktop
#
cd /home/eranlab/HU_WRF/
#
mars MARS_PL_00.req
mars MARS_SFC_00.req
#mars MARS_Test_00.req
#
#  line 12, 13 and 14 are external to install the ecmwf eccodes grib_api
# wget https://repo.anaconda.com/archive/Anaconda3-2020.07-Linux-x86_64.sh
# bash Anaconda3-2020.07-Linux-x86_64.sh
# conda create -n gwrf -c conda-forge python=3.8 eccodes 
source /home/eranlab/anaconda3/etc/profile.d/conda.sh
conda activate gwrf
#
grib_copy _PL_${DATE}_\[DATE\]_\[TIME\]_israel.grb ECMWF_IFS_pl_[validityDate][validityTime].grib
grib_copy _SFC_${DATE}_\[DATE\]_\[TIME\]_israel.grb ECMWF_IFS_SFC_[validityDate][validityTime].grib
#

# 




