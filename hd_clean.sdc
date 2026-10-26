create_clock -name clk50 -period 20.000 [get_ports clk50]
derive_pll_clocks -gen_basic_clock
# 50MHz control is asynchronous to the cascaded video PLL. Transfers between
# the video PLL domains use explicit held-payload/toggle handshakes rather than
# depending on an implicit phase relation. The serializer payload is bounded below.
# CLKC3 is the +90-degree 92.8125MHz SDRAM pin clock, kept related to CLKC1.
set_false_path -from [get_clocks clk50] -to [get_clocks {u_pll.clkc[0]}]
set_false_path -from [get_clocks {u_pll.clkc[0]}] -to [get_clocks clk50]
set_false_path -from [get_clocks clk50] -to [get_clocks {u_pll.clkc[1]}]
set_false_path -from [get_clocks {u_pll.clkc[1]}] -to [get_clocks clk50]
set_false_path -from [get_clocks clk50] -to [get_clocks {u_pll.clkc[2]}]
set_false_path -from [get_clocks {u_pll.clkc[2]}] -to [get_clocks clk50]
set_false_path -from [get_clocks {u_pll.clkc[0]}] -to [get_clocks {u_pll.clkc[1]}]
set_false_path -from [get_clocks {u_pll.clkc[1]}] -to [get_clocks {u_pll.clkc[0]}]
set_false_path -from [get_clocks {u_pll.clkc[0]}] -to [get_clocks {u_pll.clkc[2]}]
# Symbols are sampled >=3 serializer periods (8.08ns) after source update.
# TD's max-path check includes the launch edge and insertion latency (about
# 4.96ns in this design), not only Q-to-D propagation. An absolute 7.5ns bound
# therefore leaves about 2.54ns for the payload path, within the 8.08ns window.
# Keep this bound timed: report_timing must show nonnegative max-path slack.
set_max_delay -from [get_clocks {u_pll.clkc[2]}] -to [get_clocks {u_pll.clkc[0]}] 7.500
set_false_path -from [get_clocks {u_pll.clkc[1]}] -to [get_clocks {u_pll.clkc[2]}]
set_false_path -from [get_clocks {u_pll.clkc[2]}] -to [get_clocks {u_pll.clkc[1]}]
