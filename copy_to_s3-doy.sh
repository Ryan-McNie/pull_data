#!/bin/bash

#-------------------------------- Check and clean inputs --------------------------------

# Display usage instructions
usage() {
    echo "Usage: $0 doy "
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

#Take input arg and turn it into year and doy
read -r year DOY <<< "$(calculate_doy "$1")"


#Take input arg and turn it into year and doy
read -r year DOY <<< "$(calculate_doy "$1")"

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
localDir="$(pwd)/output/$year/$DOY"


# Create a tar.gz archive
echo "Zipping files in $localDir ..."
cd "$localDir"
tar --exclude="${year}_${DOY}_adhoc_files.tgz" -czf "${year}_${DOY}_adhoc_files.tgz" .

echo "Copying files to S3..."
aws s3 cp "$localDir"/"${year}_${DOY}_adhoc_files.tgz" "s3://southpan-monitor-resources/Post_Processing_Outputs/$year/$DOY/"
rm -f "${year}_${DOY}_adhoc_files.tgz"
