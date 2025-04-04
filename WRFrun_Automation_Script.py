#!/usr/bin/env python3
"""
WRF Automation Script (Python Version)
Author: [Your Name]
Date: [Date]
"""
import os
import sys
import logging
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
import shutil
import tarfile

class WRFConfig:
    """Configuration settings for WRF automation"""
    def __init__(self):
        # Base directories
        self.wrf_base = Path(os.environ.get("WRF", "/path/to/wrf_root"))
        self.wps_dir = self.wrf_base / "WPS-4.4"
        self.wrf_run_dir = self.wrf_base / "WRFV4.4" / "run"
        
        # Processing parameters
        self.flh = 12                     # Forecast length in hours
        self.num_processors = 10          # MPI processes
        self.process_date = None          # Set during initialization
        self.cycle = "00"                 # Initialization cycle
        
        # Derived paths
        self.output_base = self.wrf_base / "wrf_output"
        self.grib_data = self.wrf_base / "ECMWF_DATA"
        self.log_dir = self.wrf_base / "_history"
        
        # Initialize paths
        self._create_directories()
        self._init_logging()
        
    def _create_directories(self):
        """Create required directory structure"""
        self.output_base.mkdir(parents=True, exist_ok=True)
        (self.output_base / "geogrid").mkdir(exist_ok=True)
        (self.output_base / "ungrib").mkdir(exist_ok=True)
        (self.output_base / "metgrid").mkdir(exist_ok=True)
        (self.output_base / "wrf").mkdir(exist_ok=True)
        self.log_dir.mkdir(exist_ok=True)

    def _init_logging(self):
        """Initialize logging configuration"""
        log_file = self.log_dir / f"WRF_Processing_{datetime.now().strftime('%Y%m%d%H%M')}.log"
        logging.basicConfig(
            level=logging.INFO,
            format="%(asctime)s [%(levelname)s] %(message)s",
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger("WRF-Automation")

    def set_processing_date(self, date_str=None):
        """Set and validate processing date"""
        if date_str:
            try:
                self.process_date = datetime.strptime(date_str, "%Y%m%d")
            except ValueError:
                self.logger.error("Invalid date format. Use YYYYMMDD")
                sys.exit(1)
        else:
            self.process_date = datetime.now()
        
        self.start_time = self.process_date.replace(hour=int(self.cycle))
        self.end_time = self.start_time + timedelta(hours=self.flh)

def run_command(cmd, cwd=None, success_msg=None, error_msg=None):
    """Execute system command with error handling"""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )
        if success_msg:
            config.logger.info(success_msg)
        return True
    except subprocess.CalledProcessError as e:
        config.logger.error(f"{error_msg}\nCommand: {e.cmd}\nError: {e.output}")
        sys.exit(1)

def wps_processing(config):
    """Handle WPS processing steps"""
    config.logger.info("Starting WPS Processing")
    
    # Clean WPS directory
    for f in config.wps_dir.glob("GRIBFILE.*"):
        f.unlink()
    
    # Update namelist.wps
    namelist = config.wps_dir / "namelist.wps"
    content = namelist.read_text()
    content = content.replace(
        "start_date =", 
        f"start_date = '{config.start_time.strftime('%Y-%m-%d_%H:%M:%S')}',"
    )
    content = content.replace(
        "end_date =", 
        f"end_date = '{config.end_time.strftime('%Y-%m-%d_%H:%M:%S')}',"
    )
    namelist.write_text(content)
    
    # Run geogrid
    if not (config.output_base / "geogrid" / "geo_em.d01.nc").exists():
        run_command(
            ["./geogrid.exe"],
            cwd=config.wps_dir,
            success_msg="Geogrid completed successfully",
            error_msg="Geogrid failed"
        )
        shutil.copy2(config.wps_dir / "geo_em.d01.nc", config.output_base / "geogrid")

    # Link and process GRIB data
    grib_source = config.grib_data / f"{config.start_time.strftime('%Y%m%d%H')}"
    if not grib_source.exists():
        config.logger.error(f"GRIB data not found: {grib_source}")
        sys.exit(1)
        
    # Link GRIB files
    run_command(
        ["./link_grib.csh", str(grib_source / "*")],
        cwd=config.wps_dir,
        success_msg="GRIB files linked",
        error_msg="Failed to link GRIB files"
    )
    
    # Run ungrib and metgrid
    for step in ["ungrib", "metgrid"]:
        run_command(
            [f"./{step}.exe"],
            cwd=config.wps_dir,
            success_msg=f"{step.capitalize()} completed",
            error_msg=f"{step.capitalize()} failed"
        )
    
    # Move metgrid files
    metgrid_output = config.output_base / "metgrid" / f"{config.start_time.strftime('%Y%m%d%H')}"
    metgrid_output.mkdir(parents=True, exist_ok=True)
    for f in config.wps_dir.glob("met_em*"):
        shutil.move(str(f), str(metgrid_output))

def wrf_processing(config):
    """Handle WRF processing steps"""
    config.logger.info("Starting WRF Processing")
    
    # Clean WRF run directory
    for pattern in ["met_em.d*", "rsl.*", "wrfout*"]:
        for f in config.wrf_run_dir.glob(pattern):
            f.unlink()
    
    # Link metgrid files
    metgrid_files = list((config.output_base / "metgrid" / f"{config.start_time.strftime('%Y%m%d%H')}").glob("met_em*"))
    if not metgrid_files:
        config.logger.error("No metgrid files found")
        sys.exit(1)
        
    for f in metgrid_files:
        (config.wrf_run_dir / f.name).symlink_to(f)
    
    # Update namelist.input
    namelist = config.wrf_run_dir / "namelist.input"
    content = namelist.read_text()
    replacements = {
        "run_hours": f"run_hours = {config.flh},",
        "start_year": f"start_year = {config.start_time.year},",
        "start_month": f"start_month = {config.start_time.month},",
        "start_day": f"start_day = {config.start_time.day},",
        "start_hour": f"start_hour = {config.start_time.hour},"
    }
    for key, value in replacements.items():
        content = re.sub(f"{key}.*", value, content)
    namelist.write_text(content)
    
    # Run real.exe
    run_command(
        ["mpirun", "-np", str(config.num_processors), "./real.exe"],
        cwd=config.wrf_run_dir,
        success_msg="real.exe completed",
        error_msg="real.exe failed"
    )
    
    # Run wrf.exe
    run_command(
        ["mpirun", "-np", str(config.num_processors), "./wrf.exe"],
        cwd=config.wrf_run_dir,
        success_msg="wrf.exe completed",
        error_msg="wrf.exe failed"
    )
    
    # Archive output
    output_dir = config.output_base / "wrf" / f"{config.start_time.strftime('%Y%m%d%H')}"
    output_dir.mkdir(parents=True, exist_ok=True)
    for f in config.wrf_run_dir.glob("wrfout*"):
        shutil.move(str(f), str(output_dir))
    
    # Create tarball
    with tarfile.open(f"{output_dir}.tar.gz", "w:gz") as tar:
        tar.add(output_dir, arcname=output_dir.name)
    
    config.logger.info(f"Output archived to {output_dir}.tar.gz")

if __name__ == "__main__":
    config = WRFConfig()
    
    try:
        # Handle command line arguments
        date_arg = sys.argv[1] if len(sys.argv) > 1 else None
        config.set_processing_date(date_arg)
        
        config.logger.info(f"WRF Automation Started for {config.start_time}")
        
        # Run processing steps
        wps_processing(config)
        wrf_processing(config)
        
        config.logger.info("WRF Processing Completed Successfully")
        
    except Exception as e:
        config.logger.error(f"Critical Error: {str(e)}", exc_info=True)
        sys.exit(1)
