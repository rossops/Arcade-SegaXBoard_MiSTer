# Report the worst setup/hold paths per clock to output_files/sta_paths.txt
# so they can be read on the Mac. Run by build.bat after the normal flow:
#   quartus_sta -t tools/sta_paths.tcl Arcade-SegaXBoard
set prj [lindex $quartus(args) 0]
project_open $prj
create_timing_netlist
read_sdc
update_timing_netlist
set fh [open "output_files/sta_paths.txt" w]
foreach_in_collection c [get_clocks] {
    set clk [get_clock_info -name $c]
    puts $fh "==== setup, clock: $clk"
    foreach_in_collection p [get_timing_paths -to_clock $c -npaths 6 -setup] {
        set from [get_node_info -name [get_path_info -from $p]]
        set to   [get_node_info -name [get_path_info -to $p]]
        puts $fh [format "slack %.3f  levels %s  from %s  to %s" \
            [get_path_info -slack $p] [get_path_info -num_logic_levels $p] $from $to]
    }
}
puts $fh "==== worst hold (all clocks)"
foreach_in_collection p [get_timing_paths -npaths 5 -hold] {
    puts $fh [format "slack %.3f  from %s  to %s" [get_path_info -slack $p] \
        [get_node_info -name [get_path_info -from $p]] [get_node_info -name [get_path_info -to $p]]]
}
close $fh
project_close
