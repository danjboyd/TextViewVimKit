include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = TextViewVimKitTests

TextViewVimKitTests_OBJC_FILES = \
	GSVVimConfigLoaderTests.m \
	GSVVimEngineTests.m \
	GSVVimBindingControllerTests.m \
	../src/GSVVimMode.m \
	../src/GSVVimConfig.m \
	../src/GSVVimConfigLoader.m \
	../src/GSVTextViewAdapter.m \
	../src/GSVVimEngine.m \
	../src/GSVVimBindingController.m

TextViewVimKitTests_CPPFLAGS += -I../src
TextViewVimKitTests_BUNDLE_LIBS += -lXCTest -lgnustep-gui
ADDITIONAL_OBJCFLAGS += -fobjc-arc

include $(GNUSTEP_MAKEFILES)/bundle.make
