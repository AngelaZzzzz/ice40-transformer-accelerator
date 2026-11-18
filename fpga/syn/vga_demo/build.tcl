# build.tcl
#   VGA demo build: synthesis, map, place-and-route and bitstream of
#   vga_demo_top for the iCE40UP5K, in two variants:
#     build/text/  PATTERN = 0, the text screen from demo_text.mem
#     build/bars/  PATTERN = 1, color bars and border (no memories)
#   Run from any directory with
#     radiantc fpga/syn/vga_demo/build.tcl
#   Each variant's results (not committed) are in build/<variant>/impl_1/:
#     vga_demo_<variant>_impl_1.bin  bitstream to program
#     vga_demo_<variant>_impl_1.mrp  resource usage (text: 6 EBR expected)
#     vga_demo_<variant>_impl_1.twr  timing report
#   The text variant needs fpga/mem/font.mem and fpga/mem/demo_text.mem;
#   they are copied next to the project so $readmemh finds them.

set here [file dirname [file normalize [info script]]]
set rtl  [file normalize [file join $here .. .. rtl]]
set mem  [file normalize [file join $here .. .. mem]]
set root [file join $here build]

file delete -force $root

foreach {variant pattern} {text 0 bars 1} {
    set out [file join $root $variant]
    file mkdir [file join $out impl_1]

    # Copy of the top with this variant's PATTERN default
    set f [open [file join $here vga_demo_top.sv] r]
    set src [read $f]
    close $f
    regsub {parameter bit PATTERN = 1'b0} $src \
        "parameter bit PATTERN = 1'b$pattern" src
    set top [file join $out vga_demo_top.sv]
    set f [open $top w]
    puts -nonewline $f $src
    close $f

    # Memory images where synthesis looks for them
    foreach m {font.mem demo_text.mem} {
        file copy -force [file join $mem $m] $out
        file copy -force [file join $mem $m] [file join $out impl_1]
    }

    prj_create -name vga_demo_$variant -dir $out -impl impl_1 \
        -dev iCE40UP5K-SG48I -performance "High-Performance_1.2V" \
        -synthesis "lse"

    prj_add_source [file join $rtl ctrl synchronizer.sv]
    prj_add_source [file join $rtl ctrl reset_gen.sv]
    prj_add_source [file join $rtl vga vga_pll.sv]
    prj_add_source [file join $rtl vga vga_timing.sv]
    prj_add_source [file join $rtl vga text_buffer.sv]
    prj_add_source [file join $rtl vga font_rom.sv]
    prj_add_source [file join $rtl vga scroll_cdc.sv]
    prj_add_source [file join $rtl vga text_renderer.sv]
    prj_add_source $top
    prj_add_source [file join $here vga_demo.pdc]
    prj_set_top_module vga_demo_top
    prj_save

    prj_run Synthesis -impl impl_1
    prj_run Map -impl impl_1
    prj_run PAR -impl impl_1
    prj_run Export -impl impl_1
    prj_close
}
