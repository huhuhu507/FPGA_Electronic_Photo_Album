open_project hd_clean.al
elaborate -top hd_clean
read_adc hd_clean.adc
read_sdc hd_clean.sdc
optimize_rtl
optimize_gate -packarea reports/gate.area
legalize_phy_inst
place
route
report_area -file reports/final.area
report_timing -file reports/timing.rpt
bitgen -bit bitstream/hd_fixed.bit -version 0X00 -g ucode:00000000000000000000000000000000
exit
