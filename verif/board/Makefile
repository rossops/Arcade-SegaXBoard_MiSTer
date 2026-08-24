# Verilator board simulation. From repo root: make -C verif/board run FRAMES=10
ROOT := $(abspath ../..)
SRCS := rtl/xb_pkg.sv rtl/video/xb_video_timing.sv rtl/mem/xb_dpram.sv \
  rtl/cpu/xb_math_5248.sv rtl/cpu/xb_math_5249.sv rtl/cpu/xb_cmptimer_5250.sv \
  rtl/io/xb_cxd1095.sv rtl/io/xb_adc0804.sv rtl/cpu/xb_rom_cache.sv rtl/cpu/xb_m68k_bus.sv \
  rtl/cpu/fx68k/fx68k.sv rtl/cpu/fx68k/fx68kAlu.sv rtl/cpu/fx68k/uaddrPla.sv \
  rtl/xb_core.sv verif/board/sdram_model.sv verif/board/tb_board.sv
VFLAGS := -Wno-fatal -Wno-lint -Wno-style -Wno-BLKANDNBLK -Wno-MULTIDRIVEN -Wno-UNOPTFLAT \
  -DSIMULATION --timing -O2 --x-assign fast --x-initial fast \
  --no-assert-case --top-module tb_board -I$(ROOT)/rtl/cpu/fx68k
FRAMES ?= 10

obj_dir/Vtb_board: $(addprefix $(ROOT)/,$(SRCS)) main.cpp
	verilator $(VFLAGS) --cc --exe --build -j 4 $(addprefix $(ROOT)/,$(SRCS)) main.cpp -o Vtb_board

build: obj_dir/Vtb_board

run: obj_dir/Vtb_board
	mkdir -p out/verif && ln -sfn $(ROOT)/verif/golden out/verif/golden; \
	ln -sf $(ROOT)/rtl/cpu/fx68k/microrom.mem out/microrom.mem; ln -sf $(ROOT)/rtl/cpu/fx68k/nanorom.mem out/nanorom.mem; \
	cd out && ../obj_dir/Vtb_board +frames=$(FRAMES)

clean:
	rm -rf obj_dir out
