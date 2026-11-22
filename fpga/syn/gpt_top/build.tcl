# build.tcl
#   gpt_top build: synthesis, map, place-and-route and bitstream for the
#   iCE40UP5K at a 48 MHz core clock, with fpga/constraints/gpt_top.pdc.
#   The vector registers and text buffer are preloaded from
#   bringup_vreg.mem and bringup_text.mem (python tools/make_bringup.py)
#   for the MCU bring-up test. Run from any directory with
#     radiantc fpga/syn/gpt_top/build.tcl
#   Results (not committed) are in build/impl_1/:
#     gpt_top_impl_1.bin  bitstream to program
#     gpt_top_impl_1.mrp  resource usage (8 DSP, 4 SPRAM expected)
#     gpt_top_impl_1.twr  timing report
#   The memory images in fpga/mem are copied next to the project so
#   $readmemh finds them.

set here [file dirname [file normalize [info script]]]
set rtl  [file normalize [file join $here .. .. rtl]]
set mem  [file normalize [file join $here .. .. mem]]
set pdc  [file normalize [file join $here .. .. constraints gpt_top.pdc]]
set out  [file join $here build]

file delete -force $out
file mkdir [file join $out impl_1]

# Copy of the top with the bring-up preloads as parameter defaults
set f [open [file join $rtl gpt_top.sv] r]
set src [read $f]
close $f
regsub {parameter VREG_INIT = ""} $src \
    {parameter VREG_INIT = "bringup_vreg.mem"} src
regsub {parameter TEXT_INIT = ""} $src \
    {parameter TEXT_INIT = "bringup_text.mem"} src
set top [file join $out gpt_top.sv]
set f [open $top w]
puts -nonewline $f $src
close $f

# Memory images where synthesis looks for them
foreach m {font.mem exp_lut.mem recip_lut.mem rsqrt_lut.mem
           bringup_vreg.mem bringup_text.mem} {
    file copy -force [file join $mem $m] $out
    file copy -force [file join $mem $m] [file join $out impl_1]
}

prj_create -name gpt_top -dir $out -impl impl_1 \
    -dev iCE40UP5K-SG48I -performance "High-Performance_1.2V" \
    -synthesis "lse"

prj_add_source [file join $rtl gpt_pkg.sv]
foreach m {synchronizer reset_gen spi_slave cmd_decoder prog_mem
           sequencer rmsnorm_unit softmax_unit lut_rom} {
    prj_add_source [file join $rtl ctrl $m.sv]
}
foreach m {mac_lane requant matvec_engine vecop kv_store} {
    prj_add_source [file join $rtl exec $m.sv]
}
foreach m {spram_mem vreg_file score_buf} {
    prj_add_source [file join $rtl mem $m.sv]
}
foreach m {vga_pll vga_timing text_buffer font_rom scroll_cdc
           text_renderer} {
    prj_add_source [file join $rtl vga $m.sv]
}
prj_add_source $top
prj_add_source $pdc
prj_set_top_module gpt_top
prj_save

prj_run Synthesis -impl impl_1
prj_run Map -impl impl_1
prj_run PAR -impl impl_1
prj_run Export -impl impl_1
prj_close
