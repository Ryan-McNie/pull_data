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

station=$(echo "$station" | tr  '[:lower:]' '[:upper:]')
for file in "${localDir}/${station}"*; do
  # Skip if no match
  [ -e "$file" ] || continue
  # Uppercase full filename (including suffix)
  uppername="$(basename "$file")"
  uppername="${uppername^^}"

  mv -- "$file" "${localDir}/${uppername}" 2>/dev/null
done


total=$(ls -1 ${localDir}/${station}*O ${localDir}/${station}*MO.RNX 2>/dev/null | wc -l)
count=0

files=(${localDir}/${station}* )
for file in "${files[@]}"; do
    ./tools/gfzrnx -finp "$file" -fout "$file" -satsys GES -f 2>/dev/null
    ((count++))
    percent=$((count * 100 / total))
    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
    printf "\rRemoving unused constellations: [%-100s] %d%%" "$bar" "$percent"
    station_prefix=$(ls -1 "${localDir}/${station}*" | head -n 1 | cut -c1-12)
done

#files=(${localDir}/${station}*O)
#for file in "${files[@]}"; do
#    ./tools/gfzrnx -finp "$file" -fout "$file" -satsys GES -kv -f 2>/dev/null
#    ((count++))
#    percent=$((count * 100 / total))
#    bar=$(printf "%-${percent}s" "#" | tr ' ' '#')
#    printf "\rRemoving unused constellations: [%-100s] %d%%" "$bar" "$percent"
#    station_prefix="${station}${DOY}_"
#done

echo

./tools/gfzrnx -finp "${localDir}/${station}*" -fout "${localDir}/${station_prefix}${year}${DOY}0000_01D_01S_MO.RNX" -splice_direct -kv -f 2>/dev/null &

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

sed -i '/^E   /s/\([CLS]\)1X/\11C/g' "${localDir}/${station_prefix}${year}${DOY}0000_01D_01S_MO.RNX" 2>/dev/null

echo

echo "15 minute files combined into daily file."

# Delete older files
#rm -f ${localDir}/${station}*15M_01S_MO.RNX
#rm -f ${localDir}/${station}*01H_01S_MO.RNX
#rm -f ${localDir}/${station}*O

