#!/usr/bin/env bash
set -u

usage() {
  printf 'usage: raw-week.sh --workspace <path> (--week <YYYY-Www> | --date <YYYY-MM-DD>)\n' >&2
}

date_to_iso_week() {
  local input_date=$1

  awk -v input_date="$input_date" '
    function leap(year) {
      return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
    function month_days(year, month) {
      if (month == 2) return 28 + leap(year)
      if (month == 4 || month == 6 || month == 9 || month == 11) return 30
      return 31
    }
    function valid_date(year, month, day) {
      return year >= 1 && year <= 9999 && month >= 1 && month <= 12 \
        && day >= 1 && day <= month_days(year, month)
    }
    function day_of_year(year, month, day,    result, current) {
      result = day
      for (current = 1; current < month; current++) {
        result += month_days(year, current)
      }
      return result
    }
    function weekday(year, month, day,    offsets, adjusted_year, value) {
      split("0 3 2 5 0 3 5 1 4 6 2 4", offsets, " ")
      adjusted_year = year
      if (month < 3) adjusted_year--
      value = adjusted_year + int(adjusted_year / 4) \
        - int(adjusted_year / 100) + int(adjusted_year / 400) \
        + offsets[month] + day
      value %= 7
      return value == 0 ? 7 : value
    }
    function weeks_in_year(year,    jan_first) {
      jan_first = weekday(year, 1, 1)
      return jan_first == 4 || (jan_first == 3 && leap(year)) ? 53 : 52
    }
    BEGIN {
      if (input_date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit 1
      year = substr(input_date, 1, 4) + 0
      month = substr(input_date, 6, 2) + 0
      day = substr(input_date, 9, 2) + 0
      if (!valid_date(year, month, day)) exit 1

      iso_year = year
      iso_week = int((day_of_year(year, month, day) - weekday(year, month, day) + 10) / 7)
      if (iso_week < 1) {
        iso_year = year - 1
        iso_week = weeks_in_year(iso_year)
      } else if (iso_week > weeks_in_year(year)) {
        iso_year = year + 1
        iso_week = 1
      }
      printf "%04d-W%02d\n", iso_year, iso_week
    }
  '
}

workspace=
requested_week=
requested_date=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      [[ $# -ge 2 && -z "$workspace" ]] || {
        usage
        exit 2
      }
      workspace=$2
      shift 2
      ;;
    --week)
      [[ $# -ge 2 && -z "$requested_week" ]] || {
        usage
        exit 2
      }
      requested_week=$2
      shift 2
      ;;
    --date)
      [[ $# -ge 2 && -z "$requested_date" ]] || {
        usage
        exit 2
      }
      requested_date=$2
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$workspace" ]] \
  || { [[ -n "$requested_week" ]] && [[ -n "$requested_date" ]]; } \
  || { [[ -z "$requested_week" ]] && [[ -z "$requested_date" ]]; }; then
  usage
  exit 2
fi

if [[ -n "$requested_date" ]]; then
  target_week=$(date_to_iso_week "$requested_date") || {
    usage
    exit 2
  }
else
  if [[ ! "$requested_week" =~ ^[0-9]{4}-W[0-9]{2}$ ]]; then
    usage
    exit 2
  fi
  week_year=${requested_week:0:4}
  week_number=${requested_week:6:2}
  last_week=$(date_to_iso_week "$week_year-12-28") || {
    usage
    exit 2
  }
  if [[ "$week_number" == 00 || "$requested_week" > "$last_week" ]]; then
    usage
    exit 2
  fi
  target_week=$requested_week
fi

archive_dir=$workspace/loop/archive
if [[ ! -d "$archive_dir" ]]; then
  printf 'missing path: loop/archive/\n' >&2
  exit 1
fi

for raw_path in "$archive_dir"/*; do
  [[ -f "$raw_path" && ! -L "$raw_path" ]] || continue
  file_basename=${raw_path##*/}
  if [[ "$file_basename" =~ ^flush-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$ ]] \
    || [[ "$file_basename" =~ ^intake-evictions-([0-9]{4}-[0-9]{2}-[0-9]{2})\.md$ ]]; then
    file_date=${BASH_REMATCH[1]}
    file_week=$(date_to_iso_week "$file_date") || continue
    if [[ "$file_week" == "$target_week" ]]; then
      printf 'loop/archive/%s\n' "$file_basename"
    fi
  fi
done | LC_ALL=C sort
