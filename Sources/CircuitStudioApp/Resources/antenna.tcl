# Headless antenna driver for the LSI signoff harness.
#
# Magic's `antennacheck` extracts the cell, walks every gate, and flags any gate
# whose connected metal area exceeds the techfile's antenna ratio without a
# diode/higher-layer jumper. It registers each violation as a feedback entry and
# prints its own free-text explanation. This script normalizes the result into
# lines the ExternalSignoffReportParser understands:
#
#   ANTENNA_SUMMARY total=<n> cell=<name>
#   VIOLATION rule=antenna count=<n> message="<antennacheck explanation>"
#   ANTENNA_DONE
#
# `feedback count` is the AUTHORITATIVE total (it counts what antennacheck
# registered, independent of how the free text is worded), so the verdict is
# gated by the count, not by parsing the explanation.
#
# Inputs via environment:
#   ANTENNA_CELL  (required) top cell name to check
#   ANTENNA_GDS   (optional) GDS file to read before loading the cell
#
# Run as: magic -dnull -noconsole -rcfile <pdk>.magicrc antenna.tcl
#
# Failure policy: any driver/tool error emits `ERROR rule=DRIVER` AND exits 1.
# Magic exits 0 on an uncaught Tcl error, so without the catch below an aborted
# run would print nothing and be misread as a clean pass — hence the explicit
# guard. A completed run (with or without violations) exits 0.

if {![info exists env(ANTENNA_CELL)]} {
    puts "ERROR rule=DRIVER message=\"ANTENNA_CELL not set\""
    exit 1
}
set cell $env(ANTENNA_CELL)

if {[info exists env(ANTENNA_GDS)] && ![file exists $env(ANTENNA_GDS)]} {
    puts "ERROR rule=DRIVER message=\"GDS not found: $env(ANTENNA_GDS)\""
    exit 1
}

if {[catch {
    if {[info exists env(ANTENNA_GDS)]} {
        gds read $env(ANTENNA_GDS)
    }
    load $cell
    select top cell

    # Fail loudly if the cell did not actually load (empty 1x1 placeholder).
    lassign [box values] llx lly urx ury
    if {[expr {($urx - $llx) * ($ury - $lly)}] <= 1} {
        error "cell not found or empty: $cell"
    }

    # antennacheck reads an extract file; without a fresh extraction it sees no
    # connectivity and reports nothing (a silent false pass). Extract first so the
    # gate<->metal nets are real.
    extract do local
    extract all

    feedback clear
    antennacheck
    set total [feedback count]
    puts "ANTENNA_SUMMARY total=$total cell=$cell"
    if {$total > 0} {
        puts "VIOLATION rule=antenna count=$total message=\"antennacheck reported $total antenna violation(s) on gate-connected metal\""
    }
} err]} {
    puts "ERROR rule=DRIVER message=\"$err\""
    exit 1
}

puts "ANTENNA_DONE"
quit -noprompt
