#!/bin/bash
# azul — Xcode Cloud pre-build script
# Installs pinned dependency versions from Homebrew and populates include/

set -euo pipefail
export HOMEBREW_NO_AUTO_UPDATE=1

# Pinned versions matching the vendored headers and prebuilt libs
PINNED_BOOST="1.90.0"
PINNED_CGAL="6.1.1"
PINNED_GMP="6.3.0"
PINNED_MPFR="4.2.2"
PINNED_PUGIXML="1.15"

echo "azul CI: installing Homebrew dependencies..."

brew install boost cgal gmp mpfr pugixml

echo ""
echo "azul CI: verifying versions..."

check_version() {
    local formula=$1
    local expected=$2
    local actual=$(brew info "$formula" --json=v2 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['formulae'][0]['versions']['stable'])")
    if [ "$actual" = "$expected" ]; then
        echo "  ✓ $formula $actual (matches)"
    else
        echo "  ! $formula $actual (expected $expected)"
    fi
}

check_version "boost" "$PINNED_BOOST"
check_version "cgal" "$PINNED_CGAL"
check_version "gmp" "$PINNED_GMP"
check_version "mpfr" "$PINNED_MPFR"
check_version "pugixml" "$PINNED_PUGIXML"

echo ""
echo "azul CI: populating include/ from Homebrew..."

INCLUDE_DIR="${CI_PRIMARY_REPOSITORY_PATH}/include"
mkdir -p "$INCLUDE_DIR"

# Copy Boost (header-only libraries used: spirit, algorithm/predicate)
copy_header_dir() {
    local src="$1"
    local dst="$2"
    if [ -e "$src" ]; then
        cp -RfL "$src" "$dst"
        echo "  ✓ $(basename $src)"
    else
        echo "  ✗ $src not found"
    fi
}

copy_header_file() {
    local src="$1"
    local dst="$2"
    if [ -e "$src" ]; then
        cp -fL "$src" "$dst"
        echo "  ✓ $(basename $src)"
    else
        echo "  ✗ $src not found"
    fi
}

BREW_PREFIX=$(brew --prefix)

copy_header_dir  "$BREW_PREFIX/include/boost"   "$INCLUDE_DIR/"
copy_header_dir  "$BREW_PREFIX/include/CGAL"    "$INCLUDE_DIR/"
copy_header_file "$BREW_PREFIX/include/gmp.h"   "$INCLUDE_DIR/"
copy_header_file "$BREW_PREFIX/include/gmpxx.h" "$INCLUDE_DIR/"
copy_header_file "$BREW_PREFIX/include/mpfr.h"  "$INCLUDE_DIR/"
copy_header_file "$BREW_PREFIX/include/pugixml.hpp"   "$INCLUDE_DIR/"
copy_header_file "$BREW_PREFIX/include/pugiconfig.hpp" "$INCLUDE_DIR/"

echo ""
echo "azul CI: verifying copied files..."
if [ -f "$INCLUDE_DIR/boost/algorithm/string/predicate.hpp" ]; then
    echo "  ✓ boost/algorithm/string/predicate.hpp exists"
else
    echo "  ✗ boost/algorithm/string/predicate.hpp MISSING — copy failed"
fi
echo ""
echo "azul CI: done"
