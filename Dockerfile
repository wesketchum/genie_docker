FROM ubuntu:22.04
MAINTAINER Wesley Ketchum <wketchum@fnal.gov>

ARG NPROC=1

ENV GENIE_BASE=/usr/local/GENIE
ENV GENIE=$GENIE_BASE/Generator
ENV GENIE_REWEIGHT=$GENIE_BASE/Reweight

ENV PYTHIA6_LIBRARY=/usr/pythia6
ENV ROOTSYS=/usr/local/root
#ENV LANG=C.UTF-8

COPY packages packages

RUN apt-get update -qq && \
    ln -sf /usr/share/zoneinfo/UTC /etc/localtime && \
    apt-get -y install $(cat packages) && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/cache/apt/archives/* && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get autoremove --purge &&\
    apt-get clean all &&\
    python3 -m pip install --upgrade pip &&\
    python3 -m pip install --upgrade --no-cache-dir cmake
#RUN yes | unminimize

###############################################################################
# PYTHIA6
#
# Needed for GENIE. Needs to be linked with ROOT.
#
# Looks complicated? Tell me about it.
# Core of what's done follows from here: 
#   https://root-forum.cern.ch/t/root-with-pythia6-and-pythia8/19211
# (1) Download pythia6 build tarball from ROOT. Known to lead to a build that can work with ROOT.
# (2) Download the latest Pythia6 (6.4.2.8) from Pythia. Yes, it's still ancient.
# (3) Declare extern some definitions that need to be extern via sed. 
#     Compiler/linker warns. Hard-won solution.
# (4) Build with C and FORTRAN the various pieces.
# (5) Put everything in a directory in the install area, and cleanup.
#
# (Ideally GENIE works with Pythia8? But not sure that works yet despite the adverts that it does.)
# 
###############################################################################
ENV PYTHIA_VERSION="6.428"
ENV PREVIOUS_PYTHIA_VERSION="6.416"
ENV PYTHIA_MAJOR_VERSION=6
LABEL pythia.version=${PYTHIA_VERSION}
#"6.428"
# Pythia uses an un-dotted version file naming convention. To deal with that
# we need some string manipulation and exports that work best with bash 
SHELL ["/bin/bash", "-c"] 
WORKDIR /tmp
RUN export PYTHIA_VERSION_INTEGER=$(awk '{print $1*1000}' <<< ${PYTHIA_VERSION} )  &&\
    export PREVIOUS_PYTHIA_VERSION_INTEGER=$(awk '{print $1*1000}' <<< ${PREVIOUS_PYTHIA_VERSION} )  &&\
    wget https://root.cern.ch/download/pythia${PYTHIA_MAJOR_VERSION}.tar.gz -O pythia6.tar.gz &&\
    mkdir src && \
    tar xf pythia6.tar.gz --strip-components=1 --directory src && \
    wget --no-check-certificate https://pythia.org/download/pythia${PYTHIA_MAJOR_VERSION}/pythia${PYTHIA_VERSION_INTEGER}.f &&\
    mv pythia${PYTHIA_VERSION_INTEGER}.f src/pythia${PYTHIA_VERSION_INTEGER}.f && rm -rf src/pythia${PREVIOUS_PYTHIA_VERSION_INTEGER}.f &&\
    cd src && \
    sed -i 's/int py/extern int py/g' pythia${PYTHIA_MAJOR_VERSION}_common_address.c && \
    sed -i 's/extern int pyuppr/int pyuppr/g' pythia${PYTHIA_MAJOR_VERSION}_common_address.c && \
    sed -i 's/char py/extern char py/g' pythia${PYTHIA_MAJOR_VERSION}_common_address.c && \
    echo 'void MAIN__() {}' >main.c && \
    gcc -c -fPIC -shared main.c -lgfortran && \
    gcc -c -fPIC -shared pythia${PYTHIA_MAJOR_VERSION}_common_address.c -lgfortran && \
    gfortran -c -fPIC -shared pythia*.f && \
    gfortran -c -fPIC -shared -fno-second-underscore tpythia${PYTHIA_MAJOR_VERSION}_called_from_cc.F && \
    gfortran -shared -Wl,-soname,libPythia${PYTHIA_MAJOR_VERSION}.so -o libPythia${PYTHIA_MAJOR_VERSION}.so main.o  pythia*.o tpythia*.o && \
    mkdir -p $PYTHIA6_LIBRARY && cp -r * $PYTHIA6_LIBRARY/ && \
    cd ../ && rm -rf src && \
    echo "${PYTHIA6_LIBRARY}/" > /etc/ld.so.conf.d/pythia${PYTHIA_MAJOR_VERSION}.conf

SHELL ["/bin/sh", "-c"] 

# LHAPDF
LABEL lhapdf.version="6.5.4"
WORKDIR /tmp
RUN mkdir src &&\
    wget https://lhapdf.hepforge.org/downloads/?f=LHAPDF-6.5.4.tar.gz -O lhapdf.tar.gz && \
    tar xf lhapdf.tar.gz --strip-components=1 --directory src && \
    cd src &&\
    ./configure --disable-python --prefix=/usr &&\
    make -j$NPROC install &&\
    cd ../ &&\
    rm -rf src

# PYTHIA8
LABEL pythia.version="8.310"
WORKDIR /tmp
RUN mkdir src && \
    wget https://pythia.org/download/pythia83/pythia8310.tgz -O pythia8.tar.gz && \
    tar xf pythia8.tar.gz --strip-components=1 --directory src && \
    cd src &&\
    ./configure --with-lhapdf6 --prefix=/usr &&\
    make -j$NPROC install &&\
    cd ../ &&\
    rm -rf src

ENV ROOT_VERSION="6.30.04"
LABEL root.version=${ROOT_VERSION}
WORKDIR /tmp
RUN mkdir src &&\
    wget https://root.cern/download/root_v${ROOT_VERSION}.source.tar.gz -O root.tar.gz && \
    tar xf root.tar.gz --strip-components=1 --directory src && \
    cmake \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_STANDARD=17 \
      -DCMAKE_INSTALL_PREFIX=$ROOTSYS \
      -Dgnuinstall=ON \
      -Dgminimal=ON \
      -Dasimage=ON \
      -Dgdml=ON \
      -Dopengl=ON \
      -Dpyroot=ON \
      -Dxrootd=OFF \
#      -Dgsl_shared=ON \ 
      -Dmathmore=ON \   
      -Dpythia8=ON \    
      -Dpythia6=ON \    
      -DPYTHIA6_LIBRARY=/usr/pythia6/libPythia6.so \
      -B build \
      -S src \
    && cmake --build build --target install -j$NPROC &&\
    rm -rf build src &&\
    ldconfig

RUN apt-get update -qq && \
    apt-get install -y protobuf-compiler 

WORKDIR /tmp
RUN mkdir src && \
    wget http://hepmc.web.cern.ch/hepmc/releases/HepMC3-3.2.7.tar.gz -q -O hepmc3.tar.gz && \
    tar xf hepmc3.tar.gz --strip-components=1 --directory src && \
    mkdir build && cd build && \
    cmake \
#      -DCMAKE_INSTALL_PREFIX=/usr/lib \
      -DHEPMC3_ENABLE_ROOTIO:BOOL=ON \
      -DHEPMC3_ENABLE_PROTOBUFIO:BOOL=ON \
      -DHEPMC3_ENABLE_TEST:BOOL=OFF \
      -DHEPMC3_INSTALL_INTERFACES:BOOL=ON \
      -DHEPMC3_BUILD_STATIC_LIBS:BOOL=ON \
      -DHEPMC3_BUILD_DOCS:BOOL=OFF \
      -DHEPMC3_ENABLE_PYTHON:BOOL=ON \
      -DHEPMC3_PYTHON_VERSIONS=3.10 \
      ../src && \
    make -j$NPROC && \
    make -j$NPROC install && \
   cd ../ && rm -rf src build *.tar.gz

LABEL genie.version=3.04.00
ENV GENIE_VERSION=3_04_00
LABEL genie.version=${GENIE_VERSION}

SHELL ["/bin/bash", "-c"]

WORKDIR /tmp
RUN source $ROOTSYS/bin/thisroot.sh && \
    mkdir -p ${GENIE} &&\
    export ENV GENIE_GET_VERSION="$(sed 's,\.,_,g' <<< $GENIE_VERSION )" &&\ 
#    wget https://github.com/GENIE-MC/Generator/archive/refs/tags/R-${GENIE_GET_VERSION}.tar.gz -O genie.tar.gz && \
#    wget https://github.com/wesketchum/Generator/tarball/master -q -O genie.tar.gz && \
    wget https://github.com/wesketchum/Generator/tarball/hepmc -q -O genie.tar.gz && \
    tar xf genie.tar.gz --strip-components=1 --directory ${GENIE} &&\
    cd ${GENIE} &&\
    ./configure \
      --enable-lhapdf6 \
      --disable-lhapdf5 \
      --enable-gfortran \
      --with-gfortran-lib=/usr/x86_64-linux-gnu/ \
      --enable-pythia8 \
      --with-pythia8-lib=/usr/lib \
      --enable-test \
      --enable-hepmc3 \
      --with-hepmc3-lib=/usr/local/lib \
      --with-hepmc3-inc=/usr/local/include \
    && \
    make -j$NPROC && \
    make -j$NPROC install

#SHELL ["/bin/sh", "-c"] 

WORKDIR /home

CMD ["/bin/bash"]
