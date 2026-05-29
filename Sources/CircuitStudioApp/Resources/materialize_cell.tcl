# Materializes a real PDK cell (or composed block) layout to GDS via Magic, so the
# flow can sign off a design referenced by cell name instead of a hand-supplied
# GDS. Emits MAT_DONE on success and MAT_ERROR + exit 1 on any failure.
#
# Inputs via environment:
#   MAT_CELL  (required) cell name to load from the PDK search path
#   MAT_OUT   (required) output GDS path
# Run as: magic -dnull -noconsole -rcfile <pdk>.magicrc materialize_cell.tcl

if {![info exists env(MAT_CELL)]} { puts "MAT_ERROR MAT_CELL not set"; exit 1 }
if {![info exists env(MAT_OUT)]}  { puts "MAT_ERROR MAT_OUT not set";  exit 1 }

if {[catch {
    load $env(MAT_CELL)
    select top cell
    lassign [box values] llx lly urx ury
    if {[expr {($urx - $llx) * ($ury - $lly)}] <= 1} {
        error "cell not found or empty: $env(MAT_CELL)"
    }
    gds write $env(MAT_OUT)
} err]} {
    puts "MAT_ERROR $err"
    exit 1
}

puts "MAT_DONE"
quit -noprompt
