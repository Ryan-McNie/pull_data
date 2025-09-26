#!/bin/bash
year=$1
DOY=$2
PrevYEAR=$3
PrevDOY=$4
station=$5
localDir=$6

# Set fallback environment so lftp doesn't complain about missing user
export HOME="${TMPDIR}/home"
export USER="${USER:-dockeruser}"
mkdir -p "$HOME"



TMPDIR="${localDir}/tmp"
mkdir -p "$TMPDIR"
tmpfile="$(mktemp -p "$TMPDIR" "${station}_lftp_XXXXXX.txt")"
trap 'rm -f "$tmpfile"' EXIT

# Create the lftp script
{
 echo "set sftp:auto-confirm yes"
 echo "open -u anonymous,ryan.mcnie@linz.govt.nz sftp://sftp.data.gnss.ga.gov.au"
 echo "lcd ${localDir}/tmp"
 echo "cd /rinex/highrate/$PrevYEAR/$PrevDOY/23/"
 echo "mget ${station}*45_15M_01S_MO.crx.gz"
 for hour in $(seq -w 0 23); do
  echo "cd /rinex/highrate/$year/$DOY/$hour/"
  echo "mget ${station}*"
 done
 echo "bye"
} > "$tmpfile"

# Execute and cleanup (trap handles cleanup even on error)
lftp -f "$tmpfile"

echo
total=$(ls -1 $localDir/*.gz 2>/dev/null | wc -l)
count=0



for file in *.gz; do
    gzip -d -f "$file"
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rExtracting .gz files: [%-100s] %d%%" "$bar" "$percent"
done
echo

total=$(ls -1 *.crx 2>/dev/null | wc -l)
count=0

for file in *.crx; do
    crx2rnx -d -f "$file"
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rConverting .crx files: [%-100s] %d%%" "$bar" "$percent"
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
