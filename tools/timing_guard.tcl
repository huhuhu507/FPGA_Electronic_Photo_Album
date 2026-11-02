# Check EVERY reported clock group before making or programming a bitstream.
set timing_file [open reports/timing.rpt r]
set timing_text [read $timing_file]
close $timing_file
if {![regexp {0 errors detected} $timing_text]} {
    error "No timing summary found. Build/programming stopped."
}
if {[regexp {[1-9][0-9]* errors detected} $timing_text]} {
    error "Timing violations remain in one or more clock groups. Build/programming stopped."
}
puts "PASS: all timing report clock-group summaries contain zero errors."
