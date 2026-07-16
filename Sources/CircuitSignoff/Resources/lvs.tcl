# Headless LVS driver for the LSI signoff harness.
#
# Netgen writes its full "Final result:" only to the comparison report file, not
# stdout, so this script runs the comparison, reads that file, and emits a single
# normalized line the ExternalSignoffReportParser understands:
#
#   LVS_RESULT status=match message="..."          (clean, unique match)
#   MISMATCH rule=LVS_MISMATCH message="..."        (anything else)
#   ERROR rule=DRIVER message="..."                 (driver/input failure)
#
# Inputs via environment: LVS_LAYOUT, LVS_SCHEM, LVS_TOP, LVS_SETUP, LVS_OUT
# Run as: netgen -batch source lvs.tcl
#
# Failure policy: a driver/tool error emits `ERROR rule=DRIVER` AND exits 1
# (Netgen exits 0 on an uncaught Tcl error, so the catch below is what prevents an
# aborted comparison from being misread as a clean pass). A completed comparison
# exits 0; a non-matching result is reported via the MISMATCH diagnostic.

foreach v {LVS_LAYOUT LVS_SCHEM LVS_TOP LVS_SETUP LVS_OUT} {
    if {![info exists env($v)]} {
        puts "ERROR rule=DRIVER message=\"$v not set\""
        exit 1
    }
}
foreach {v label} {LVS_LAYOUT "layout netlist" LVS_SCHEM "schematic netlist" LVS_SETUP "setup file"} {
    if {![file exists $env($v)]} {
        puts "ERROR rule=DRIVER message=\"$label not found: $env($v)\""
        exit 1
    }
}

if {[catch {
    lvs "$env(LVS_LAYOUT) $env(LVS_TOP)" "$env(LVS_SCHEM) $env(LVS_TOP)" \
        $env(LVS_SETUP) $env(LVS_OUT)
} err]} {
    puts "ERROR rule=DRIVER message=\"lvs failed: $err\""
    exit 1
}

set result "no final result in report"
if {[file exists $env(LVS_OUT)]} {
    set fp [open $env(LVS_OUT) r]
    set data [read $fp]
    close $fp
    foreach line [split $data "\n"] {
        if {[regexp {Final result:\s*(.+)} $line -> matched]} {
            set result [string trim $matched]
        }
    }
}

# Strict signoff: only a unique match passes; warnings/property errors fail loud.
if {[string match -nocase "*match uniquely*" $result]} {
    puts "LVS_RESULT status=match message=\"$result\""
} else {
    puts "MISMATCH rule=LVS_MISMATCH message=\"$result\""
}
puts "LVS_DONE"
quit
