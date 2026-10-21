.PHONY: test clean lint ppa

ROOT := $(abspath .)

test:
	./scripts/run_iverilog.sh

lint:
	iverilog -g2012 -Wall -t null \
	  rtl/self_repairing_systolic.sv rtl/variants.sv

ppa:
	./scripts/run_ppa.sh

clean:
	rm -rf build

