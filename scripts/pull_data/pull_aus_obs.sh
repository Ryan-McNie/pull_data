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
 echo "set xfer:clobber yes"
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

count=0
lftp -f "$tmpfile" 2>&1 | while read -r line; do
  ((count++))
  echo -ne "\rDownloading file #$count: ${line:0:80}"
done
echo

echo
total=$(ls -1 ${TMPDIR}/*.gz 2>/dev/null | wc -l)
count=0



for file in ${TMPDIR}/*.gz; do
    gzip -d -f "$file"
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rExtracting .gz files: [%-100s] %d%%" "$bar" "$percent"
done
echo

total=$(ls -1 ${TMPDIR}/*.crx 2>/dev/null | wc -l)
count=0

for file in ${TMPDIR}/*.crx; do
    ./tools/crx2rnx -d -f "$file"
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rConverting .crx files: [%-100s] %d%%" "$bar" "$percent"
done

