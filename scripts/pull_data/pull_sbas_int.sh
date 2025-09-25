#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

# ── positional args
DOY=$1   # day-of-year, e.g. 175
YEAR=$2  # e.g. 2025
PDOY=$3  # previous DOY
PYEAR=$4 # previous YEAR
DIR=$5   # local staging dir

# ── convert YEAR + DOY → YYYY-MM-DD
doy2date(){
  date -d "$1-01-01 +$((10#$2-1)) days" +%F
}

pull_ems(){
  prefix=$1
  s3root=$2
  out="${DIR}/${prefix}_${YEAR}${DOY}.ems"

  mkdir -p "$DIR"
  cd "$DIR"

  files=()

  # Try previous day's last hour first
  if aws s3 cp "${s3root}/y${PYEAR}/d${PDOY}/h23.ems" "${prefix}_${PYEAR}${PDOY}_23.ems" --quiet; then
    files+=( "${prefix}_${PYEAR}${PDOY}_23.ems" )
  fi

  # Pull all available hourly files for this DOY
  for h in $(seq -w 0 23); do
    s3path="${s3root}/y${YEAR}/d${DOY}/h${h}.ems"
    localfile="${prefix}_${YEAR}${DOY}_${h}.ems"

    if aws s3 cp "$s3path" "$localfile" --quiet; then
      files+=( "$localfile" )
    fi
  done

  # Concatenate all downloaded files
  : > "$out"
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || { continue; }
    cat "$f" >> "$out"
    rm -f "$f"
  done

  # Deduplicate based on timestamp fields (YY MM DD HH MM SS)
  awk '!seen[$2 $3 $4 $5 $6 $7]++' "$out" > "${out}.dedup"
  mv "${out}.dedup" "$out"
  
  # gap check over [prev-day 23:50 … target-day 23:59:59]
  target_date=$(doy2date "$YEAR" "$DOY")

  # only run if $out exists and its size is > 0
  if [ -s "$out" ]; then
    if python3 ../../../scripts/check_data/check_ems-doy.py "$out" "$target_date"; then
      echo "✔ $prefix OK (no gaps in window)"
      return 0
    else
      echo "✖ $prefix has gaps in window"
      return 1
    fi
  else
    echo "✖ $prefix file is empty or missing"
    return 1
  fi
}

pull_gmv_ems(){
  prefix=$1
  band=${prefix%%_*}   # “L1” or “L5”

  # set up build list
  if (( YEAR < 2024 )); then
    builds=( "" )
  else
    builds=( "Build-1_Awarua" "Build-1_Uralla" "Build-0")
  fi

  # dates
  full_date=$(doy2date "$YEAR" "$DOY")
  IFS='-' read -r _ month day <<<"$full_date"
  today_root="s3://southpan-gmv-sbas-messages/${YEAR}/${month}/${day}"

  prev_date=$(doy2date "$PYEAR" "$PDOY")
  IFS='-' read -r _ pmonth pday <<<"$prev_date"
  yesterday_root="s3://southpan-gmv-sbas-messages/${PYEAR}/${pmonth}/${pday}"

  mkdir -p "$DIR"
  cd "$DIR" || return 1

  largest_size=0
  complete_candidate=""
  largest_candidate=""

 for build in "${builds[@]}"; do
    # decide whether to append '/Build-*' or not
    if [[ -n "$build" ]]; then
      echo "→ Fetching $build from GMV Archive"
      yesterday_s3path="${yesterday_root}/${build}"
      today_s3path="${today_root}/${build}"
      suffix="_${build}"
    else
      echo "→ Fetching Build 0 from GMV Archive"
      yesterday_s3path="$yesterday_root"
      today_s3path="$today_root"
      suffix="_Build-0"
    fi

    # 1) yesterday’s 23h slice
    aws s3 ls "$yesterday_s3path/" --recursive \
      | awk '{print $4}' \
      | grep 'Sisnet' \
      | grep "${band}_" \
      | grep 'ems\.tgz$' \
    | while read -r key; do
        fname=$(basename "$key")
        aws s3 cp "s3://southpan-gmv-sbas-messages/${key}" "$fname" --quiet
        tar -tzf "$fname" | grep '_23\.ems$' \
          | xargs -r -I{} tar -xzf "$fname" "{}"
        rm -f "$fname"
      done

    # 2) today’s full-day
    aws s3 ls "$today_s3path/" --recursive \
      | awk '{print $4}' \
      | grep 'Sisnet' \
      | grep "${band}_" \
      | grep 'ems\.tgz$' \
    | while read -r key; do
        fname=$(basename "$key")
        aws s3 cp "s3://southpan-gmv-sbas-messages/${key}" "$fname" --quiet
        tar -xzf "$fname"
        rm -f "$fname"
      done

    # concatenate in timestamp order
    build_out="${prefix}_${YEAR}${DOY}${suffix}.ems"
    : > "$build_out"
    for f in $(ls Sisnet* 2>/dev/null | sort); do
      cat "$f" >> "$build_out"
      rm -f "$f"
    done

    # dedupe
    awk '!seen[$2 $3 $4 $5 $6 $7]++' "$build_out" > tmp && mv tmp "$build_out"

    # only run if $out exists and its size is > 0
    # gap-check
    if [ -s "$build_out" ]; then
      if python3 ../../../scripts/check_data/check_ems-doy.py "$build_out" "$full_date"; then
        complete_candidate="$build_out"
        echo "✔ $build_out: no gaps"
        break
      else
        echo "✖ $build_out: gaps"
        size=$(stat -c '%s' "$build_out")
        if (( size > largest_size )); then
          largest_size=$size
          largest_candidate="$build_out"
        fi
      fi
    else
      echo "✖ $prefix file is empty or missing"
    fi
  done

  # pick the winner
  out="${prefix}_${YEAR}${DOY}.ems"
  if [[ -n "$complete_candidate" ]]; then
    mv "$complete_candidate" "$out"
    rm -f "${prefix}_${YEAR}${DOY}"_*".ems"
    return 0
  elif [[ -n "$largest_candidate" ]]; then
    mv "$largest_candidate" "$out"
    echo "⚠ No complete set; picked largest: $largest_candidate"
    rm -f "${prefix}_${YEAR}${DOY}"_*".ems"
    return 1
  else
    echo "❗ Nothing downloaded"
    return 1
  fi

}


for prefix in L1_INT L5_INT; do
  out="${DIR}/${prefix}_${YEAR}${DOY}.ems"
  ura="${DIR}/${prefix}_${YEAR}${DOY}.uralla.ems"
  awa="${DIR}/${prefix}_${YEAR}${DOY}.awarua.ems"
  gmv="${DIR}/${prefix}_${YEAR}${DOY}.gmv.ems"

  mkdir -p "$DIR"
  rm -f "$ura" "$awa" "$out" "$gmv"

  band="${prefix%%_*}"  # extracts 'L1' or 'L5' from 'L1_INT' or 'L5_INT'

  echo "---------------------------$prefix---------------------------"
  # 1) Try Uralla
  echo "→ Trying Uralla for $prefix"
  pull_ems "$prefix" "s3://southpan-das-messages/Uralla${band}"
  r1=$?
  cp "$out" "$ura" 2>/dev/null || :
  s1=$(stat -c '%s' "$ura" 2>/dev/null || echo 0)

  if [[ $r1 -eq 0 ]]; then
    echo "✔ Uralla has no gaps, picking Uralla for $prefix"
    cp "$ura" "$out"
  else
    echo "→ Trying Awarua for $prefix"
    pull_ems "$prefix" "s3://southpan-das-messages/Awarua${band}"
    r2=$?
    cp "$out" "$awa" 2>/dev/null || :
    s2=$(stat -c '%s' "$awa" 2>/dev/null || echo 0)

    if [[ $r2 -eq 0 ]]; then
      echo "✔ Awarua has no gaps, picking Awarua for $prefix"
      cp "$awa" "$out"
    else
      echo "→ Trying GMV for $prefix"
      pull_gmv_ems $prefix
      r3=$?
      cp "$out" "$gmv" 2>/dev/null || :
      s3=$(stat -c '%s' "$gmv" 2>/dev/null || echo 0)

      if [[ $r3 -eq 0 ]]; then
        echo "✔ GMV has no gaps, picking GMV for $prefix"
        cp "$gmv" "$out"
      else

        max_source=""
        max_size=0

        if (( s1 > max_size )); then
          max_size=$s1
          max_source="$ura"
        fi

        if (( s2 > max_size )); then
          max_size=$s2
          max_source="$awa"
        fi

        if (( s3 > max_size )); then
          max_size=$s3
          max_source="$gmv"
        fi

        if [[ -n "$max_source" ]]; then
          echo "⚠ All sources had gaps; picking largest file: $max_source ($max_size bytes)"
          cp "$max_source" "$out"
        else
          echo "❌ No valid files found for $prefix"
          shopt -s nullglob
          files=("${DIR}/${prefix}"*)
          if (( ${#files[@]} )); then
            rm "${files[@]}"
          fi
          shopt -u nullglob
        fi
      fi
    fi
  fi
  rm -f "$ura" "$awa" "$gmv"
done
