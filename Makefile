.PHONY: all test cli gui app clean

all: test

test:
	swift test

cli:
	swift build --product controllab-cli

gui:
	swift build --product ControlLab

app:
	./scripts/package-app.sh

clean:
	swift package clean
	rm -rf build
