include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = SampleApp
SampleApp_OBJC_FILES = main.m
ADDITIONAL_INCLUDE_DIRS += -I../SampleKit
ADDITIONAL_LIB_DIRS += -L../SampleKit/obj
SampleApp_GUI_LIBS = -lSampleKit
ADDITIONAL_OBJCFLAGS += -fobjc-arc

include $(GNUSTEP_MAKEFILES)/application.make
