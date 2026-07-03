#!/bin/bash
VERSION="4052026"

B_CRIT='\e[1;38;5;88m'
B_ERR='\e[1;31m'
B_WARN='\e[1;33m'
B_SUCC='\e[1;32m'

N_CRIT='\e[38;5;88m'
N_ERR='\e[0;31m'
N_WARN='\e[0;33m'
N_SUCC='\e[0;32m'

RESET='\e[0m'

print_success() {
    [ "$SILENT" -eq 1 ] && return
    echo -e "${B_SUCC}[+] Success: ${N_SUCC}$1${RESET}"
}

print_warn() {
    [ "$SILENT" -eq 1 ] && return
    echo -e "${B_WARN}[*] Warning: ${N_WARN}$1${RESET}"
}

print_error() {
    [ "$SILENT" -eq 1 ] && return
    echo -e "${B_ERR}[-] Error: ${N_ERR}$1${RESET}" >&2
}

print_critical() {
    echo -e "${B_CRIT}[!] Critical: ${N_CRIT}$1${RESET}" >&2
    exit 1
}

show_help() {
    cat << EOF
Usage: $0 SRC DEST [FLAGS]

Synchronizes and compares files between SRC (source) and DEST (destination).

Positional arguments:
  SRC           Source directory
  DEST          Destination directory

Flags:
  -o, --overwrite   Overwrite existing files in DEST if hash sums mismatch
  -r, --remove      Remove files from DEST that are missing in SRC
  -h, --hidden      Include hidden files and directories (ignored by default)
  -e, --empty       Disable default empty file/folder behavior
  -s, --silent      Run in silent mode (suppresses all output except critical errors)
  --help            Show this help message and exit
EOF
}

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

OVERWRITE=0
REMOVE=0
HIDDEN=0
EMPTY=0
SILENT=0
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--overwrite) OVERWRITE=1; shift ;;
        -r|--remove) REMOVE=1; shift ;;
        -h|--hidden) HIDDEN=1; shift ;;
        -e|--empty) EMPTY=1; shift ;;
        -s|--silent) SILENT=1; shift ;;
        --help) show_help; exit 0 ;;
        -*)
            show_help
            echo ""
            print_critical "Unknown flag '$1' provided."
            ;;
        *)
            POSITIONAL_ARGS+=("$1"); shift ;;
    esac
done

SRC="${POSITIONAL_ARGS[0]}"
DEST="${POSITIONAL_ARGS[1]}"
if [ -z "$SRC" ] && [ -z "$DEST" ]; then
    show_help
    echo ""
    print_critical "Source and destination directories not specified"
elif [ -z "$SRC" ]; then
    print_critical "Source directory not specified"
elif [ -z "$DEST" ]; then
    print_critical "Destination directory not specified"
fi

SRC="${SRC%/}"
DEST="${DEST%/}"
if [ ! -d "$SRC" ]; then
    print_critical "Source directory '$SRC' does not exist or is not a directory"
fi
if [ ! -d "$DEST" ]; then
    mkdir -p "$DEST" 2>/dev/null || print_critical "Failed to create destination directory '$DEST'"
fi

echo "Pterodactyl Git Clonner (Bash) by Enalian v$VERSION"


get_folder_hash() {
    local dir="$1"
    local hash_tool="md5sum"

    if ! command -v md5sum >/dev/null 2>&1; then
        hash_tool="shasum"
    fi

    if [ "$HIDDEN" -eq 0 ]; then
        (cd "$dir" && find . -mindepth 1 -name ".*" -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 -r $hash_tool 2>/dev/null | $hash_tool | awk '{print $1}')
    else
        (cd "$dir" && find . -mindepth 1 -type f -print0 | LC_ALL=C sort -z | xargs -0 -r $hash_tool 2>/dev/null | $hash_tool | awk '{print $1}')
    fi
}

SRC_HASH=$(get_folder_hash "$SRC")
DEST_HASH=$(get_folder_hash "$DEST")

if [ -n "$SRC_HASH" ] && [ "$SRC_HASH" == "$DEST_HASH" ]; then
    print_success "Source and destination folders have identical hashes. Sync skipped."
    exit 0
fi

get_hash() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q "$1"
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

if [ $HIDDEN -eq 0 ]; then
    FIND_DEST_CMD=(find "$DEST" -mindepth 1 -name ".*" -prune -o -print0)
    FIND_SRC_CMD=(find "$SRC" -mindepth 1 -name ".*" -prune -o -print0)
else
    FIND_DEST_CMD=(find "$DEST" -mindepth 1 -print0)
    FIND_SRC_CMD=(find "$SRC" -mindepth 1 -print0)
fi

while IFS= read -r -d '' dest_file; do
    [ ! -e "$dest_file" ] && continue
    rel_path="${dest_file#$DEST/}"
    src_file="$SRC/$rel_path"

    if [ $EMPTY -eq 0 ]; then
        is_empty=0
        if [ -f "$dest_file" ] && [ ! -s "$dest_file" ]; then is_empty=1; fi
        if [ -d "$dest_file" ] && [ -z "$(ls -A "$dest_file" 2>/dev/null)" ]; then is_empty=1; fi

        if [ $is_empty -eq 1 ]; then
            if rm -rf "$dest_file" 2>/dev/null; then
                print_success "Empty file/folder '$rel_path' found in destination, deletion completed"
            else
                print_error "Error deleting empty file/folder '$rel_path'"
            fi
            continue
        fi
    fi

    if [ ! -e "$src_file" ]; then
        if [ $REMOVE -eq 1 ]; then
            if rm -rf "$dest_file" 2>/dev/null; then
                print_success "File/folder '$rel_path' found in destination, deleted"
            else
                print_error "Error deleting file/folder '$rel_path'"
            fi
        fi
    fi
done < <("${FIND_DEST_CMD[@]}")

while IFS= read -r -d '' src_file; do
    [ ! -e "$src_file" ] && continue
    rel_path="${src_file#$SRC/}"
    dest_file="$DEST/$rel_path"

    if [ $EMPTY -eq 0 ]; then
        is_empty=0
        if [ -f "$src_file" ] && [ ! -s "$src_file" ]; then is_empty=1; fi
        if [ -d "$src_file" ] && [ -z "$(ls -A "$src_file" 2>/dev/null)" ]; then is_empty=1; fi

        if [ $is_empty -eq 1 ]; then
            continue
        fi
    fi

    if [ -d "$src_file" ]; then
        if [ -f "$dest_file" ]; then
            print_error "Path '$rel_path' is a directory in source but a file in destination"
            continue
        fi
        if [ ! -d "$dest_file" ]; then
            mkdir -p "$dest_file" 2>/dev/null || print_error "Error creating directory '$dest_file'"
        fi
        continue
    fi

    if [ ! -r "$src_file" ]; then
        print_error "Read permission denied for source file '$rel_path'"
        continue
    fi

    if [ ! -e "$dest_file" ]; then
        mkdir -p "$(dirname "$dest_file")" 2>/dev/null || print_error "Error creating directory for '$dest_file'"
        if cp -a "$src_file" "$dest_file" 2>/dev/null; then
            print_success "File '$rel_path' copied to destination folder"
        else
            print_error "Error copying file '$rel_path'"
        fi
    else
        if [ ! -r "$dest_file" ]; then
            print_error "Read permission denied for destination file '$rel_path'"
            continue
        fi

        hash_src=$(get_hash "$src_file")
        hash_dest=$(get_hash "$dest_file")

        if [ -z "$hash_src" ] || [ -z "$hash_dest" ]; then
            print_error "Error calculating hash for '$rel_path'"
            continue
        fi

        if [ "$hash_src" != "$hash_dest" ]; then
            if [ $OVERWRITE -eq 1 ]; then
                if cp -a "$src_file" "$dest_file" 2>/dev/null; then
                    print_success "Hashes of '$rel_path' mismatch, destination file overwritten"
                else
                    print_error "Error overwriting file '$rel_path'"
                fi
            fi
        fi
    fi
done < <("${FIND_SRC_CMD[@]}")

if [ $EMPTY -eq 0 ]; then
    while IFS= read -r -d '' check_dir; do
        [ ! -d "$check_dir" ] && continue
        rel_path="${check_dir#$DEST/}"

        if [ -z "$(ls -A "$check_dir" 2>/dev/null)" ]; then
            if rmdir "$check_dir" 2>/dev/null; then
                print_success "Empty directory '$rel_path' removed during final cleanup"
            else
                print_error "Error removing empty directory '$rel_path' during cleanup"
            fi
        fi
    done < <(find "$DEST" -mindepth 1 -type d -print0 | LC_ALL=C sort -rz)
fi