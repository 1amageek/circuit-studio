# Headless DRC driver for the LSI signoff harness.
#
# Magic emits free-text DRC explanations (e.g. "Metal1 spacing < 0.14um
# (met1.2)") that carry no severity keyword, so this script normalizes them into
# lines the ExternalSignoffReportParser understands:
#
#   DRC_SUMMARY total=<n> cell=<name>
#   VIOLATION rule=<code> count=<n> message="<full rule text>"
#   DRC_DONE
#
# Inputs are passed via environment variables:
#   DRC_CELL  (required) top cell name to check
#   DRC_GDS   (optional) GDS file to read before loading the cell
#
# Run as: magic -dnull -noconsole -rcfile <pdk>.magicrc drc.tcl
#
# Failure policy: any driver/tool error emits `ERROR rule=DRIVER` AND exits 1.
# Magic exits 0 on an uncaught Tcl error, so without the catch below an aborted
# run would print nothing and be misread as a clean pass — hence the explicit
# guard. A completed run (with or without violations) exits 0.

if {![info exists env(DRC_CELL)]} {
    puts "ERROR rule=DRIVER message=\"DRC_CELL not set\""
    exit 1
}
set cell $env(DRC_CELL)

if {[info exists env(DRC_GDS)] && ![file exists $env(DRC_GDS)]} {
    puts "ERROR rule=DRIVER message=\"GDS not found: $env(DRC_GDS)\""
    exit 1
}

if {[catch {
    if {[info exists env(DRC_GDS)]} {
        gds read $env(DRC_GDS)
    }
    load $cell
    select top cell

    # Fail loudly if the cell did not actually load. A missing cell (absent from
    # the PDK search path or not present in the GDS) leaves Magic with an empty
    # 1x1 placeholder; reporting that as a clean DRC would be a silent false pass.
    lassign [box values] llx lly urx ury
    if {[expr {($urx - $llx) * ($ury - $lly)}] <= 1} {
        error "cell not found or empty: $cell"
    }

    drc check
    drc catchup
    set total [drc list count total]
    puts "DRC_SUMMARY total=$total cell=$cell"

    foreach {rule coords} [drc listall why] {
        set code "unknown"
        regexp {\(([^)]+)\)\s*$} $rule -> code
        set n [llength $coords]
        puts "VIOLATION rule=$code count=$n message=\"$rule\""
    }
} err]} {
    puts "ERROR rule=DRIVER message=\"$err\""
    exit 1
}

puts "DRC_DONE"
quit -noprompt
