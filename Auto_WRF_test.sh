#!/bin/bash
# --------------------------------------------#
cd $WRF
# 
dt=`date +%Y-%m-%d-%H-%M`
[ ! -d "${WRF}/_history" ] && mkdir -p _history
touch ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt  
# 
echo "Model run start time at `date` :$dt" >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt
# Get current date from the system and set cycle to 00
#
#for YYYY in 2020 2021 2022; do   # e.g for the selected years 
#for MM in {06..12..1}; do        # months of the season       
#for DD in {01..31..1}; do        # days of the months 
export YYYY=2022
export MM=03 
export DD=24
#--------------------------------
Y_r=${YYYY}${MM}${DD} 
inDate=${Y_r}   # Date should be in YYYYDDMM mormat
export cc=00           # Cycle should be 00 or 06 or 12 or 18
export flh=12          # Forecast lenfth in hours. Should be <= 120hr,
# however since we have five days from 00 day one to 23 fouth day at 3hr interval
export cDate=${inDate}${cc} # Ex. cDate = 2022122300
export gribdir=${WRF}/wrf_output/ungrib/${cDate} # ungrib data directory
export metdir=${WRF}/wrf_output/metgrid/${cDate} # metgrid data directory
export wrfdir=${WRF}/wrf_output/wrf/${cDate}     # WRF output data directory
export pltdir=${WRF}/wrf_output/wrf/plots        # plots
# If folders to hold ungrib, metgrib and wrf output files do not exist, they will be created.
[ ! -d "${WRF}/$gribdir" ] && mkdir -p $gribdir
[ ! -d "${WRF}/$metdir" ] && mkdir -p $metdir
[ ! -d "${WRF}/$wrfdir" ] && mkdir -p $wrfdir  
[ ! -d "${WRF}/$pltdir" ] && mkdir -p $pltdir 
# 
# 
# WPS pre-processing section of the WRF model run starts here.
#=============================================================
#
rm -rf ${WRF}/wrf_output/geogrid/*
rm -rf ${WRF}/wrf_output/ungrib/*
rm -rf ${WRF}/wrf_output/metgrid/*
rm -rf ${WRF}/WPS-4.4/GRIBFILE.*
echo "\n::WPS Pre-Processing Started" 
echo "  =========================="
echo "Entering WPS folder: ${WRF}/WPS-4.4\n at `date`" >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt 
cd ${WRF}/WPS-4.4
#               Edit namelist.wps
#               =================
# Make edits to namelist.wps to change the forecast start and end dates
# The following line of codes modifies the namelist.wps start date and end
# dates based on the date of model run. Note that the namelists should be 
# modified with care. If text editors are used to modify them, make sure
# they are in order.
# For real time forecast
# export tSeconds = "`date --date='$inDate' -u +%s`"
# @ fls = $flh * 3600   # forecast length in seconds (fls)
# @ endDate = $tSeconds + $fls
# Define forecast starting and ending date which will modify the date in the namelists.
export Xhr=0  # Five days lead time forecast 
export endDate=$(($inDate+$Xhr))      #Z----------=$(($X+$Y)), add the five days lead time forecast.  
export sYear=`echo ${inDate} | awk '{print substr($inDate,1,4)}'`
export sMonth=`echo ${inDate} | awk '{print substr($inDate,5,2)}'`
export sDay=`echo ${inDate} | awk '{print substr($inDate,7,2)}'`
# 
export eYear=`echo ${endDate} | awk '{print substr($endDate,1,4)}'`
export eMonth=`echo ${endDate} | awk '{print substr($endDate,5,2)}'`
export eDay=`echo ${endDate} | awk '{print substr($endDate,7,2)}'`
export eHour=${flh}
#
# Set variables to update start and end date in namelist.wps
#
export sDate="${sYear}-${sMonth}-${sDay}_00:00:00"
export eDate="${eYear}-${eMonth}-${eDay}_${eHour}:00:00"
export start_date=" start_date = '$sDate','$sDate','$sDate'"
export end_date=" end_date = '$eDate','$eDate','$eDate'"
export ARW_sDate=" start_date = '$sDate',"
export ARW_eDate=" end_date = '$eDate',"
#
# Update start and end dates in namelist.wps
#
sed -i "4s/.*/$start_date/" namelist.wps
sed -i "5s/.*/$end_date/" namelist.wps
# I like grads for plotting even the WRF python is latest 
sed -i "2s/.*/$ARW_sDate/" $WRF/ARWpost/namelist.ARWpost
sed -i "3s/.*/$ARW_eDate/" $WRF/ARWpost/namelist.ARWpost
echo "::namlist.wps is updated at `date`" >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt
#
#               Run geogrid
#               ===========
#
# Geogrid should be run only once after setting the spatial domain.
# If any changes are made to the domain, uncoment the line below and 
# then comment it to avoid rerunning again.
#
./geogrid.exe >& log.geogrid
echo "::geogrid program run completed at `date`"  >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt

echo "Using ECMWF_IFS data from  -  ${WRF}/ECMWF_DATA/${cDate}/"
#
# Link ECMWF_IFS input data into WPS folder
if [ -d "${WRF}/ECMWF_DATA/${cDate}" ]; then
./link_grib.csh ${WRF}/ECMWF_DATA/${cDate}/*  
fi
#
echo "::Input grib files are linked into WPS directory at `date`" >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt

# The line below should be uncommented if input data type is other
# than ECMWF_IFS data and it is required to be done once.
#
ln -sf ungrib/Variable_Tables/Vtable.ECMWF Vtable
#               Run ungrib
#               ==========
# ungrib.exe prepares/unpacks the required fields from grib input data
# and writes them out into a format that the METGRID program can read.
#
ls -lrt 
./ungrib.exe >& log.ungrib
echo "::ungrib program run completed at `date`"   >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt

#               Run metgrid
#               ===========
# metgrid.exe interpolates the input data on the model domain based on
# the fields provided by the METGRID.TBL file.
#
./metgrid.exe >& log.metgrid
echo "::metgrid program run completed `date` " >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt

# The ungribbed data and the metgrid files are place in the folders
# defined in the namelist.wps. The following lines will move them to
# the sub-folders created based on the run date.
#
mv ${WRF}/wrf_output/ungrib/IFS* ${WRF}/wrf_output/ungrib/$cDate
mv ${WRF}/wrf_output/metgrid/met_e* ${WRF}/wrf_output/metgrid/$cDate

echo "\n::Finished WPS processes at `date`!" >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt
echo "  =======================\n"

# WRF model run starts here.
#===========================
#
echo "::WRF Model Run Started"
echo "  =====================\n"

# To run the WRF model, change directory to WRF run sub-directory
#
echo "Entering WRF run folder: ${WRF}/WRFV4.4/run at `date` " >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt
cd $WRF/WRFV4.4/run
#               Edit namelist.input
#               ===================
# Make edits to namelist.input to change the forecast start and end dates
# The following line of codes modifies the namelist.input start date and end
# dates based on the date of model run. Note that the namelists should be 
# modified with care. If text editors are used to modify them, make sure
# they are in order.
#
# Set variables to update start and end dates in namelist.input
#
export run_hours=" run_hours     = $flh,"
export start_year=" start_year   = $sYear,   $sYear,    $sYear,"
export start_month=" start_month = $sMonth,  $sMonth,   $sMonth,"
export start_day=" start_day     = $sDay,    $sDay,     $sDay,"
export end_year=" end_year       = $sYear,   $sYear,    $sYear,"
export end_month=" end_month     = $eMonth,  $eMonth,   $eMonth,"
export end_day=" end_day         = $eDay,    $eDay,     $eDay,"
export end_hour=" end_hour       = $eHour,   $eHour,    $eHour,"

# Update start and end dates in namelist.input
#
sed -i "3s/.*/$run_hours/"   $WRF/WRFV4.4/run/namelist.input
sed -i "6s/.*/$start_year/"  $WRF/WRFV4.4/run/namelist.input
sed -i "7s/.*/$start_month/" $WRF/WRFV4.4/run/namelist.input
sed -i "8s/.*/$start_day/"   $WRF/WRFV4.4/run/namelist.input
sed -i "12s/.*/$end_year/"   $WRF/WRFV4.4/run/namelist.input
sed -i "13s/.*/$end_month/"  $WRF/WRFV4.4/run/namelist.input
sed -i "14s/.*/$end_day/"    $WRF/WRFV4.4/run/namelist.input
sed -i "15s/.*/$end_hour/"   $WRF/WRFV4.4/run/namelist.input
#
echo "::namlist.input is updated at `date` " >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt
rm met_em.d0* rsl.* wrfout_d0* wrfbdy_d0* wrfinput_d0*
#
#              Run real data initialization program
#              ====================================
# Link metgrid output data into WRF run folder
#
ln -sf ${WRF}/wrf_output/metgrid/$cDate/met_em* .
echo "::metgrid data linked into WRF run folder\n `date`" >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt

# The command for running the real program may vary depending on your system  
# and the number of processors you have available. Considering the workstation 
# at Erick with 2 Sockets, 28 total processors and 14 cores per socket, you may choose to issue the command as below.
#
status=$?
if [ $status == 0 ]; then
   mpirun -np 10 ./real.exe
fi
#
#
echo "::Real data initializaiton run completed\n `date` " >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt
#
# Run the WRF model using most of processor cores 
#
echo "\n::WRF Model Run Started" >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt
if [ $status == 0 ]; then
   mpirun -np 10 ./wrf.exe
fi
#
echo "\n::WRF Model Run Completed"
echo "  =======================\n"
echo "Model run end time : `date` " >> ${WRF}/_history/WRF_Processing_Date_${dt}_time_info.txt
# move the wrf output into in to Archive 
mv wrfout_* ${wrfdir}   
# Copy parent domain output to plot folder for plotting in GrADS and Archive 
#
tar -czvf ${wrfdir}-2archive.tar.gz ${wrfdir}
# We need the domain for Israel only to save it on the archive 
# Enabling RSA key-based authentication #TODO  132.64.249.xxx the local Desktop   
#scp ${wrfdir}-2archive.tar.gz goitomk@132.64.249.xxx:"D:\Archive\WRF_DATA"
#

