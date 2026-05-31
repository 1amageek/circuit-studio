# Headless metal-density driver for the LSI signoff harness.
#
# Foundries require each metal layer's area coverage to sit inside a density
# window: too sparse and CMP dishes the dielectric, too dense and it pulls metal
# thin — both shift the fabricated geometry away from drawn. Magic's
# `cif coverage <LAYER>` reports the true GDS-derived coverage of an output layer,
# so the density measurement rests on the same geometry that ships, not a redraw.
#
# This driver runs `cif coverage` for each requested layer and frames its native
# output with markers the Swift side parses:
#
#   DENSITY_LAYER <CIF_LAYER>
#   ... Magic's "Cell Area = N", "Layer Total Area = M", "Coverage in cell = X%" ...
#   DENSITY_DONE
#
# The density WINDOW (min/max) is policy, applied on the Swift side against the
# measured coverage — the tool measures, the harness judges, one verdict source.
#
# Inputs via environment:
#   DENSITY_CELL    (required) top cell name
#   DENSITY_LAYERS  (required) comma/space separated CIF output layer names (e.g. "MET1,MET2")
#   DENSITY_GDS     (optional) GDS file to read before loading the cell
#
# Run as: magic -dnull -noconsole -rcfile <pdk>.magicrc density.tcl
#
# Failure policy: any driver/tool error emits `ERROR rule=DRIVER` AND exits 1, so
# an aborted run can never be misread as a clean pass.

if {![info exists env(DENSITY_CELL)]} {
    puts "ERROR rule=DRIVER message=\"DENSITY_CELL not set\""
    exit 1
}
if {![info exists env(DENSITY_LAYERS)]} {
    puts "ERROR rule=DRIVER message=\"DENSITY_LAYERS not set\""
    exit 1
}
set cell $env(DENSITY_CELL)
set layers [regexp -all -inline {[^, \t]+} $env(DENSITY_LAYERS)]

if {[info exists env(DENSITY_GDS)] && ![file exists $env(DENSITY_GDS)]} {
    puts "ERROR rule=DRIVER message=\"GDS not found: $env(DENSITY_GDS)\""
    exit 1
}

if {[catch {
    if {[info exists env(DENSITY_GDS)]} {
        gds read $env(DENSITY_GDS)
    }
    load $cell
    select top cell

    lassign [box values] llx lly urx ury
    if {[expr {($urx - $llx) * ($ury - $lly)}] <= 1} {
        error "cell not found or empty: $cell"
    }

    foreach lyr $layers {
        puts "DENSITY_LAYER $lyr"
        cif coverage $lyr
    }
} err]} {
    puts "ERROR rule=DRIVER message=\"$err\""
    exit 1
}

puts "DENSITY_DONE"
quit -noprompt
