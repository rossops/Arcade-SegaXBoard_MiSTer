"""Shared cocotb runner: build with Icarus and run one test module."""
import os
from pathlib import Path
from cocotb_tools.runner import get_runner

ROOT = Path(__file__).resolve().parents[2]


def run(toplevel, sources, test_module, parameters=None):
    sim = os.getenv("SIM", "icarus")
    runner = get_runner(sim)
    build_dir = ROOT / "verif" / "unit" / "sim_build" / toplevel
    runner.build(
        sources=[ROOT / s for s in sources],
        hdl_toplevel=toplevel,
        build_dir=build_dir,
        parameters=parameters or {},
        build_args=["-g2012"] if sim == "icarus" else [],
        always=True,
        timescale=("1ns", "1ps"),
    )
    runner.test(hdl_toplevel=toplevel, test_module=test_module, build_dir=build_dir)
