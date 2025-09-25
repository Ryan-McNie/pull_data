#!/bin/bash
year=$1
DOY=$2
PrevYEAR=$3
PrevDOY=$4
station=$5
localDir=$6

# Normalize station name
station=$(echo "$station" | tr '[:upper:]' '[:lower:]')

# Determine receiver type
if [[ "$station" == *_sept ]]; then
    receiver="sept"
    station="KLTG"
elif [[ "$station" == *_nov ]]; then
    receiver="nov"
    station="KLTG"
else
    read -p "Which receiver type for $station? (sept/nov): " receiver
    receiver=$(echo "$receiver" | tr '[:upper:]' '[:lower:]')
    station="KLTG"
fi

# Validate input
if [[ "$receiver" == "sept" ]]; then
    s3_path="s3://southpan-gnss-observables/LINZ_Septentrio/RINEX/y${year}/d${DOY}/"
    prev_s3_path="s3://southpan-gnss-observables/LINZ_Septentrio/RINEX/y${PrevYEAR}/d${PrevDOY}/"
elif [[ "$receiver" == "nov" ]]; then
    s3_path="s3://southpan-gnss-observables/LINZ_Novatel/RINEX/y${year}/d${DOY}/"
    prev_s3_path="s3://southpan-gnss-observables/LINZ_Novatel/RINEX/y${PrevYEAR}/d${PrevDOY}/"
else
    echo " Invalid receiver type. Please use 'sept' or 'nov'."
    exit 1
fi

cd "$localDir"

# Get list of files to download
prev_files=$(aws s3 ls "$prev_s3_path" | awk '{print $4}' | grep -E '$|2300_01H_01S_MO\.zip$|2300_01H_01S_MO\.rnx$')
curr_files=$(aws s3 ls "$s3_path" | awk '{print $4}' | grep -E '\.zip$|\.rnx$')

# Combine both lists
all_files=($prev_files $curr_files)
total=${#all_files[@]}
count=0

# Download with unified progress bar
for file in "${all_files[@]}"; do
  if [[ "$prev_files" == *"$file"* ]]; then
    aws s3 cp "${prev_s3_path}${file}" . --quiet
  else
    aws s3 cp "${s3_path}${file}" . --quiet
  fi
  ((count++))
  percent=$((count * 100 / total))
  bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
  printf "\rDownloading files: [%-100s] %d%%" "$bar" "$percent"
done


# Loop through all files in the directory to capitalise
for file in *.rnx; do
    # Check if it's a file (not a directory)
    if [ -f "$file" ]; then
        # Get the uppercase version of the filename
        uppercase_file=$(echo "$file" | tr '[:lower:]' '[:upper:]')
        # Rename the file
        mv "$file" "$uppercase_file"
    fi
done
