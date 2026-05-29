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

foreach v {LVS_LAYOUT LVS_SCHEM LVS_TOP LVS_SETUP LVS_OUT} {
    if {![info exists env($v)]} {
        puts "ERROR rule=DRIVER message=\"$v not set\""
        quit
    }
}
foreach {v label} {LVS_LAYOUT "layout netlist" LVS_SCHEM "schematic netlist" LVS_SETUP "setup file"} {
    if {![file exists $env($v)]} {
        puts "ERROR rule=DRIVER message=\"$label not found: $env($v)\""
        quit
    }
}

lvs "$env(LVS_LAYOUT) $env(LVS_TOP)" "$env(LVS_SCHEM) $env(LVS_TOP)" \
    $env(LVS_SETUP) $env(LVS_OUT)

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
