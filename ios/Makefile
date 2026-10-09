.PHONY: project test build open device

DESTINATION ?= platform=iOS Simulator,name=iPhone 17
# Find your device ids with: xcrun devicectl list devices
# Usage: make device DEVICE_UDID=<udid> DEVICE_CORE=<coredevice-id> DEVELOPMENT_TEAM=<team-id>
DEVICE_UDID ?=
DEVICE_CORE ?=
BUNDLE ?= com.nightmoose.whistler
DD ?= $(PWD)/build/DD

project:
	xcodegen generate

open: project
	open Whistler.xcodeproj

test: project
	xcodebuild test -project Whistler.xcodeproj -scheme Whistler -destination '$(DESTINATION)' -quiet

build: project
	xcodebuild -project Whistler.xcodeproj -scheme Whistler -destination '$(DESTINATION)' -quiet

device: project
	xcodebuild \
		-project Whistler.xcodeproj \
		-scheme Whistler \
		-destination 'id=$(DEVICE_UDID)' \
		DEVELOPMENT_TEAM='$(DEVELOPMENT_TEAM)' \
		-configuration Debug \
		-derivedDataPath '$(DD)' \
		-allowProvisioningUpdates \
		build
	xcrun devicectl device install app --device '$(DEVICE_CORE)' \
		'$(DD)/Build/Products/Debug-iphoneos/Whistler.app'
	xcrun devicectl device process launch --device '$(DEVICE_CORE)' \
		$(BUNDLE) || true
