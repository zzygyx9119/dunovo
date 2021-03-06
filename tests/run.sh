#!/usr/bin/env bash
if [ x$BASH = x ] || [ ! $BASH_VERSINFO ] || [ $BASH_VERSINFO -lt 4 ]; then
  echo "Error: Must use bash version 4+." >&2
  exit 1
fi
# get the name of the test directory
dirname=$(dirname $0)

USAGE="Usage: \$ $(basename $0) [options] [test1 [test2]]"


function main {

  gave_tests=
  verbose=true
  # Run the requested tests
  for arg in "$@"; do
    # Check for options
    #TODO: option to keep test data at end instead of removing it.
    if [[ ${arg:0:1} == '-' ]]; then
      case "$arg" in
        -h)
          echo "$USAGE" >&2
          echo "Currently valid tests:" >&2
          list_tests >&2
          echo "Meta tests:" >&2
          list_meta_tests >&2
          exit 1;;
        -q)
          verbose='';;
        -v)
          verbose=true;;
        *)
          echo "Unrecognized option \"$arg\"." >&2;;
      esac
      continue
    fi
    # Execute valid tests (if they're existing functions).
    if [[ $(type -t $arg) == function ]]; then
      gave_tests=true
      if [[ $verbose ]]; then
        $arg
      else
        $arg 2>/dev/null
      fi
    else
      echo "Unrecognized test \"$arg\"." >&2
    fi
  done

  # If no tests were specified in arguments, do all tests.
  if ! [[ $gave_tests ]]; then
    fail "Error: Please specify a valid test to run (or \"all\" to run all of them)."
  fi
}

function fail {
  echo "$@" >&2
  exit 1
}

function list_tests {
  while read declare f test; do
    # Filter out functions that aren't tests.
    if echo "$initial_declarations_plus_meta" | grep -qF "declare -f $test"; then
      continue
    elif echo "$test" | grep -qE '^_'; then
      continue
    else
      echo "  $test"
    fi
  done < <(declare -F)
}

function list_meta_tests {
  while read declare f test; do
    if echo "$initial_declarations" | grep -qF "declare -f $test"; then
      continue
    elif echo "$initial_declarations_plus_meta" | grep -qF "declare -f $test"; then
      echo "  $test"
    fi
  done < <(declare -F)
}

# Capture a list of all functions defined before the tests, to tell which are actual functions
# and which are tests.
initial_declarations=$(declare -F)


########## Meta tests ##########

# Run all tests.
function all {
  for test in $(list_tests); do
    $test
  done
}

# Run the errstats.py-specific tests.
function errstats {
  errstats_simple
  errstats_overlap
}

# Run the dunovo.py-specific tests.
function dunovo_all {
  declare -a tests
  i=1
  while read declare f test; do
    if echo "$test" | grep -qE '^dunovo' && [[ $test != dunovo_all ]]; then
      tests[$i]=$test
      i=$((i+1))
    fi
  done < <(declare -F)
  for test in ${tests[@]}; do
    $test
  done
}

# Get the list of functions now that the meta tests have been declared.
initial_declarations_plus_meta=$(declare -F)


########## Functional tests ##########

# make-barcodes.awk
function barcodes {
  echo -e "\tmake-barcodes.awk ::: families.raw_[12].fq"
  paste "$dirname/families.raw_1.fq" "$dirname/families.raw_2.fq" \
    | paste - - - - \
    | awk -f "$dirname/../make-barcodes.awk" -v TAG_LEN=12 -v INVARIANT=5 \
    | sort \
    | diff -s - "$dirname/families.sort.tsv"
}

# align_families.py
function align {
  echo -e "\talign_families.py ::: families.sort.tsv:"
  python "$dirname/../align_families.py" -q "$dirname/families.sort.tsv" \
    | diff -s - "$dirname/families.msa.tsv"
}

# align_families.py with 3 processes
function align_p3 {
  echo -e "\talign_families.py -p 3 ::: families.sort.tsv:"
  python "$dirname/../align_families.py" -q -p 3 "$dirname/families.sort.tsv" \
    | diff -s - "$dirname/families.msa.tsv"
}

# align_families.py smoke test
function align_smoke {
  echo -e "\talign_families.py ::: smoke.families.tsv:"
  python "$dirname/../align_families.py" -q "$dirname/smoke.families.tsv" \
    | diff -s - "$dirname/smoke.families.aligned.tsv"
}

# dunovo.py defaults on toy data
function dunovo {
  _dunovo families.msa.tsv families.sscs_1.fa families.sscs_2.fa families.dcs_1.fa families.dcs_2.fa
}

# dunovo.py with 3 processes
function dunovo_p3 {
  _dunovo families.msa.tsv families.sscs_1.fa families.sscs_2.fa families.dcs_1.fa families.dcs_2.fa -p 3
}

# dunovo.py quality score consideration
function dunovo_qual {
  _dunovo qual.msa.tsv qual.10.sscs_1.fa qual.10.sscs_2.fa empty.txt empty.txt -q 10
  _dunovo qual.msa.tsv qual.20.sscs_1.fa qual.20.sscs_2.fa empty.txt empty.txt -q 20
}

function dunovo_gapqual {
  _dunovo gapqual.msa.tsv gapqual.sscs_1.fa gapqual.sscs_2.fa empty.txt empty.txt -q 25
}

function dunovo_consthres {
  _dunovo cons.thres.msa.tsv cons.thres.0.5.sscs_1.fa cons.thres.0.5.sscs_2.fa \
          cons.thres.0.5.dcs_1.fa cons.thres.0.5.dcs_2.fa \
          --min-cons-reads 3 --cons-thres 0.5
  _dunovo cons.thres.msa.tsv cons.thres.0.7.sscs_1.fa cons.thres.0.7.sscs_2.fa \
          cons.thres.0.7.dcs_1.fa cons.thres.0.7.dcs_2.fa \
          --min-cons-reads 3 --cons-thres 0.7
}

# baralign.sh
function baralign {
  echo -e "\tbaralign.sh ::: correct.families.tsv:"
  bash "$dirname/../baralign.sh" "$dirname/correct.families.tsv" "$dirname/refdir.tmp" 2>/dev/null \
    | diff -s "$dirname/correct.sam" -
  rm -rf "$dirname/refdir.tmp"
}

# correct.py
function correct {
  echo -e "\tcorrect.py ::: correct.sam"
  "$dirname/../correct.py" "$dirname/correct.families.tsv" \
      "$dirname/correct.barcodes.fa" "$dirname/correct.sam" \
    | diff -s "$dirname/correct.families.corrected.tsv" -
}

function stats_diffs {
  echo -e "\tstats.py diffs ::: gaps.msa.tsv:"
  python "$dirname/../utils/stats.py" diffs "$dirname/gaps.msa.tsv" \
    | diff -s - "$dirname/gaps-diffs.out.tsv"
}

function errstats_simple {
  echo -e "\terrstats.py ::: families.msa.tsv:"
  python "$dirname/../utils/errstats.py" "$dirname/families.msa.tsv" | diff -s - "$dirname/errstats.out.tsv"
  python "$dirname/../utils/errstats.py" -R "$dirname/families.msa.tsv" | diff -s - "$dirname/errstats.-R.out.tsv"
  python "$dirname/../utils/errstats.py" -a "$dirname/families.msa.tsv" | diff -s - "$dirname/errstats.-a.out.tsv"
  python "$dirname/../utils/errstats.py" -R -a "$dirname/families.msa.tsv" | diff -s - "$dirname/errstats.-R.-a.out.tsv"
}

function errstats_overlap {
  echo -e "\terrstats.py ::: families.overlap.msa.tsv"
  python "$dirname/../utils/errstats.py" --dedup --min-reads 3 --bam "$dirname/families.overlap.sscs.bam" \
    "$dirname/families.overlap.msa.tsv" --overlap-stats "$dirname/overlaps.tmp.tsv" >/dev/null
  diff -s "$dirname/overlaps.tmp.tsv" "$dirname/families.overlap.overlaps.expected.tsv"
  if [[ -f "$dirname/overlaps.tmp.tsv" ]]; then
    rm "$dirname/overlaps.tmp.tsv"
  fi
}

# utility function for all dunovo.py tests
function _dunovo {
  # Read required arguments.
  input=$1
  sscs1=$2
  sscs2=$3
  dcs1=$4
  dcs2=$5
  # Read optional arguments (after the required ones).
  declare -a args
  i=6
  while [[ ${!i} ]]; do
    args[$i]=${!i}
    i=$((i+1))
  done
  echo -e "\tdunovo.py ${args[@]} ::: $input:"
  python "$dirname/../dunovo.py" ${args[@]} "$dirname/$input" \
    --sscs1 "$dirname/families.tmp.sscs_1.fa" --sscs2 "$dirname/families.tmp.sscs_2.fa" \
    --dcs1  "$dirname/families.tmp.dcs_1.fa"  --dcs2  "$dirname/families.tmp.dcs_2.fa"
  diff -s "$dirname/families.tmp.sscs_1.fa" "$dirname/$sscs1"
  diff -s "$dirname/families.tmp.sscs_2.fa" "$dirname/$sscs2"
  diff -s "$dirname/families.tmp.dcs_1.fa"  "$dirname/$dcs1"
  diff -s "$dirname/families.tmp.dcs_2.fa"  "$dirname/$dcs2"
  for file in "$dirname/families.tmp.sscs_1.fa" "$dirname/families.tmp.sscs_2.fa" \
      "$dirname/families.tmp.dcs_1.fa" "$dirname/families.tmp.dcs_2.fa"; do
    if [[ -f "$file" ]]; then
      rm "$file"
    fi
  done
}

main "$@"
