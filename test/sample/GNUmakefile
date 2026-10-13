# The sample on GNUstep (Linux): make, make check, make install DESTDIR=...
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS = SampleKit SampleApp

include $(GNUSTEP_MAKEFILES)/aggregate.make

# The library's test, against the library as built here (not installed).
check::
	$(MAKE) -C Tests
	LD_LIBRARY_PATH="$(CURDIR)/SampleKit/obj$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" ./Tests/obj/samplekit-test
