include $(GNUSTEP_MAKEFILES)/common.make

# Not "check": that is gnustep-make's target.
TOOL_NAME = samplekit-test
samplekit-test_OBJC_FILES = check.m
ADDITIONAL_INCLUDE_DIRS += -I../SampleKit
ADDITIONAL_LIB_DIRS += -L../SampleKit/obj
samplekit-test_TOOL_LIBS = -lSampleKit
ADDITIONAL_OBJCFLAGS += -fobjc-arc

include $(GNUSTEP_MAKEFILES)/tool.make
