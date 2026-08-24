derive_pll_clocks
derive_clock_uncertainty

# OSD counters that the vendored sys_top.sdc does not relax (s32 finding).
set_multicycle_path -to {*_osd|pixcnt*} -setup 2
set_multicycle_path -to {*_osd|pixcnt*} -hold 1
set_multicycle_path -to {*_osd|multiscan*} -setup 2
set_multicycle_path -to {*_osd|multiscan*} -hold 1

# Objects below only exist after fit; warn during quartus_map, fail in STA.
proc xb_require {present what} {
    if {$present} { return 1 }
    if {[string match "quartus_map" $::quartus(nameofexecutable)]} {
        post_message -type warning "xb SDC: $what not elaborated yet; deferring to fit/STA"
        return 0
    }
    error "xb SDC: expected $what but it is missing at $::quartus(nameofexecutable)"
}

#**************************************************************
# SDRAM: CL2 @ 100 MHz, SDRAM_CLK forwarded at 180 degrees
#**************************************************************
set sdram_fwd_pin [get_pins -nowarn -compatibility_mode {*|pll|pll_inst|altera_pll_i|*[2].*|divclk}]
set sdram_mem_clk [get_clocks -nowarn {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}]

if {[xb_require [expr {[get_collection_size $sdram_fwd_pin] == 1 && \
                       [get_collection_size $sdram_mem_clk] == 1}] \
        "exactly one PLL outclk2 pin and outclk0 clock for the SDRAM bus"]} {

create_generated_clock -name SDRAM_CLK -source $sdram_fwd_pin [get_ports SDRAM_CLK]

# board + chip delays (typical MiSTer SDRAM module, -7 grade)
set_input_delay  -clock SDRAM_CLK -max 6.4 [get_ports SDRAM_DQ[*]]
set_input_delay  -clock SDRAM_CLK -min 3.2 [get_ports SDRAM_DQ[*]]
set_output_delay -clock SDRAM_CLK -max 1.5 \
    [get_ports {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQML SDRAM_DQMH \
                SDRAM_nCS SDRAM_nCAS SDRAM_nRAS SDRAM_nWE SDRAM_CKE}]
set_output_delay -clock SDRAM_CLK -min -0.8 \
    [get_ports {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQML SDRAM_DQMH \
                SDRAM_nCS SDRAM_nCAS SDRAM_nRAS SDRAM_nWE SDRAM_CKE}]
set_multicycle_path -setup -end -from [get_clocks SDRAM_CLK] -to $sdram_mem_clk 2
set_multicycle_path -hold  -end -from [get_clocks SDRAM_CLK] -to $sdram_mem_clk 1

}

# The reserved 16 MHz PLL output (outclk3) drives nothing; keep STA quiet.
set snd_clk [get_clocks -nowarn {*|pll|pll_inst|altera_pll_i|*[3].*|divclk}]
if {[get_collection_size $snd_clk] > 0} {
    set_false_path -from $snd_clk
    set_false_path -to   $snd_clk
}
