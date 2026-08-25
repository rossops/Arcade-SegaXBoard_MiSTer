
# Build TimeStamp Verilog Module
# Jeff Wiencrot - 8/1/2011
# Sorgelig - 02/11/2019
# Git short SHA of HEAD, "*" appended when the tree has local changes.
# Uses git when available, else reads .git/HEAD and the ref file directly.
proc gitShortSha {} {
	set sha ""
	if {![catch {exec git rev-parse --short=7 HEAD} out]} {
		set sha [string trim $out]
		if {![catch {exec git status --porcelain --untracked-files=no} st] && [string trim $st] ne ""} {
			append sha "*"
		}
		return $sha
	}
	if {[file exists ".git/HEAD"]} {
		set f [open ".git/HEAD" r]; set head [string trim [read $f]]; close $f
		if {[regexp {^ref: (.*)$} $head -> ref]} {
			if {[file exists ".git/$ref"]} {
				set f [open ".git/$ref" r]; set sha [string range [string trim [read $f]] 0 6]; close $f
			} elseif {[file exists ".git/packed-refs"]} {
				set f [open ".git/packed-refs" r]
				foreach line [split [read $f] "\n"] {
					if {[regexp "^(\[0-9a-f\]+) $ref\$" $line -> full]} { set sha [string range $full 0 6] }
				}
				close $f
			}
		} else {
			set sha [string range $head 0 6]
		}
	}
	if {$sha eq ""} { set sha "nogit" }
	return $sha
}

proc generateBuildID_Verilog {} {

	# Get the timestamp (see: http://www.altera.com/support/examples/tcl/tcl-date-time-stamp.html)
	set buildDate "`define BUILD_DATE \"[clock format [ clock seconds ] -format %y%m%d]\"\n`define BUILD_GIT \"[gitShortSha]\""

	# Create a Verilog file for output
	set outputFileName "build_id.v"
	
	set fileData ""
	if { [file exists $outputFileName]} {
		set outputFile [open $outputFileName "r"]
		set fileData [read $outputFile]
		close $outputFile	
	}

	if {$buildDate ne $fileData} {
		set outputFile [open $outputFileName "w"]
		puts -nonewline $outputFile $buildDate
		close $outputFile
		# Send confirmation message to the Messages window
		post_message "Generated: [pwd]/$outputFileName: $buildDate"
	}
}

# Build CDF file
# Sorgelig - 17/2/2018
proc generateCDF {revision device outpath} {

	set outputFileName "jtag.cdf"
	set outputFile [open $outputFileName "w"]

	puts $outputFile "JedecChain;"
	puts $outputFile "	FileRevision(JESD32A);"
	puts $outputFile "	DefaultMfr(6E);"
	puts $outputFile ""
	puts $outputFile "	P ActionCode(Ign)"
	puts $outputFile "		Device PartName(SOCVHPS) MfrSpec(OpMask(0));"
	puts $outputFile "	P ActionCode(Cfg)"
	puts $outputFile "		Device PartName($device) Path(\"$outpath/\") File(\"$revision.sof\") MfrSpec(OpMask(1));"
	puts $outputFile "ChainEnd;"
	puts $outputFile ""
	puts $outputFile "AlteraBegin;"
	puts $outputFile "	ChainType(JTAG);"
	puts $outputFile "AlteraEnd;"
}

set project_name [lindex $quartus(args) 1]
set revision [lindex $quartus(args) 2]

if {[project_exists $project_name]} {
    if {[string equal "" $revision]} {
        project_open $project_name -revision [get_current_revision $project_name]
    } else {
        project_open $project_name -revision $revision
    }
} else {
    post_message -type error "Project $project_name does not exist"
    exit
}

set device  [get_global_assignment -name DEVICE]
set outpath [get_global_assignment -name PROJECT_OUTPUT_DIRECTORY]

if [is_project_open] {
    project_close
}

generateBuildID_Verilog
generateCDF $revision $device $outpath
