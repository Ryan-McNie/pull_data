#!/bin/bash

shopt -s nullglob


# Get the arguments
year=$1
DOY=$2
PrevYEAR=$3
PrevDOY=$4
station=$5
localDir=$6

yy="${year: -2}"
# Change to the output directory
cd "$localDir" || exit


station=$(echo "$station" | tr  '[:lower:]' '[:upper:]')
for file in $station*; do
  mv -- "$file" "${file^^}" 2>/dev/null
done


total=$(ls -1 ${station}*O ${station}*MO.RNX 2>/dev/null | wc -l)
count=0

files=(${station}*MO.RNX )
for file in "${files[@]}"; do
    gfzrnx -finp "$file" -fout "$file" -satsys GES -f 2>/dev/null
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rRemoving unused constellations: [%-100s] %d%%" "$bar" "$percent"
    station_prefix=$(ls -1 ${station}* | head -n 1 | cut -c1-12)
done

files=(${station}*O)
for file in "${files[@]}"; do
    gfzrnx -finp "$file" -fout "$file" -satsys GES -kv -f 2>/dev/null
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rRemoving unused constellations: [%-100s] %d%%" "$bar" "$percent"
    station_prefix="${station}${DOY}_"
done
echo


gfzrnx -finp "${station}*MO.RNX" "${station}*${yy}O" -fout "${station_prefix}${year}${DOY}0000_01D_01S_MO.RNX" -splice_direct -kv -f 2>/dev/null &
#gfzrnx -finp "${station}*O" -fout "::RX3::" -splice_direct -kv -f 2>/dev/null &
pid=$!
# Spinner characters
spin='-\|/'
i=0

# Show spinner while the command is running
while kill -0 $pid 2>/dev/null; do
  i=$(( (i+1) %4 ))
  printf "\rCombining Rinex... ${spin:$i:1}"
  sleep 0.1
done

sed -i '/^E   /s/\([CLS]\)1X/\11C/g' "${station_prefix}${year}${DOY}0000_01D_01S_MO.RNX" 2>/dev/null

echo "15 minute files combined into daily file."

# Delete older files
rm -f ${station}*15M_01S_MO.RNX
rm -f ${station}*01H_01S_MO.RNX
rm -f ${station}*O

