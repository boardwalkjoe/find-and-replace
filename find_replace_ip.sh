#!/bin/bash

# DNS Name Find and Replace Script
# Searches through files in a directory and replaces DNS names

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Default values
DRY_RUN=false
RECURSIVE=true
EXTENSIONS=""
EXCLUDE_DIRS=".git .svn __pycache__ node_modules .DS_Store"
BACKUP=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] DIRECTORY OLD_VALUE NEW_VALUE

Find and replace DNS names or IP addresses in files within a directory.

ARGUMENTS:
    DIRECTORY    Directory to search
    OLD_VALUE    DNS name or IP address to replace
    NEW_VALUE    New DNS name or IP address

OPTIONS:
    -d, --dry-run        Show what would be changed without making changes
    -r, --recursive      Search subdirectories recursively (default: true)
    -n, --no-recursive   Do not search subdirectories
    -e, --extensions     Comma-separated list of file extensions to include
                        (e.g., "txt,conf,py")
    -x, --exclude        Comma-separated list of directories to exclude
                        (default: ".git,.svn,__pycache__,node_modules,.DS_Store")
    -b, --backup         Create backup files with .bak extension
    -h, --help          Show this help message

EXAMPLES:
    $0 /etc/nginx old.example.com new.example.com --dry-run
    $0 /var/www 192.168.1.100 10.0.0.50 --extensions "conf,txt,html"
    $0 . old.example.com 192.168.1.200 --backup --no-recursive
    $0 /etc 10.0.0.1 new-server.local --exclude "backup,temp"

EOF
}

# Function to log messages
log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" >&2 ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
    esac
}

# Function to check if a file is likely a text file
is_text_file() {
    local file="$1"
    
    # Check if file is readable
    [[ -r "$file" ]] || return 1
    
    # Use file command to check if it's text
    if command -v file >/dev/null 2>&1; then
        file -b --mime-type "$file" | grep -q "^text/" && return 0
    fi
    
    # Fallback: check for null bytes in first 1024 bytes
    if head -c 1024 "$file" | grep -q $'\0'; then
        return 1
    fi
    
    return 0
}

# Function to validate IP address format
validate_ip() {
    local ip="$1"
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}

# Function to check if file extension should be included
should_include_file() {
    local file="$1"
    
    # If no extensions specified, include all files
    [[ -z "$EXTENSIONS" ]] && return 0
    
    local ext="${file##*.}"
    [[ "$ext" == "$file" ]] && ext=""  # No extension
    
    # Convert EXTENSIONS to array and check
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for allowed_ext in "${EXT_ARRAY[@]}"; do
        # Remove leading dot if present
        allowed_ext="${allowed_ext#.}"
        if [[ "$ext" == "$allowed_ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to replace DNS/IP in a single file
replace_dns_in_file() {
    local file="$1"
    local old_value="$2"
    local new_value="$3"
    local count=0
    
    # Check if file contains the old value
    if ! grep -q "$old_value" "$file" 2>/dev/null; then
        return 0
    fi
    
    # Count occurrences
    count=$(grep -o "$old_value" "$file" 2>/dev/null | wc -l)
    
    if [[ $DRY_RUN == true ]]; then
        echo "[DRY RUN] Would replace $count occurrence(s) in: $file"
    else
        # Create backup if requested
        if [[ $BACKUP == true ]]; then
            cp "$file" "$file.bak"
        fi
        
        # Perform replacement using sed
        if sed -i.tmp "s/$old_value/$new_value/g" "$file" 2>/dev/null; then
            rm -f "$file.tmp"
            echo "Replaced $count occurrence(s) in: $file"
        else
            log "ERROR" "Failed to replace in: $file"
            [[ -f "$file.tmp" ]] && mv "$file.tmp" "$file"  # Restore original
            return 1
        fi
    fi
    
    return $count
}

# Function to find files and replace DNS names or IP addresses
find_and_replace() {
    local directory="$1"
    local old_value="$2"
    local new_value="$3"
    local total_files=0
    local total_replacements=0
    local find_args=()
    
    # Build find command arguments
    find_args+=("$directory")
    
    if [[ $RECURSIVE == false ]]; then
        find_args+=("-maxdepth" "1")
    fi
    
    find_args+=("-type" "f")
    
    # Add exclusions for directories
    for exclude in $EXCLUDE_DIRS; do
        find_args+=("!" "-path" "*/$exclude/*")
    done
    
    log "INFO" "${DRY_RUN:+DRY RUN: }Searching for '$old_value' to replace with '$new_value'"
    log "INFO" "Directory: $directory"
    echo "----------------------------------------"
    
    # Process files
    while IFS= read -r -d '' file; do
        # Check if we should include this file based on extension
        if ! should_include_file "$file"; then
            continue
        fi
        
        # Skip if not a text file
        if ! is_text_file "$file"; then
            continue
        fi
        
        # Replace value in file
        if replace_dns_in_file "$file" "$old_value" "$new_value"; then
            local count=$?
            if [[ $count -gt 0 ]]; then
                ((total_files++))
                ((total_replacements += count))
            fi
        fi
        
    done < <(find "${find_args[@]}" -print0 2>/dev/null)
    
    # Summary
    echo "----------------------------------------"
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "DRY RUN SUMMARY:"
        log "INFO" "Would modify $total_files files"
        log "INFO" "Would make $total_replacements total replacements"
    else
        log "SUCCESS" "SUMMARY:"
        log "SUCCESS" "Modified $total_files files"
        log "SUCCESS" "Made $total_replacements total replacements"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -n|--no-recursive)
            RECURSIVE=false
            shift
            ;;
        -e|--extensions)
            EXTENSIONS="$2"
            shift 2
            ;;
        -x|--exclude)
            EXCLUDE_DIRS="${2//,/ }"
            shift 2
            ;;
        -b|--backup)
            BACKUP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check if we have the required arguments
if [[ $# -lt 3 ]]; then
    log "ERROR" "Missing required arguments"
    usage
    exit 1
fi

DIRECTORY="$1"
OLD_DNS="$2"
NEW_DNS="$3"

# Validate inputs
if [[ ! -d "$DIRECTORY" ]]; then
    log "ERROR" "Directory '$DIRECTORY' does not exist"
    exit 1
fi

# Basic DNS validation
validate_dns "$OLD_DNS" || log "WARN" "Old DNS name may not be valid"
validate_dns "$NEW_DNS" || log "WARN" "New DNS name may not be valid"

# Confirm operation if not dry run
if [[ $DRY_RUN == false ]]; then
    echo -n "Replace '$OLD_DNS' with '$NEW_DNS' in $DIRECTORY? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled"
        exit 0
    fi
fi

# Perform the operation
find_and_replace "$DIRECTORY" "$OLD_DNS" "$NEW_DNS"

    
    if [[ $ip =~ $ip_regex ]]; then
        # Check each octet is <= 255
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Function to validate DNS name format (basic)
validate_dns() {
    local dns="$1"
    local dns_regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*

# Function to check if directory should be excluded
is_excluded_dir() {
    local dir="$1"
    local basename_dir=$(basename "$dir")
    
    for exclude in $EXCLUDE_DIRS; do
        if [[ "$basename_dir" == "$exclude" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if file extension should be included
should_include_file() {
    local file="$1"
    
    # If no extensions specified, include all files
    [[ -z "$EXTENSIONS" ]] && return 0
    
    local ext="${file##*.}"
    [[ "$ext" == "$file" ]] && ext=""  # No extension
    
    # Convert EXTENSIONS to array and check
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for allowed_ext in "${EXT_ARRAY[@]}"; do
        # Remove leading dot if present
        allowed_ext="${allowed_ext#.}"
        if [[ "$ext" == "$allowed_ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to replace DNS in a single file
replace_dns_in_file() {
    local file="$1"
    local old_dns="$2"
    local new_dns="$3"
    local count=0
    
    # Check if file contains the old DNS name
    if ! grep -q "$old_dns" "$file" 2>/dev/null; then
        return 0
    fi
    
    # Count occurrences
    count=$(grep -o "$old_dns" "$file" 2>/dev/null | wc -l)
    
    if [[ $DRY_RUN == true ]]; then
        echo "[DRY RUN] Would replace $count occurrence(s) in: $file"
    else
        # Create backup if requested
        if [[ $BACKUP == true ]]; then
            cp "$file" "$file.bak"
        fi
        
        # Perform replacement using sed
        if sed -i.tmp "s/$old_dns/$new_dns/g" "$file" 2>/dev/null; then
            rm -f "$file.tmp"
            echo "Replaced $count occurrence(s) in: $file"
        else
            log "ERROR" "Failed to replace in: $file"
            [[ -f "$file.tmp" ]] && mv "$file.tmp" "$file"  # Restore original
            return 1
        fi
    fi
    
    return $count
}

# Function to find files and replace DNS names
find_and_replace() {
    local directory="$1"
    local old_dns="$2"
    local new_dns="$3"
    local total_files=0
    local total_replacements=0
    local find_args=()
    
    # Build find command arguments
    find_args+=("$directory")
    
    if [[ $RECURSIVE == false ]]; then
        find_args+=("-maxdepth" "1")
    fi
    
    find_args+=("-type" "f")
    
    # Add exclusions for directories
    for exclude in $EXCLUDE_DIRS; do
        find_args+=("!" "-path" "*/$exclude/*")
    done
    
    log "INFO" "${DRY_RUN:+DRY RUN: }Searching for '$old_dns' to replace with '$new_dns'"
    log "INFO" "Directory: $directory"
    echo "----------------------------------------"
    
    # Process files
    while IFS= read -r -d '' file; do
        # Check if we should include this file based on extension
        if ! should_include_file "$file"; then
            continue
        fi
        
        # Skip if not a text file
        if ! is_text_file "$file"; then
            continue
        fi
        
        # Replace DNS in file
        if replace_dns_in_file "$file" "$old_dns" "$new_dns"; then
            local count=$?
            if [[ $count -gt 0 ]]; then
                ((total_files++))
                ((total_replacements += count))
            fi
        fi
        
    done < <(find "${find_args[@]}" -print0 2>/dev/null)
    
    # Summary
    echo "----------------------------------------"
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "DRY RUN SUMMARY:"
        log "INFO" "Would modify $total_files files"
        log "INFO" "Would make $total_replacements total replacements"
    else
        log "SUCCESS" "SUMMARY:"
        log "SUCCESS" "Modified $total_files files"
        log "SUCCESS" "Made $total_replacements total replacements"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -n|--no-recursive)
            RECURSIVE=false
            shift
            ;;
        -e|--extensions)
            EXTENSIONS="$2"
            shift 2
            ;;
        -x|--exclude)
            EXCLUDE_DIRS="${2//,/ }"
            shift 2
            ;;
        -b|--backup)
            BACKUP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check if we have the required arguments
if [[ $# -lt 3 ]]; then
    log "ERROR" "Missing required arguments"
    usage
    exit 1
fi

DIRECTORY="$1"
OLD_DNS="$2"
NEW_DNS="$3"

# Validate inputs
if [[ ! -d "$DIRECTORY" ]]; then
    log "ERROR" "Directory '$DIRECTORY' does not exist"
    exit 1
fi

# Basic DNS validation
validate_dns "$OLD_DNS" || log "WARN" "Old DNS name may not be valid"
validate_dns "$NEW_DNS" || log "WARN" "New DNS name may not be valid"

# Confirm operation if not dry run
if [[ $DRY_RUN == false ]]; then
    echo -n "Replace '$OLD_DNS' with '$NEW_DNS' in $DIRECTORY? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled"
        exit 0
    fi
fi

# Perform the operation
find_and_replace "$DIRECTORY" "$OLD_DNS" "$NEW_DNS"

    
    if [[ $dns =~ $dns_regex ]]; then
        return 0
    fi
    return 1
}

# Function to validate input (DNS name or IP address)
validate_input() {
    local input="$1"
    local type="$2"
    
    if validate_ip "$input"; then
        log "INFO" "$type appears to be an IP address: $input"
        return 0
    elif validate_dns "$input"; then
        log "INFO" "$type appears to be a DNS name: $input"
        return 0
    else
        log "WARN" "$type '$input' doesn't appear to be a valid DNS name or IP address"
        return 1
    fi
}

# Function to check if directory should be excluded
is_excluded_dir() {
    local dir="$1"
    local basename_dir=$(basename "$dir")
    
    for exclude in $EXCLUDE_DIRS; do
        if [[ "$basename_dir" == "$exclude" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if file extension should be included
should_include_file() {
    local file="$1"
    
    # If no extensions specified, include all files
    [[ -z "$EXTENSIONS" ]] && return 0
    
    local ext="${file##*.}"
    [[ "$ext" == "$file" ]] && ext=""  # No extension
    
    # Convert EXTENSIONS to array and check
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for allowed_ext in "${EXT_ARRAY[@]}"; do
        # Remove leading dot if present
        allowed_ext="${allowed_ext#.}"
        if [[ "$ext" == "$allowed_ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to replace DNS in a single file
replace_dns_in_file() {
    local file="$1"
    local old_dns="$2"
    local new_dns="$3"
    local count=0
    
    # Check if file contains the old DNS name
    if ! grep -q "$old_dns" "$file" 2>/dev/null; then
        return 0
    fi
    
    # Count occurrences
    count=$(grep -o "$old_dns" "$file" 2>/dev/null | wc -l)
    
    if [[ $DRY_RUN == true ]]; then
        echo "[DRY RUN] Would replace $count occurrence(s) in: $file"
    else
        # Create backup if requested
        if [[ $BACKUP == true ]]; then
            cp "$file" "$file.bak"
        fi
        
        # Perform replacement using sed
        if sed -i.tmp "s/$old_dns/$new_dns/g" "$file" 2>/dev/null; then
            rm -f "$file.tmp"
            echo "Replaced $count occurrence(s) in: $file"
        else
            log "ERROR" "Failed to replace in: $file"
            [[ -f "$file.tmp" ]] && mv "$file.tmp" "$file"  # Restore original
            return 1
        fi
    fi
    
    return $count
}

# Function to find files and replace DNS names
find_and_replace() {
    local directory="$1"
    local old_dns="$2"
    local new_dns="$3"
    local total_files=0
    local total_replacements=0
    local find_args=()
    
    # Build find command arguments
    find_args+=("$directory")
    
    if [[ $RECURSIVE == false ]]; then
        find_args+=("-maxdepth" "1")
    fi
    
    find_args+=("-type" "f")
    
    # Add exclusions for directories
    for exclude in $EXCLUDE_DIRS; do
        find_args+=("!" "-path" "*/$exclude/*")
    done
    
    log "INFO" "${DRY_RUN:+DRY RUN: }Searching for '$old_dns' to replace with '$new_dns'"
    log "INFO" "Directory: $directory"
    echo "----------------------------------------"
    
    # Process files
    while IFS= read -r -d '' file; do
        # Check if we should include this file based on extension
        if ! should_include_file "$file"; then
            continue
        fi
        
        # Skip if not a text file
        if ! is_text_file "$file"; then
            continue
        fi
        
        # Replace DNS in file
        if replace_dns_in_file "$file" "$old_dns" "$new_dns"; then
            local count=$?
            if [[ $count -gt 0 ]]; then
                ((total_files++))
                ((total_replacements += count))
            fi
        fi
        
    done < <(find "${find_args[@]}" -print0 2>/dev/null)
    
    # Summary
    echo "----------------------------------------"
    if [[ $DRY_RUN == true ]]; then
        log "INFO" "DRY RUN SUMMARY:"
        log "INFO" "Would modify $total_files files"
        log "INFO" "Would make $total_replacements total replacements"
    else
        log "SUCCESS" "SUMMARY:"
        log "SUCCESS" "Modified $total_files files"
        log "SUCCESS" "Made $total_replacements total replacements"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -n|--no-recursive)
            RECURSIVE=false
            shift
            ;;
        -e|--extensions)
            EXTENSIONS="$2"
            shift 2
            ;;
        -x|--exclude)
            EXCLUDE_DIRS="${2//,/ }"
            shift 2
            ;;
        -b|--backup)
            BACKUP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check if we have the required arguments
if [[ $# -lt 3 ]]; then
    log "ERROR" "Missing required arguments"
    usage
    exit 1
fi

DIRECTORY="$1"
OLD_DNS="$2"
NEW_DNS="$3"

# Validate inputs
if [[ ! -d "$DIRECTORY" ]]; then
    log "ERROR" "Directory '$DIRECTORY' does not exist"
    exit 1
fi

# Basic DNS validation
validate_dns "$OLD_DNS" || log "WARN" "Old DNS name may not be valid"
validate_dns "$NEW_DNS" || log "WARN" "New DNS name may not be valid"

# Confirm operation if not dry run
if [[ $DRY_RUN == false ]]; then
    echo -n "Replace '$OLD_DNS' with '$NEW_DNS' in $DIRECTORY? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled"
        exit 0
    fi
fi

# Perform the operation
find_and_replace "$DIRECTORY" "$OLD_DNS" "$NEW_DNS"
