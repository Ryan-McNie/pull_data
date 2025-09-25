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

merge_ems(){
  prefix=$1        # L1_SIS or L5_SIS
  s3root=$2        # e.g. s3://…/LINZ_Novatel
  out="${DIR}/${prefix}_${YEAR}${DOY}.ems"

  mkdir -p "$DIR"
  cd "$DIR"

  # build download list
  files=()

  # prev-day 23h chunk
  if aws s3 cp "${s3root}/y${PYEAR}/d${PDOY}/${prefix}_${PYEAR}${PDOY}_23.ems" . --quiet; then
    files+=( "${prefix}_${PYEAR}${PDOY}_23.ems" )
  else
    echo "⚠ warning: missing ${prefix}_${PYEAR}${PDOY}_23.ems"
  fi

  # today 00–23
  aws s3 cp "${s3root}/y${YEAR}/d${DOY}" . --recursive --exclude "*" --include "${prefix}_*.ems" --quiet

  for h in $(seq -w 0 23); do
    files+=( "${prefix}_${YEAR}${DOY}_${h}.ems" )
  done

  # empty output
  : > "$out"

  # for each chunk, filter exactly that hour
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || { continue; }

    # parse out the yyyydddhh
    base="${f%.ems}"
    suf="${base#${prefix}_}"       # e.g. 2025175_14
    fy="${suf:0:4}"; fd="${suf:4:3}"; hh="${suf:8:2}"

    # choose ISO date
    if [[ $fy == $PYEAR && $fd == $PDOY ]]; then
      iso=$(doy2date $PYEAR $PDOY)
    elif [[ $fy == $YEAR  && $fd == $DOY ]]; then
      iso=$(doy2date $YEAR  $DOY)
    else
      echo "⚠ skipping unexpected $f"
      continue
    fi

    Y2=${iso:2:2}; M2=${iso:5:2}; D2=${iso:8:2}

    # keep only lines in the right YY MM DD HH
    # this automatically drops the extra 30 s at each boundary
    awk -v Y2=$Y2 -v M2=$M2 -v D2=$D2 -v H=$hh '
      $2==Y2 && $3==M2 && $4==D2 && $5==H
    ' "$f" >> "$out"

    rm -f "$f"
  done

  rm -f "${DIR}/${prefix}_${YEAR}${DOY}"_??.ems  "${DIR}/${prefix}_${PYEAR}${PDOY}"_23.ems || true

  # dedupe any duplicate timestamps (field2..7 = YY MM DD HH MM SS)
  awk '!seen[$2 $3 $4 $5 $6 $7]++' "$out" > "${out}.dedup"
  mv "${out}.dedup" "$out"

   # if there's literally no data in $out, fail so we can retry on the other source
   if [[ ! -s "$out" ]]; then
     echo "✖ $prefix no data collected"
     return 1
   fi

  # gap check over [prev-day 23:50 … target-day 23:59:59]
  target_date=$(doy2date $YEAR $DOY)
  if python3 ../../../scripts/check_data/check_ems-doy.py "$out" "$target_date"; then
    echo "✔ $prefix OK (no gaps in window)"
    return 0
  else
    echo "✖ $prefix has gaps in window"
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
      | grep 'LogBook' \
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
      | grep 'LogBook' \
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
    for f in $(ls LogBook* 2>/dev/null | sort); do
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






for prefix in L1_SIS L5_SIS; do
  out="${DIR}/${prefix}_${YEAR}${DOY}.ems"
  nov="${DIR}/${prefix}_${YEAR}${DOY}.nov.ems"
  sep="${DIR}/${prefix}_${YEAR}${DOY}.sep.ems"
  gmv="${DIR}/${prefix}_${YEAR}${DOY}.gmv.ems"

  mkdir -p "$DIR"
  rm -f "$nov" "$sep" "$out" "$gmv"

  echo "---------------------------$prefix---------------------------"

  # 1) Novatel
  echo "→ Trying Novatel for $prefix"
  merge_ems "$prefix" "s3://southpan-sis-messages/LINZ_Novatel"
  r1=$?                                # 0 if no gaps
  cp "$out" "$nov" 2>/dev/null || :
  s1=$(stat -c '%s' "$nov" 2>/dev/null || echo 0)

  if [[ $r1 -eq 0 ]]; then
    # perfect Novatel → pick and skip Septentrio altogether
    echo "✔ Novatel has no gaps, picking Novatel for $prefix"
    cp "$nov" "$out"
  else
    # 2) only now try Septentrio
    echo "→ Trying Septentrio for $prefix"
    merge_ems "$prefix" "s3://southpan-sis-messages/LINZ_Septentrio"
    r2=$?
    cp "$out" "$sep" 2>/dev/null || :
    s2=$(stat -c '%s' "$sep" 2>/dev/null || echo 0)

    if   [[ $r2 -eq 0 ]]; then
      echo "✔ Septentrio has no gaps, picking Septentrio for $prefix"
      cp "$sep" "$out"
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
          max_source="$nov"
        fi

        if (( s2 > max_size )); then
          max_size=$s2
          max_source="$sep"
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
  rm -f "$nov" "$sep" "$gmv"
done
