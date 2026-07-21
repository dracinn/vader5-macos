PREFIX ?= /usr/local

.PHONY: all clean install

all: vader5-macos

vader5-macos: Vader5Bridge.swift VirtualHID.c VirtualHID.h
	xcrun clang -O2 -c VirtualHID.c -o VirtualHID.o
	xcrun swiftc -O Vader5Bridge.swift VirtualHID.o -o $@ -framework IOKit -framework CoreFoundation

install: vader5-macos
	install -d "$(PREFIX)/bin"
	install -m 755 vader5-macos "$(PREFIX)/bin/vader5-macos"

clean:
	rm -f vader5-macos VirtualHID.o
