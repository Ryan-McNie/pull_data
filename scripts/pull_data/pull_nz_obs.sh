#!/bin/bash
year=$1
DOY=$2
PrevYEAR=$3
PrevDOY=$4
station=$5
localDir=$6

station=$(echo "$station" | tr '[:upper:]' '[:lower:]')
yy="${year: -2}"

# Call python script with error handling
python3 "../../../scripts/pull_data/gnss_archive.py" -1 "$PrevYEAR:$PrevDOY" "$station"
exit_code=$?

if [ "$exit_code" -eq 3 ]; then
    echo "No data found in NZ archive"
    exit 3
fi

# Delete all previous day files that are not from the last 15 mins
for file in ${localDir}/*; do
    filename=$(basename "$file")
    suffix="${filename: -6}"  # Gets the suffix (e.g., 'crx.gz' or '25d.gz')

    if [[ "$suffix" == "crx.gz" ]]; then
        fileyear="${filename:12:4}"
        filedoy="${filename:16:3}"
        hhmm="${filename:19:4}"
        filestation="${filename:0:4}"
        if [[ "$fileyear$filedoy" == "$PrevYEAR$PrevDOY" && "$hhmm" != "2345" && " ${station} " == *" $filestation "* ]]; then
            rm "$file"
            continue
        fi

    elif [[ "$suffix" == "${yy}d.gz" ]]; then
        base="${filename%.*}"
        filehmm="${base: -7:-4}"
        filestation="${filename:0:4}"
        filestation="${filestation,,}"
        if [[ "$filehmm" != "x45" && "$filestation" == "$station" ]]; then
            rm "$file"
            continue
        fi
    fi
done

(
cd $localDir
python3 "../../../scripts/pull_data/gnss_archive.py" -1 "$year:$DOY" "$station"
)

echo
total=$(ls -1 ${localDir}/*.gz 2>/dev/null | wc -l)
count=0

for file in *.gz; do
    gzip -d -f "$file"
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rExtracting .gz files: [%-100s] %d%%" "$bar" "$percent"
done
echo

total=$(ls -1 ${localDir}/*d ${localDir}/*.crx 2>/dev/null | wc -l)
count=0

for file in ${localDir}/*d ${localDir}/*.crx; do
    ./tools/CRX2RNX -d -f "$file" 2>/dev/null
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rExtracting CRINEX files: [%-100s] %d%%" "$bar" "$percent"
done
echo


# Loop through all files in the directory to capitalise
for file in ${localDir}/*.rnx ${localDir}/*o; do
    # Check if it's a file (not a directory)
    if [ -f "$file" ]; then
        # Get the uppercase version of the filename
        uppercase_file=$(echo "$file" | tr '[:lower:]' '[:upper:]')
        # Rename the file
        mv "$file" "$uppercase_file"
    fi
done
