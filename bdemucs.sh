#!/usr/bin/env bash
# Script by: Chris Lewicki

# Bash script to convert audio files to instrumental / karaoke versions using demucs and ffmpeg

# Required software:
# demucs (https://github.com/facebookresearch/demucs)
# ffmpeg (https://ffmpeg.org/)

# Example usage:
# ./bdemucs.sh -s -o /Users/Me/Instrumentals MySong1.flac

# Set default global values
OUTPUT_ROOT="/Volumes/Media/Instrumentals"
DEMUCS_MODEL="htdemucs_ft"
MULTITRACK_ROOT="/Volumes/Media/Multitracks"
NUM_CORES=1
SAVE_MULTITRACK=false
ONLY_MULTITRACK=false
WORKING_DIR="/tmp/bdemucs"
ALBUM_APPEND_STRING=" (Instrumental)" # String to append to album name, including any leading space if desired
FILE_APPEND_STRING="_instrumental"    # String to append to file name, including any leading space if desired
DEBUG=false

# Declare an empty array for errors
declare -a ERRORS

function display_help() {
  echo "Usage: $(basename "$0") [OPTIONS] INPUT"
  echo
  echo "Options:"
  echo "  -o, --output-dir DIR         Set the output base directory (default: /Volumes/Media/Instrumentals)"
  echo "  -s, --save-multitrack        Save multitrack files (default: false)"
  echo "  -m, --only-multitrack        Only process multitrack files (default: false)"
  echo "  -a, --append                 String to append to Album title (default: \"${ALBUM_APPEND_STRING}\")"
  echo "  -f, --file-append            String to append to file name (default: \"${FILE_APPEND_STRING}\")"
  echo "  -d, --debug                  Enable debug mode (default: false)"
  echo
  echo "Input:"
  echo "  INPUT                        Input files or folders"
  echo
}

function echobold() {
  echo -e "\033[1m${1}\033[0m"
}

function echored() {
  echo -e "\033[31m${1}\033[0m"
}

function echoitalic() {
  echo -e "\033[3m${1}\033[0m"
}

# Function to perform cleanup actions
function cleanup() {
  if [[ $DEBUG == "true" ]]; then
    echo "Debug mode is enabled. Preserving working directory."
    echo "Clean up your files in $WORKING_DIR"
  else
    echo "Cleaning up working directory: $WORKING_DIR"
    if [[ $SAVE_MULTITRACK == "false" ]]; then
      rm -f "${WORKING_DIR_ultimate}/tmp.flac" "${WORKING_DIR_ultimate}/bass.wav" "${WORKING_DIR_ultimate}/drums.wav" "${WORKING_DIR_ultimate}/other.wav" "${WORKING_DIR_ultimate}/vocals.wav"
      rmdir "${WORKING_DIR_ultimate}"
    fi
    rmdir "${WORKING_DIR}/${DEMUCS_MODEL}"

    # Remove the temporary working directory, which now should be empty
    rmdir "${WORKING_DIR}"
  fi
  echo
}

# Handle SIGINT and SIGTERM signals
# shellcheck disable=SC2317
function handle_sigint() {
  echo "Terminated by user..."

  # Perform cleanup actions if not in debug mode
  if [[ $DEBUG == "false" ]]; then
    cleanup
  fi
  exit 1
}

# Set trap to perform cleanup actions on script termination
trap handle_sigint SIGINT SIGTERM

# Function to extract metadata from an input file
function extract_metadata() {
  local song
  local album_year_string
  song=$1
  album_year_string=$(ffprobe -v quiet -show_entries format_tags=date -of default=noprint_wrappers=1:nokey=1 "$song")
  ALBUM=$(ffprobe -v quiet -show_entries format_tags=album -of default=noprint_wrappers=1:nokey=1 "$song")
  ARTIST=$(ffprobe -v quiet -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$song")

  ALBUM_YEAR=${album_year_string:0:4}
}

# Function to check if the file is an audio file and set bit depth flag
function check_audio_file_and_set_bit_depth() {
  local input_file
  input_file=$1

  if [[ "$input_file" =~ \.(mp3|flac|m4a|m4v|wav|wma)$ ]]; then
    bit_depth=$(ffprobe -v error -select_streams a:0 -show_entries stream=bits_per_raw_sample -of default=noprint_wrappers=1:nokey=1 "$input_file")

    if [[ $bit_depth == "24" ]]; then
      INT24_FLAG="--int24"
    else
      INT24_FLAG=""
    fi
  else
    echoitalic "\"${input_filename}\" is not an audio file"
    return 1
  fi
}

# Function to create a temporary working directory
function create_temp_working_dir() {
  if [[ "$(uname)" == "Linux" ]]; then
    # Linux (Ubuntu) systems
    WORKING_DIR=$(mktemp -d -t "bdemucs.XXXXXX")
  elif [[ "$(uname)" == "Darwin" ]]; then
    # macOS systems
    WORKING_DIR=$(mktemp -d -t "bdemucs")
  else
    echo "Unsupported operating system."
    return 1
  fi
}

# Main process_file function
function process_file() {
  # Set the various file and directory variables
  local input_file
  local input_filename
  local input_file_basename
  local input_file_fullpath
  local input_file_duration
  local input_file_sample_rate

  input_file=$1
  input_filename=$(basename "$input_file")
  input_file_basename="${input_filename%.*}"
  input_file_fullpath=$(readlink -f "$input_file")

  check_audio_file_and_set_bit_depth "$input_file" || return 1

  extract_metadata "$input_file_fullpath"

  # Duration of the input file in seconds
  input_file_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file_fullpath")

  # Sample rate of the input file
  input_file_sample_rate=$(ffprobe -v error -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$input_file_fullpath")

  # Append " - Instrumental" to the album title
  local new_album="${ALBUM}{$ALBUM_APPEND_STRING}"

  # Set the output file based on the OUTPUT_ROOT, artist, and album - include year if it looks like a year
  if [[ $ALBUM_YEAR =~ ^[0-9]{4}$ ]]; then
    local output_file_dir="${OUTPUT_ROOT}/${ARTIST}/${ALBUM_YEAR} ${ALBUM}"
    local multitrack_dir="${MULTITRACK_ROOT}/${ARTIST}/${ALBUM_YEAR} ${ALBUM}"
  else
    local output_file_dir="${OUTPUT_ROOT}/${ARTIST}/${ALBUM}"
    local multitrack_dir="${MULTITRACK_ROOT}/${ARTIST}/${ALBUM}"
  fi

  local output_file_final="${output_file_dir}/${input_file_basename}${FILE_APPEND_STRING}.flac"

  # Determine if $output_file_final already exists, but only if $ONLY_MULTITRACK is false
  if [[ "$ONLY_MULTITRACK" = false && -e "$output_file_final" ]]; then
    echoitalic "Output file already exists: ${output_file_final}"

    # Skip processing of this file
    return 0
  fi

  # Determine if the multi-track output files already exist at the destination
  # Note that since the process will make the song-folder, we need to append it to the multi-track directory
  if [[ "$SAVE_MULTITRACK" = true ]]; then
    if [[ -d "${multitrack_dir}/${input_file_basename}" ]]; then
      echoitalic "Multi-track output directory already exists: ${multitrack_dir}/${input_file_basename}"

      # Skip processing of this file
      return 0
    fi
  fi

  echo
  echo "Artist:      ${ARTIST}"
  echo "Album:       ${ALBUM}"
  echo "Song File:   ${input_file_basename}"
  echo "Album Year:  ${ALBUM_YEAR}"
  echo "Sample Rate: ${input_file_sample_rate}"
  echo "Bit Depth:   ${bit_depth} bit"
  echo "Dest Dir:    ${output_file_dir}"
  echo

  # Call create_temp_working_dir to set the ephemeral WORKING_DIR variable
  create_temp_working_dir || return 1

  WORKING_DIR_ultimate="${WORKING_DIR}/${DEMUCS_MODEL}/${input_file_basename}"

  # Start timer for processing
  processing_start_time=$(date +%s)
  # Process file and echo the command being processed to the user
  echo "demucs -n $DEMUCS_MODEL --out $WORKING_DIR $INT24_FLAG -d cpu --jobs $NUM_CORES \"${input_file_fullpath}\""
  # shellcheck disable=SC2086
  demucs -n $DEMUCS_MODEL --out "$WORKING_DIR" $INT24_FLAG -d cpu --jobs $NUM_CORES "${input_file_fullpath}"
  ret=$?
  echo

  # Note - this doesn't seem to catch errors from demucs
  if [ $ret -ne 0 ]; then
    # If demucs did not complete successfully, print the error message in red and append the file to the errors array
    echored "Error: demucs did not complete successfully for ${input_file_fullpath}" >&2

    # Append a new error to the array
    ERRORS+=("${input_file_fullpath}")

  return 1
  fi  

  # End timer for processing
  processing_end_time=$(date +%s)
  # Calculate the total time for processing
  processing_total_time=$((processing_end_time - processing_start_time))
  # Echo the total time for processing to the user
  processing_rate=$(echo "scale=2; $input_file_duration / $processing_total_time" | bc)
  echo "Total time for processing: $processing_total_time seconds at $processing_rate seconds/s"
  echo

  # Set a variable Name for the output file the same as $input_file, but with a flac extension
  output_file="${WORKING_DIR_ultimate}/${input_file_basename}.flac"

  # Make sure all demucs files exist before proceeding: bass.wav, drums.wav, other.wav
  if [ ! -f "${WORKING_DIR_ultimate}/bass.wav" ] && \
    [ ! -f "${WORKING_DIR_ultimate}/drums.wav" ] && \
    [ ! -f "${WORKING_DIR_ultimate}/other.wav" ]
  then
    echored "Error: one or more of the demucs files do not exist in ${WORKING_DIR_ultimate}" >&2
    # Append a new error to the array, as this was missed with the demucs error check above
    ERRORS+=("${input_file_fullpath}")
    return 1
  fi

  if [[ $ONLY_MULTITRACK == "false" ]]; then
    echo "Merging stems..."
  #  ffmpeg -i "${WORKING_DIR_ultimate}/bass.wav" -i "${WORKING_DIR_ultimate}/drums.wav" -i "${WORKING_DIR_ultimate}/other.wav" -filter_complex "amix=inputs=3:duration=longest" -c:a flac "${output_file}"
    ffmpeg -loglevel warning -i "${WORKING_DIR_ultimate}/bass.wav" -i "${WORKING_DIR_ultimate}/drums.wav" -i "${WORKING_DIR_ultimate}/other.wav" -filter_complex "amix=inputs=3:duration=longest" "${WORKING_DIR_ultimate}/tmp.flac"

    echo "Copying metadata..."
    # Copy metadata and set the new album title using FFmpeg
    ffmpeg -loglevel warning -i "${input_file_fullpath}" -i "${WORKING_DIR_ultimate}/tmp.flac" -map 1 -map_metadata 0 -metadata album="$new_album" -c copy "${output_file}"


    mkdir -p "$output_file_dir"
    echo "Moving output file to final location"
    echo "mv \"${output_file}\" \"${output_file_final}\""

    if ! mv "${output_file}" "${output_file_final}" ; then
      echored "Error: Failed to move output file: ${output_file} to ${output_file_final}"
      return 1
    fi
  fi

  # If everything up to this point worked, process the working files
  if [[ $SAVE_MULTITRACK == "true" ]]; then
    rm -f "{$WORKING_DIR_ultimate}/tmp.flac"
    mkdir -p "$multitrack_dir"
    echo "Moving multitrack files to final location: ${multitrack_dir}/${input_file_basename}"
    
    # Throw error if the mv command failed
    if ! mv -n "${WORKING_DIR_ultimate}" "${multitrack_dir}"; then
      echored "Error: Failed to move multitrack files to ${multitrack_dir}"
      echored "Working files are located at ${WORKING_DIR_ultimate}"
      return 1
    fi
  fi

  cleanup
}

function process_folder() {
  # Set the input folder
  input_folder=$1

  # Loop through all files in the input folder
  for input_file in "$input_folder"/*; do
    # Process the file
    process_file "$input_file"

    sleep 1
  done 
}

# Process command line arguments
function process_args() {
  while (($#)); do
    case "$1" in
      -o|--output-dir)
        OUTPUT_ROOT="$2"
        echo "Output directory: $OUTPUT_ROOT"
        shift 2
        ;;
      -s|--save-multitrack)
        SAVE_MULTITRACK=true
        echobold "Saving multitrack output"
        shift
        ;;
      -m|--only-multitrack)
        ONLY_MULTITRACK=true
        SAVE_MULTITRACK=true
        echobold "Processing only multitrack output"
        shift
        ;;
      -a|--append)
        ALBUM_APPEND_STRING="$2"
        echobold "Appending \"$ALBUM_APPEND_STRING\" to album name tags"
        shift 2
        ;;
      -f|--file-append)
        FILE_APPEND_STRING="$2"
        echobold "Appending \"$FILE_APPEND_STRING\" to file name"
        shift 2
        ;;
      -d|--debug)
        DEBUG=true
        echobold "Debug mode enabled"
        shift
        ;;
      -h|--help)
        display_help
        exit 0
        ;;
      -*)
        echo "Unknown flag: $1"
        exit 1
        ;;
      *)
        if [ -f "$1" ]; then
          # Handle file
          echo "File: $1"
          process_file "$1"
        elif [ -d "$1" ]; then
          # Handle directory
          echo "Dir:  $1"
          process_folder "$1"
        else
          echo "Unknown argument: $1"
          exit 1
        fi
        shift
        ;;
  esac
done
}

function set_num_cores() {
  if [[ "$(uname)" == "Linux" ]]; then
    TOTAL_CORES=$(nproc)
  elif [[ "$(uname)" == "Darwin" ]]; then
    TOTAL_CORES=$(sysctl -n hw.physicalcpu)
  else
    echo "Unsupported operating system."
    return 1
  fi

  # NUM_CORES is set to 2 less than the total number of cores
  NUM_CORES=$((TOTAL_CORES - 2))
  if [ $NUM_CORES -le 0 ]; then
      NUM_CORES=1
  fi

  echobold "Processing with $NUM_CORES of $TOTAL_CORES cores"
}

function display_errors() {
  if [ ${#ERRORS[@]} -eq 0 ]; then
    echobold "No errors detected"
  else
    echored "Errors detected. You may need to manually re-process the following file(s):"

    for error in "${ERRORS[@]}"; do
      echored "  $error"
    done
    exit 1
  fi
}

# Main function
function main() {
  set_num_cores
  process_args "$@"
  display_errors
  exit 0
}

# Call the main function and pass command-line arguments
main "$@"