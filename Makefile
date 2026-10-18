PREFIX ?= /usr/local
.PHONY: test install
test:
	bash ci/test.sh
install:
	install -d $(DESTDIR)$(PREFIX)/share/licensebox-pascal
	install -m644 src/licensebox.pas $(DESTDIR)$(PREFIX)/share/licensebox-pascal/
