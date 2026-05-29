# Headless layout-netlist extractor for the LSI signoff harness (LVS input).
#
# Runs Magic's LVS-mode extraction (device-level netlist, no parasitics) so
# Netgen can compare the layout against the schematic. Emits EXT_DONE on success
# and EXT_ERROR + exit 1 on any failure (Magic exits 0 on an uncaught Tcl error,
# so the catch below is what makes a failed extraction fail loud).
#
# Inputs via environment:
#   EXT_CELL  (required) top cell to extract
#   EXT_OUT   (required) output SPICE netlist path
#   EXT_GDS   (optional) GDS to read before loading the cell
# Run as: magic -dnull -noconsole -rcfile <pdk>.magicrc extract_lvs.tcl

if {![info exists env(EXT_CELL)]} { puts "EXT_ERROR EXT_CELL not set"; exit 1 }
if {![info exists env(EXT_OUT)]}  { puts "EXT_ERROR EXT_OUT not set";  exit 1 }
if {[info exists env(EXT_GDS)] && ![file exists $env(EXT_GDS)]} {
    puts "EXT_ERROR gds not found: $env(EXT_GDS)"
    exit 1
}

if {[catch {
    if {[info exists env(EXT_GDS)]} { gds read $env(EXT_GDS) }
    load $env(EXT_CELL)
    select top cell
    lassign [box values] llx lly urx ury
    if {[expr {($urx - $llx) * ($ury - $lly)}] <= 1} {
        error "cell not found or empty: $env(EXT_CELL)"
    }
    extract do local
    extract all
    ext2spice lvs
    ext2spice -o $env(EXT_OUT)
} err]} {
    puts "EXT_ERROR $err"
    exit 1
}

puts "EXT_DONE"
quit -noprompt
