#!/usr/bin/env bash
set -euo pipefail

# Usage: bundle_pdftoppm.sh <AppBundleOrMacOSDir> <PathToSystemPdftoppm>

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <AppBundleOrMacOSDir> <PathToSystemPdftoppm>" >&2
  exit 1
fi

INPUT_PATH="$1"
PDFTOPPM_SRC="$2"

# Derive Contents/MacOS and Contents paths from the input
if [[ -d "$INPUT_PATH/../Resources" ]]; then
  # Input is Contents/MacOS
  MACOS_DIR="$(cd "$INPUT_PATH" && pwd)"
  CONTENTS_DIR="$(cd "$INPUT_PATH/.." && pwd)"
else
  # Input is app bundle or Contents directory
  if [[ -d "$INPUT_PATH/Contents/MacOS" ]]; then
    MACOS_DIR="$(cd "$INPUT_PATH/Contents/MacOS" && pwd)"
    CONTENTS_DIR="$(cd "$INPUT_PATH/Contents" && pwd)"
  elif [[ -d "$INPUT_PATH/MacOS" ]]; then
    MACOS_DIR="$(cd "$INPUT_PATH/MacOS" && pwd)"
    CONTENTS_DIR="$(cd "$INPUT_PATH" && pwd)"
  else
    echo "Error: cannot locate Contents/MacOS under $INPUT_PATH" >&2
    exit 1
  fi
fi

RES_DIR="$CONTENTS_DIR/Resources"
LIB_DIR="$CONTENTS_DIR/lib"

mkdir -p "$RES_DIR" "$LIB_DIR"

DEST_PDFTOPPM="$RES_DIR/pdftoppm"
cp -f "$PDFTOPPM_SRC" "$DEST_PDFTOPPM"
chmod +x "$DEST_PDFTOPPM"

is_system_lib() {
  case "$1" in
    /System/*|/usr/lib/*) return 0 ;;
    *) return 1 ;;
  esac
}

rpaths_of() {
  otool -l "$1" | awk '/LC_RPATH/{getline; getline; if ($1 == "path") print $2}'
}

BASE_RPATHS="$(rpaths_of "$PDFTOPPM_SRC" || true)"

expand_token() {
  local token="$1" base="$2"
  case "$token" in
    @loader_path/*)
      local dir="$(dirname "$base")"
      echo "$dir/${token#@loader_path/}"
      ;;
    @executable_path/*)
      local exe_dir="$(dirname "$PDFTOPPM_SRC")"
      echo "$exe_dir/${token#@executable_path/}"
      ;;
    @rpath/*)
      echo "$token"
      ;;
    *)
      echo "$token"
      ;;
  esac
}

# Keep track of libraries that have been processed using a colon-separated string for portability
processed_libs=":"

# Function to resolve @rpath. It needs the path of the library/binary being processed
# to correctly resolve @loader_path and @executable_path.
resolve_rpath() {
    local binary_path="$1"      # The path of the file whose dependencies we are resolving
    local rpath_dependency="$2" # The dependency string, e.g., "@rpath/libfoo.dylib"
    local dep_name
    dep_name=$(basename "$rpath_dependency")

    # Get rpaths from the binary
    local rpaths
    rpaths=$(otool -l "$binary_path" | awk '/LC_RPATH/{getline; getline; if ($1 == "path") print $2}')

    for rpath in $rpaths; do
        # Substitute @loader_path and @executable_path
        # @loader_path is the directory of the binary_path itself
        # @executable_path is also often the same in the context of libraries from homebrew
        local resolved_rpath
        resolved_rpath=${rpath//\@loader_path/$(dirname "$binary_path")}
        resolved_rpath=${resolved_rpath//\@executable_path/$(dirname "$binary_path")}

        if [[ -f "$resolved_rpath/$dep_name" ]]; then
            echo "$resolved_rpath/$dep_name"
            return
        fi
    done

    # As a fallback, check the directory of the binary itself
    if [[ -f "$(dirname "$binary_path")/$dep_name" ]]; then
        echo "$(dirname "$binary_path")/$dep_name"
        return
    fi
}


process_file() {
  local file_to_process="$1"
  local original_src_path="$2" # The original path of the file before it was copied

  # Get the list of dependencies for the file
  otool -L "$file_to_process" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    if is_system_lib "$dep"; then
      continue
    fi

    local dep_name
    dep_name=$(basename "$dep")
    local dep_src_path="$dep"

    # Resolve @rpath dependencies
    if [[ "$dep" == "@rpath/"* ]]; then
        dep_src_path=$(resolve_rpath "$original_src_path" "$dep")
        if [[ -z "$dep_src_path" || ! -f "$dep_src_path" ]]; then
            echo "Warning: Could not resolve rpath for $dep in $original_src_path" >&2
            continue
        fi
    fi

    # Path for the dependency inside the app bundle
    local dest_lib_path="$LIB_DIR/$dep_name"

    # Change the dependency path in the file being processed
    local new_path
    if [[ "$file_to_process" == "$DEST_PDFTOPPM" ]]; then
        # For the main executable, the path is relative to the executable's location
        new_path="@executable_path/../lib/$dep_name"
    else
        # For libraries, it's relative to the library itself
        new_path="@loader_path/$dep_name"
    fi
    install_name_tool -change "$dep" "$new_path" "$file_to_process"

    # If we've already processed this library, skip it
    if [[ "$processed_libs" == *":$dep_name:"* ]]; then
      continue
    fi

    echo "  bundling $dep_name"
    processed_libs="$processed_libs$dep_name:"

    # Copy the dependency into the lib folder
    cp -f "$dep_src_path" "$dest_lib_path"
    chmod 755 "$dest_lib_path"

    # Fix the id of the copied library so it knows its own new path
    install_name_tool -id "@rpath/$dep_name" "$dest_lib_path"

    # Recursively process the new library
    process_file "$dest_lib_path" "$dep_src_path"
  done
}

echo "Bundling pdftoppm and its dependencies..."

# Start the process with the pdftoppm executable
process_file "$DEST_PDFTOPPM" "$PDFTOPPM_SRC"

# Also, we need to set the rpath for the main executable so it can find the libs in ../lib
install_name_tool -add_rpath "@executable_path/../lib" "$DEST_PDFTOPPM"

echo "Done."
