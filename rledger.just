#!/usr/bin/env just -f

import '~/bin/prelude.just'
help: _help

# install latest rustledger binaries, with bean* renamed to rbean*
install:
    #!/usr/bin/env bash
    cd ~/src/hledger/bin
    eget rustledger/rustledger --all --pre-release
    for f in bean-*; do mv $f r$f; done
    ls -ltF rledger* rbean*
    rledger --version
