#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

OUTPUT_DIR=artifacts
BUILD_DIR=out

if [ ! -d "$BUILD_DIR" ]; then
  echo "Error: Directory '$BUILD_DIR' does not exist. Run 'bun run build' to generate artifacts." >&2
  exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# List of contracts to package
CONTRACTS=(
  # LSP versions of the routes
  "HypLSP7Collateral"
  "HypLSP7"
  "HypLSP8Collateral"
  "HypLSP8"
  # Pausable versions of the routes
  "HypERC20CollateralPausable"
  "HypERC20Pausable"
  "HypLSP7CollateralPausable"
  "HypLSP7Pausable"
  "HypLSP8CollateralPausable"
  "HypLSP8Pausable"
  "HypNativePausable"
)

# Function to check and copy artifact
copy_artifact() {
  local contract=$1

  if [ ! -f "$BUILD_DIR/${contract}.sol/${contract}.json" ]; then
    echo "Warning: Artifacts for '${contract}.sol' are missing." >&2
  else
    cp "$BUILD_DIR/${contract}.sol/${contract}.json" "$OUTPUT_DIR/"
  fi
}

# Copy each contract artifact
echo "Packaging artifacts..."
for CONTRACT in "${CONTRACTS[@]}"; do
  copy_artifact "$CONTRACT"
done

echo "Artifacts successfully packaged in '$OUTPUT_DIR'"
