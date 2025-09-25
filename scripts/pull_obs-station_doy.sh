#!/bin/bash

#-------------------------------- Check and clean inputs --------------------------------

# Display usage instructions
usage() {
    echo "Usage: $0 <SITE> input_date "
    echo "Input date should be in format yyyymmdd, yymmdd, yyyyDOY or DOY"
    exit 1
}

# Validate input date format and calculate DOY
calculate_doy() {
    local input_date=$1
    local year month day DOY

    if [[ $input_date =~ ^[0-9]{8}$ ]]; then
        # YYYYMMDD format
        year=${input_date:0:4}
        month=${input_date:4:2}
        day=${input_date:6:2}
        DOY=$(date -d "$year-$month-$day" +%j)
    elif [[ $input_date =~ ^[0-9]{7}$ ]]; then
        # YYYYDOY format (e.g. 2025103 meaning year 2025, day 103)
        year=${input_date:0:4}
        DOY=${input_date:4:3}
    elif [[ $input_date =~ ^[0-9]{6}$ ]]; then
        # YYMMDD format, convert to YYYYMMDD by adding century (modify if needed)
        input_date=$((input_date + 20000000))
        year=${input_date:0:4}
        month=${input_date:4:2}
        day=${input_date:6:2}
        DOY=$(date -d "$year-$month-$day" +%j)
    elif [[ $input_date =~ ^[0-9]{3}$ ]]; then
        # DOY only, use current year
        DOY=$input_date
        year=$(date +%Y)
    else
        echo "Error: Invalid input date format"
        exit 1
    fi

    # Output the results so they can be captured by the calling code
    echo "$year $DOY"
}

# Validate input arguments
if [ -z "$2" ]; then
    echo "Error: Not enough inputs"
    usage
fi

read -r year DOY <<< "$(calculate_doy "$2")"
station_name=$1
station_name="${station_name^^}"

# Basic validation for the year (should be a 4-digit number)
if ! [[ $year =~ ^[0-9]{4}$ ]]; then
    echo "Error: Computed year ($year) is invalid."
    exit 1
fi

# Convert DOY to an integer to allow arithmetic checks (forcing base 10)
DOY_INT=$((10#$DOY))

# Determine the maximum day of the year (leap year check)
if (( (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0) )); then
    max_day=366
else
    max_day=365
fi

if [ "$DOY_INT" -gt "$max_day" ]; then
    echo "Error: DOY ($DOY) exceeds the number of days ($max_day) in year $year."
    exit 1
fi

# Calculate the previous DOY
DOY_NUM=$((10#$DOY))
PrevDOY=$((DOY_NUM - 1))
PrevYEAR=$year
if [ $PrevDOY -eq 0 ]; then
    PrevYEAR=$((year - 1))
    PrevDOY=$(date -d "$PrevYEAR-12-31" +%j)
fi
PrevDOY=$(printf "%03d" $PrevDOY)

# Define output directory
localDir="$(pwd)/../output/$year/$DOY"
mkdir -p "$localDir"

echo "Pulling $station_name for $DOY:$year"
if [[ "$station_name" == KLTG* ]]; then
    ./pull_data/pull_kltg_obs.sh "$year" "$DOY" "$PrevYEAR" "$PrevDOY" "$station_name" "$localDir"
    ./manipulate_data/combine_rinex.sh "$year" "$DOY" "$PrevYEAR" "$PrevDOY" "KLTG" "$localDir"

else
    echo "Attempting to pull from NZ archive"
    ./pull_data/pull_nz_obs.sh "$year" "$DOY" "$PrevYEAR" "$PrevDOY" "$station_name" "$localDir"
    exit_code=$?
    if [ "$exit_code" -eq 3 ]; then
        echo "Attempting to pull from AUS archive"
        ./pull_data/pull_aus_obs.sh "$year" "$DOY" "$PrevYEAR" "$PrevDOY" "$station_name" "$localDir"
    fi
    ./manipulate_data/combine_rinex.sh "$year" "$DOY" "$PrevYEAR" "$PrevDOY" "$station_name" "$localDir"

fi



