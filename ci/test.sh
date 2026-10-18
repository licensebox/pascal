#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/units build/install
fpc -Mobjfpc -Sh -Fu./src -FUbuild/units -FEbuild -Fl"$LICENSEBOX_LIB_DIR" tests/binding.pas
./build/binding
fpc -Mobjfpc -Sh -Fu./src -FUbuild/units -FEbuild -Fl"$LICENSEBOX_LIB_DIR" tests/adapter.pas
install -m 644 src/licensebox.pas build/install/
fpc -Mobjfpc -Sh -Fubuild/install -FUbuild/units -FEbuild -Fl"$LICENSEBOX_LIB_DIR" examples/status.pas
