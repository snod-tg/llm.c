#!/bin/bash
set -euo pipefail

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Base URL. Override this if you need to use a cache, proxy, or mirror.
BASE_URL="${LLMC_STARTER_PACK_BASE_URL:-https://huggingface.co/datasets/karpathy/llmc-starter-pack/resolve/main/}"
if [[ "$BASE_URL" != */ ]]; then
    BASE_URL="${BASE_URL}/"
fi

# Directory paths based on script location
SAVE_DIR_PARENT="$(cd "$SCRIPT_DIR/.." && pwd)"
SAVE_DIR_TINY="$SCRIPT_DIR/data/tinyshakespeare"
SAVE_DIR_HELLA="$SCRIPT_DIR/data/hellaswag"

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required but was not found in PATH" >&2
    exit 1
fi

# Create the directories if they don't exist
mkdir -p "$SAVE_DIR_TINY"
mkdir -p "$SAVE_DIR_HELLA"

# Files to download
FILES=(
    "gpt2_124M.bin"
    "gpt2_124M_bf16.bin"
    "gpt2_124M_debug_state.bin"
    "gpt2_tokenizer.bin"
    "tiny_shakespeare_train.bin"
    "tiny_shakespeare_val.bin"
    "hellaswag_val.bin"
)

check_network() {
    local TEST_FILE="${FILES[0]}"
    local TEST_URL="${BASE_URL}${TEST_FILE}?download=true"
    local CURL_ERROR
    local STATUS

    CURL_ERROR="$(mktemp "${TMPDIR:-/tmp}/llmc-starter-pack-network.XXXXXX")"

    echo "Checking network access to starter pack..."
    if curl -fLsS --head --retry 1 --connect-timeout 10 --max-time 20 -o /dev/null "$TEST_URL" 2>"$CURL_ERROR"; then
        rm -f "$CURL_ERROR"
        echo "Network check passed."
        return 0
    fi

    STATUS=$?
    echo "Error: cannot reach the starter pack download URL." >&2
    echo "Tested URL: $TEST_URL" >&2
    echo "curl exit code: $STATUS" >&2
    if [[ -s "$CURL_ERROR" ]]; then
        echo "curl output:" >&2
        while IFS= read -r line; do
            echo "  $line" >&2
        done < "$CURL_ERROR"
    fi
    rm -f "$CURL_ERROR"
    echo "Hints:" >&2
    echo "  - Check that this machine can access huggingface.co over HTTPS." >&2
    echo "  - If you need a proxy, set HTTPS_PROXY and HTTP_PROXY before running this script." >&2
    echo "  - If you use a mirror or cache, set LLMC_STARTER_PACK_BASE_URL to that base URL." >&2
    return "$STATUS"
}

# Function to download files to the appropriate directory
download_file() {
    local FILE_NAME=$1
    local FILE_URL="${BASE_URL}${FILE_NAME}?download=true"
    local FILE_PATH
    local TEMP_PATH

    # Determine the save directory based on the file name
    if [[ "$FILE_NAME" == tiny_shakespeare* ]]; then
        FILE_PATH="${SAVE_DIR_TINY}/${FILE_NAME}"
    elif [[ "$FILE_NAME" == hellaswag* ]]; then
        FILE_PATH="${SAVE_DIR_HELLA}/${FILE_NAME}"
    else
        FILE_PATH="${SAVE_DIR_PARENT}/${FILE_NAME}"
    fi

    TEMP_PATH="$(mktemp "${FILE_PATH}.tmp.XXXXXX")"
    trap 'rm -f "$TEMP_PATH"; exit 130' INT TERM

    echo "Downloading $FILE_NAME to $FILE_PATH..."
    if curl -fLsS --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 20 -o "$TEMP_PATH" "$FILE_URL"; then
        if [[ ! -s "$TEMP_PATH" ]]; then
            echo "Error: downloaded file is empty: $FILE_NAME" >&2
            rm -f "$TEMP_PATH"
            trap - INT TERM
            return 1
        fi
        mv "$TEMP_PATH" "$FILE_PATH"
        trap - INT TERM
        echo "Downloaded $FILE_NAME to $FILE_PATH"
    else
        local status=$?
        echo "Error: failed to download $FILE_NAME from $FILE_URL" >&2
        rm -f "$TEMP_PATH"
        trap - INT TERM
        return "$status"
    fi
}

check_network

# Download files one by one so progress and errors stay readable.
for FILE in "${FILES[@]}"; do
    download_file "$FILE"
done

echo "All files downloaded and saved in their respective directories"
