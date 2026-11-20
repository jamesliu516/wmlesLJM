#!/usr/bin/env bash
# Build and run the EB_WMLES tests on Linux/WSL (AMReX 26.11, GCC 13, OpenMPI).
#
# Usage:  Tests/EB_WMLES/tools/run_wmles_wsl.sh [ci|full] [2d|3d|both]
#
#   ci    use Exec/*/inputs-ci   (smoke: 10 steps)
#   full  use Exec/*/inputs      (STL_Box: 400 steps, 176x48x48;
#                                 Cylinder: 200 steps, 96x48)
#
# Build directories live in $HOME (amrex-build for 3D, amrex-build-2d for 2D);
# they are configured automatically on first use.  Run this from WSL with the
# repository visible (e.g. /mnt/d/sfw/jamesliu516-wmlesGit).
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$(cd "$HERE/../../.." && pwd)

MODE=${1:-ci}
DIM=${2:-both}
JOBS=${JOBS:-$(nproc)}
INPUTS=inputs-ci; [ "$MODE" = full ] && INPUTS=inputs
RC=0

configure() {
    local dim=$1 bdir=$2
    if [ ! -f "$bdir/CMakeCache.txt" ]; then
        echo "=== configuring $dim-d build in $bdir ==="
        cmake -S "$SRC" -B "$bdir" \
            -DCMAKE_BUILD_TYPE=Release -DAMReX_EB=ON \
            -DAMReX_ENABLE_TESTS=ON -DAMReX_TEST_TYPE=Small \
            -DAMReX_SPACEDIM="$dim" > "$HOME/wmles-configure-$dim.log" 2>&1 \
            || { echo "CONFIGURE FAILED ($dim)"; tail -n 20 "$HOME/wmles-configure-$dim.log"; RC=1; return 1; }
    fi
    return 0
}

run_one() {
    local tag=$1 dim=$2 bdir=$3 tgt=$4 sub=$5
    configure "$dim" "$bdir" || return 1
    echo "=== [$tag] build $tgt ==="
    cmake --build "$bdir" -j "$JOBS" --target "$tgt" > "$HOME/wmles-build-$tag.log" 2>&1 \
        || { echo "BUILD FAILED ($tag)"; tail -n 20 "$HOME/wmles-build-$tag.log"; RC=1; return 1; }
    echo "BUILD OK ($tag)"
    cd "$bdir/Tests/EB_WMLES/$sub" || { RC=1; return 1; }
    ./"$tgt" "$INPUTS" > run.log 2>&1
    local rc=$?
    echo "RUN $tgt $INPUTS -> exit=$rc  $(grep -E 'Run Time total' run.log | tail -1)"
    if [ $rc -ne 0 ]; then echo "--- tail run.log ---"; tail -n 15 run.log; RC=1; fi
    return $rc
}

if [ "$DIM" = 2d ] || [ "$DIM" = both ]; then
    run_one 2d 2 "$HOME/amrex-build-2d" Test_WMLES_Cylinder_2d Cylinder_2d
fi
if [ "$DIM" = 3d ] || [ "$DIM" = both ]; then
    run_one 3d 3 "$HOME/amrex-build" Test_WMLES_STL_Box_3d STL_Box_3d
fi
echo "=== DONE (mode=$MODE dim=$DIM) rc=$RC ==="
exit $RC
