#!/bin/bash
# WRF Automation Script (v2.0)
# Enhanced with error checking, logging, and validation

# ---------------------------
# Configuration Section
# ---------------------------
set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Base directories
export WRF_BASE="${WRF:-/path/to/wrf_root}"  # Set default if WRF env var not set
export WPS_DIR="${WRF_BASE}/WPS-4.4"
export WRF_RUN_DIR="${WRF_BASE}/WRFV4.4/run"
export LOG_DIR="${WRF_BASE}/_history"
export GRIB_DATA="${WRF_BASE}/ECMWF_DATA"

# Processing parameters
export FLH=12                  # Forecast length in hours
export NUM_PROCESSORS=10       # Number of MPI processes

# Date parameters (safer date calculation)
export PROCESS_DATE="${1:-$(date +%Y%m%d)}"  # Accept input date or use current
export CYCLE="00"              # Initialization cycle

# ---------------------------
# Initialization and Validation
# ---------------------------
# Create directory structure
mkdir -p "${LOG_DIR}" "${WRF_BASE}/wrf_output/"{geogrid,ungrib,metgrid,wrf/plots}

# Validate directories
required_dirs=("${WPS_DIR}" "${WRF_RUN_DIR}" "${GRIB_DATA}")
for dir in "${required_dirs[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "FATAL ERROR: Directory $dir not found"
        exit 1
    fi
done

# Initialize logging
export LOG_FILE="${LOG_DIR}/WRF_Processing_$(date +%Y%m%d%H%M).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------------------------
# Function Definitions
# ---------------------------
log() {
    echo "[$(date +%Y-%m-%dT%H:%M:%S)] $1"
}

validate_date() {
    if ! date -d "${PROCESS_DATE:0:4}-${PROCESS_DATE:4:2}-${PROCESS_DATE:6:2}" &>/dev/null; then
        log "ERROR: Invalid processing date: $PROCESS_DATE"
        exit 1
    fi
}

# ---------------------------
# Main Processing
# ---------------------------
log "WRF Automation Script Started"
validate_date

# Calculate time parameters using proper date arithmetic
start_time=$(date -d "${PROCESS_DATE} ${CYCLE} hours" +%s)
end_time=$((start_time + FLH * 3600))

export START_DATE=$(date -d @$start_time +%Y-%m-%d_%H:%M:%S)
export END_DATE=$(date -d @$end_time +%Y-%m-%d_%H:%M:%S)

# ---------------------------
# WPS Processing
# ---------------------------
log "Starting WPS Processing"

# Clean WPS directory
cd "$WPS_DIR"
rm -f GRIBFILE.* PFILE:* *.log

# Update namelist.wps
sed -i \
    -e "s|start_date.*|start_date = '${START_DATE}', '${START_DATE}', '${START_DATE}',|" \
    -e "s|end_date.*|end_date = '${END_DATE}', '${END_DATE}', '${END_DATE}',|" \
    namelist.wps

# Run geogrid (only needs to run once per domain)
if [[ ! -f "${WRF_BASE}/wrf_output/geogrid/geo_em.d01.nc" ]]; then
    log "Running geogrid"
    ./geogrid.exe >& geogrid.log
    [[ $? -eq 0 ]] && cp geo_em.d* "${WRF_BASE}/wrf_output/geogrid/"
fi

# Link and process GRIB data
grib_source="${GRIB_DATA}/${PROCESS_DATE}${CYCLE}"
if [[ -d "$grib_source" ]]; then
    ./link_grib.csh "${grib_source}"/*
    ln -sf ungrib/Variable_Tables/Vtable.ECMWF Vtable
    
    log "Running ungrib"
    ./ungrib.exe >& ungrib.log || {
        log "ERROR: ungrib failed. Check ungrib.log and linked GRIB files"
        exit 1
    }
    
    log "Running metgrid"
    ./metgrid.exe >& metgrid.log || {
        log "ERROR: metgrid failed. Check metgrid.log"
        exit 1
    }
    
    # Organize output
    mv ${WPS_DIR}/met_em* "${WRF_BASE}/wrf_output/metgrid/${PROCESS_DATE}${CYCLE}/"
else
    log "ERROR: GRIB data not found in $grib_source"
    exit 1
fi

# ---------------------------
# WRF Processing
# ---------------------------
log "Starting WRF Processing"
cd "$WRF_RUN_DIR"

# Clean previous run
rm -f met_em.d* rsl.* wrfout* wrfbdy* wrfinput*

# Link metgrid files
met_files=("${WRF_BASE}/wrf_output/metgrid/${PROCESS_DATE}${CYCLE}/met_em"*)
if [[ ${#met_files[@]} -eq 0 ]]; then
    log "ERROR: No metgrid files found"
    exit 1
fi
ln -sf "${met_files[@]}" .

# Update namelist.input
sed -i \
    -e "s|run_hours.*|run_hours = ${FLH},|" \
    -e "s|start_year.*|start_year = ${PROCESS_DATE:0:4},|" \
    -e "s|start_month.*|start_month = ${PROCESS_DATE:4:2},|" \
    -e "s|start_day.*|start_day = ${PROCESS_DATE:6:2},|" \
    -e "s|start_hour.*|start_hour = ${CYCLE},|" \
    namelist.input

# Run real.exe
log "Running real.exe with ${NUM_PROCESSORS} processors"
mpirun -np ${NUM_PROCESSORS} ./real.exe
if [[ $? -ne 0 ]]; then
    log "ERROR: real.exe failed. Check rsl.error.* files"
    exit 1
fi

# Run wrf.exe
log "Running wrf.exe with ${NUM_PROCESSORS} processors"
mpirun -np ${NUM_PROCESSORS} ./wrf.exe
if [[ $? -ne 0 ]]; then
    log "ERROR: wrf.exe failed. Check rsl.error.* files"
    exit 1
fi

# ---------------------------
# Post Processing
# ---------------------------
log "Processing outputs"
output_dir="${WRF_BASE}/wrf_output/wrf/${PROCESS_DATE}${CYCLE}"
mkdir -p "$output_dir"
mv wrfout* "$output_dir"

# Create archive
if [[ -d "$output_dir" ]]; then
    log "Creating archive"
    tar -czf "${output_dir}.tar.gz" -C "$(dirname "$output_dir")" "$(basename "$output_dir")"
else
    log "WARNING: No output files to archive"
fi

log "WRF Processing Completed Successfully"
exit 0
