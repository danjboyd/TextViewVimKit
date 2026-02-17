include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS = ReferenceApp TextViewVimKitTests

include $(GNUSTEP_MAKEFILES)/aggregate.make

.PHONY: run
run: all
	. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh; \
	openapp "$(CURDIR)/ReferenceApp/TextViewVimKitReferenceApp.app" $(filter-out run,$(MAKECMDGOALS))
