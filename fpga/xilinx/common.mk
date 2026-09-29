HOSTNAME := $(shell hostname)

ifneq (,$(findstring lis,$(HOSTNAME)))
	MODULEFILE_FLAG := -source ../../scripts/add_modulefiles.tcl
endif

all:
	vivado -mode batch $(MODULEFILE_FLAG) -source tcl/run.tcl

gui:
	vivado -mode gui $(MODULEFILE_FLAG) -source tcl/run.tcl &

clean:
	rm -rf ip/*
	mkdir -p ip
	rm -rf ${PROJECT}.*
	rm -rf component.xml
	rm -rf vivado*.jou
	rm -rf vivado*.log
	rm -rf vivado*.str
	rm -rf xgui
	rm -rf .Xil
