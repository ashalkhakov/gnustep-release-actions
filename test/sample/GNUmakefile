# The sample on GNUstep (Linux): make, make check, make install DESTDIR=...
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS = SampleKit SampleApp

include $(GNUSTEP_MAKEFILES)/aggregate.make

# The library's test, against the library as built here (not installed):
# found on LD_LIBRARY_PATH on Linux, on PATH on Windows.
check::
	$(MAKE) -C Tests
	LD_LIBRARY_PATH="$(CURDIR)/SampleKit/obj$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	PATH="$(CURDIR)/SampleKit/obj:$$PATH" ./Tests/obj/samplekit-test
