#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

LOG_FILE="build.log"
rm -f "$LOG_FILE"  # Remove any existing log file

pad_string() {
  local input="$1"
  local totalCharacters=$2
  # Calculate how many spaces are needed
  local padding_length=$(($totalCharacters - ${#input}))
  # Create a string of spaces and concatenate with the input
  echo "│ ${input}$(printf ' %.0s' $(seq 1 $padding_length)) │"
}

echo_and_log() {
  local message="$1"

  # Calculate how many spaces are needed
  local padding_length=$((36 - ${#message}))

  echo $message

  echo "┌──────────────────────────────────────┐" >> "$LOG_FILE"
  echo "│ ${message}$(printf ' %.0s' $(seq 1 $padding_length)) │" >> "$LOG_FILE"
  echo "└──────────────────────────────────────┘" >> "$LOG_FILE"
}

echo_and_log "Starting build process..."

echo_and_log "Compiling contracts..."
if ! bun run build >> "$LOG_FILE" 2>&1; then
  echo "Error: 'bun run build' failed. Check the log for details."
  exit 1
fi

echo_and_log "Generating contract artifacts..."
if ! bun run build:artifacts >> "$LOG_FILE" 2>&1; then
  echo "Error: 'bun run build:artifacts' failed. Check the log for details."
  exit 1
fi

echo_and_log "Generating wagmi typed ABI..."
if ! bun run build:wagmi >> "$LOG_FILE" 2>&1; then
  echo "Error: 'bun run build:wagmi' failed. Check the log for details."
  exit 1
fi

echo_and_log "Generating typechain types and factories for ethers v5..."
if ! bun run build:typechain >> "$LOG_FILE" 2>&1; then
  echo "Error: 'bun run build:typechain' failed. Check the log for details."
  exit 1
fi

echo_and_log "Compiling typescript files..."
if ! bun run build:js >> "$LOG_FILE" 2>&1; then
  echo "Error: 'bun run build:js' failed. Check the log for details."
  exit 1
fi

echo_and_log "Build completed successfully."
