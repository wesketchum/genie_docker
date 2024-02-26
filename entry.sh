#!/bin/bash

source $ROOTSYS/bin/thisroot.sh
export LD_LIBRARY_PATH=$GENIE/lib:$PYTHIA6_LIB:/usr/local/lib:$LD_LIBRARY_PATH
export PATH=$GENIE/bin:$PATH

/bin/bash "$@"

