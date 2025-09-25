#!/usr/bin/env python3

import sys
import subprocess
import os
import pandas as pd
from datetime import datetime, timedelta
from pathlib import Path


def doy_to_date(year: int, doy: int) -> str:
    """Convert year and day-of-year to YYYY-MM-DD."""
    date_obj = datetime(year, 1, 1) + timedelta(days=doy - 1)
    return date_obj.strftime("%Y-%m-%d")

def run_check(script_path: str, file_path: str, date_str: str) -> int:
    """Run the Python check script and return the number of epochs, even if the script fails."""
    result = subprocess.run(
        ["python3", script_path, file_path, date_str],
        capture_output=True,
        text=True
    )
    output = result.stdout.strip()

    try:
        return int(output)
    except ValueError:
        print(f"Invalid output: {output}", file=sys.stderr)
        return -1

def process_day(doy, year):

    date_str = doy_to_date(year, doy)

    # Pull data
    subprocess.run(["./pull_sbas-doy.sh", f"{year}{doy:03}"], check=True)

    sis_file = f"./output/{year}/{doy:03}/L1_SIS_{year}{doy:03}.ems"
    int_file = f"./output/{year}/{doy:03}/L1_INT_{year}{doy:03}.ems"
    check_script = "./scripts/check_data/check_ems-doy.py"

    if Path(sis_file).exists():
        sis_epochs = run_check(check_script, sis_file, date_str)
        if sis_epochs == 0:
            sis_epochs = 87000
        if sis_epochs == 1:
            sis_epochs = 0
        os.remove(sis_file)
    else:
        print(f"{sis_file} does not exist")
        sis_epochs = 0


    if Path(int_file).exists():
        int_epochs = run_check(check_script, int_file, date_str)
        if int_epochs == 0:
            int_epochs = 87000
        if int_epochs == 1:
            int_epochs = 0
        os.remove(int_file)
    else:
        print(f"{int_file} does not exist")
        int_epochs = 0


    print(f"INT epochs: {int_epochs}")
    print(f"SIS epochs: {sis_epochs}")
    return int_epochs, sis_epochs


if __name__ == "__main__":
    results=[]
    year = 2024

    for doy in range(1, 20):
        int_epochs, sis_epochs = process_day(doy, year)
        results.append({
            "year": year,
            "doy": doy,
            "int_epochs": int_epochs,
            "sis_epochs": sis_epochs
        })

    df = pd.DataFrame(results)
    print(df.head())
