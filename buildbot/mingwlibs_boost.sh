#!/bin/bash

set -e

# Setting system dependent vars
BOOST_DIR=/tmp/boost64/
BOOST_BUILD_DIR=/tmp/build-boost64/
MINGWLIBS_DIR=/tmp/mingwlibs64/
BOOST_MAJOR=1
BOOST_MINOR=55
BOOST_PATCH=0
BOOST_FILE=boost_${BOOST_MAJOR}_${BOOST_MINOR}_${BOOST_PATCH}.tar.bz2?download
BOOST_DL=http://sourceforge.net/projects/boost/files/boost/${BOOST_MAJOR}.${BOOST_MINOR}.${BOOST_PATCH}/$BOOST_FILE

# spring's boost dependencies
BOOST_LIBS="test thread system regex filesystem program_options signals chrono"
SPRING_HEADERS="${BOOST_LIBS} format ptr_container spirit algorithm date_time asio signals2"
ASSIMP_HEADERS="math/common_factor smart_ptr"
BOOST_HEADERS="${SPRING_HEADERS} ${ASSIMP_HEADERS}"
BOOST_CONF=${BOOST_BUILD_DIR}/user-config.jam

set +e
## disable fetch by emerge as it requires access to the portage group (which buildbot doesn't have)
# EMERGE=$(which emerge)
set -e

# x86 or x86_64
MINGW_GPP=x86_64-w64-mingw32.static-g++
GCC_VERSION=$(${MINGW_GPP} -dumpversion)

BOOST_LIBS_ARG=""
for LIB in $BOOST_LIBS
do
	BOOST_LIBS_ARG="${BOOST_LIBS_ARG} --with-${LIB}"
done


#############################################################################################################

# cleanup
echo -e "\n---------------------------------------------------"
echo "-- clear"
rm -rf ${BOOST_BUILD_DIR}
rm -rf ${BOOST_DIR}
rm -rf ${MINGWLIBS_DIR}


# git clone mingwlibs repo (needed for later uploading)
echo -e "\n---------------------------------------------------"
echo "-- clone git repo"
git clone -l -s -n .  ${MINGWLIBS_DIR}
cd ${MINGWLIBS_DIR}
git fetch
git checkout -f master


# Setup final structure
echo -e "\n---------------------------------------------------"
echo "-- setup dirs"
mkdir -p ${BOOST_DIR}
rm -f ${MINGWLIBS_DIR}lib/libboost*
rm -rf ${MINGWLIBS_DIR}include/boost
mkdir -p ${MINGWLIBS_DIR}lib/
mkdir -p ${MINGWLIBS_DIR}include/boost/


# Gentoo related - retrieve boost's tarball
echo -e "\n---------------------------------------------------"
echo "-- fetching boost's tarball"

if [ -n "$EMERGE" ] && [ -x "$EMERGE" ]; then
	$EMERGE boost --fetchonly &>/dev/null
	source /etc/portage/make.conf
	BOOST_FILE=$(find ${DISTDIR} -iname "boost_*.tar.*" -print -quit)
else
	wget -P /tmp -N --no-verbose ${BOOST_DL}
	BOOST_FILE="/tmp/${BOOST_FILE}"
fi


echo -e "\n---------------------------------------------------"
echo "-- extracting boost's tarball"
tar -xa -C ${BOOST_DIR} -f ${BOOST_FILE}

# bootstrap bjam
echo -e "\n---------------------------------------------------"
echo "-- bootstrap bjam"
cd ${BOOST_DIR}/boost_*
./bootstrap.sh


# Building bcp - boosts own filtering tool
echo -e "\n---------------------------------------------------"
echo "-- creating bcp"
cd tools/bcp
../../bjam --build-dir=${BOOST_BUILD_DIR}
cd ../..
cp $(ls ${BOOST_BUILD_DIR}/boost/*/tools/bcp/*/*/*/bcp) .


# Building the required libraries
echo -e "\n---------------------------------------------------"
echo "-- running bjam"
echo "using gcc : : ${MINGW_GPP} ;" > ${BOOST_CONF}
./bjam \
    -j5 \
    --build-dir="${BOOST_BUILD_DIR}" \
    --stagedir="${MINGWLIBS_DIR}" \
    --user-config=${BOOST_CONF} \
    --debug-building \
    --layout="tagged" \
    ${BOOST_LIBS_ARG} \
    variant=release \
    target-os=windows \
    threadapi=win32 \
    threading=multi \
    link=static \
    toolset=gcc \


# Copying the headers to MinGW-libs
echo -e "\n---------------------------------------------------"
echo "-- copying headers"
rm -Rf ${BOOST_BUILD_DIR}/filtered
mkdir ${BOOST_BUILD_DIR}/filtered
./bcp ${BOOST_HEADERS} ${BOOST_BUILD_DIR}/filtered
cp -r ${BOOST_BUILD_DIR}/filtered/boost ${MINGWLIBS_DIR}include/


# some config we need
echo -e "\n---------------------------------------------------"
echo "-- adjusting config/user.hpp"
echo "#define BOOST_THREAD_USE_LIB" >> "${MINGWLIBS_DIR}include/boost/config/user.hpp"


# fix names
echo -e "\n---------------------------------------------------"
echo "-- fix some library names"
mv "${MINGWLIBS_DIR}lib/libboost_thread_win32-mt.a" "${MINGWLIBS_DIR}lib/libboost_thread-mt.a"


# push to git repo
echo -e "\n---------------------------------------------------"
echo "-- git push"
cd ${MINGWLIBS_DIR}
BOOST_VERSION=$(grep "#define BOOST_VERSION " ./include/boost/version.hpp | awk '{print $3}')
BOOST_VERSTR="$((BOOST_VERSION / 100000)).$((BOOST_VERSION / 100 % 1000)).$((BOOST_VERSION % 100))"
git remote add cloud git@github.com:spring/mingwlibs64.git
git add --all
git commit -m "boost update (boost: ${BOOST_VERSTR} gcc: ${GCC_VERSION})"
git push cloud


# cleanup
echo -e "\n---------------------------------------------------"
echo "-- cleanup"
rm -rf ${BOOST_BUILD_DIR}
rm -rf ${BOOST_DIR}
rm -rf ${MINGWLIBS_DIR}

