include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = TextViewVimKitReferenceApp

TextViewVimKitReferenceApp_OBJC_FILES = \
	main.m \
	RAAppDelegate.m \
	RAFixtureTextView.m \
	RAReferenceWindow.m \
	../src/GSVVimMode.m \
	../src/GSVVimConfig.m \
	../src/GSVVimConfigLoader.m \
	../src/GSVTextViewAdapter.m \
	../src/GSVVimEngine.m \
	../src/GSVVimBindingController.m

TextViewVimKitReferenceApp_CPPFLAGS += -I../src
ADDITIONAL_OBJCFLAGS += -fobjc-arc

include $(GNUSTEP_MAKEFILES)/application.make
