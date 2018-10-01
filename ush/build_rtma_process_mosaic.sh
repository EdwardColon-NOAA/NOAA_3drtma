#!/bin/sh

date
# set -x

#=========================================================================#
# User define the following variables:

dirname_source="rtma_process_mosaic.fd"

#=========================================================================#

echo "*==================================================================*"
echo " this script is going to build/make the executable code of observation pre-process " 
echo "   of MOSAIC radar data used for RTMA3D " 
echo "*==================================================================*"
#
#--- detect the machine/platform
#
if [[ -d /dcom && -d /hwrf ]] ; then
    . /usrx/local/Modules/3.2.10/init/sh
    target=wcoss
    . $MODULESHOME/init/sh
elif [[ -d /cm ]] ; then
    . $MODULESHOME/init/sh
    conf_target=nco
    target=cray
elif [[ -d /ioddev_dell ]]; then
    . $MODULESHOME/init/sh
    conf_target=nco
    target=dell
elif [[ -d /scratch3 ]] ; then
    . /apps/lmod/lmod/init/sh
    target=theia
else
    echo "unknown target = $target"
    exit 9
fi
echo " This machine is $target ."
#===================================================================#

#
#--- Finding the RTMA ROOT DIRECTORY --- #
#
BASE=`pwd`;
echo " current directory is $BASE "

# detect existence of directory sorc/
i_max=5; i=0;
while [ "$i" -lt "$i_max" ]
do
  let "i=$i+1"
  if [ -d ./sorc ]
  then
    cd ./sorc
    TOP_SORC=`pwd`
    TOP_RTMA=`dirname $(readlink -f .)`
    echo " found sorc/ is under $TOP_RTMA"
    break
  else
    cd ..
  fi
done
if [ "$i" -ge "$i_max" ]
then
  echo ' directory sorc/ could not be found. Abort the task of compilation.'
  exit 1
fi

USH_DIR=${TOP_RTMA}/ush

cd $TOP_RTMA
EXEC=${TOP_RTMA}/exec
if [ ! -d ${EXEC} ]; then mkdir -p ${EXEC}; fi

cd ${TOP_SORC}
# all the building jobs is to be done under sub-direvtory BUILD_DIR
SOURCE_DIR=${TOP_SORC}/${dirname_source}
BUILD_DIR=${TOP_SORC}/${dirname_source}

echo "*==================================================================*"
echo "  building process is under $BUILD_DIR"
echo "   the source code is under "
echo
echo "   ----> ${SOURCE_DIR}"
echo
echo " please look at the source code directory name and make sure it is the name you want to build code on "
echo " if it is not, abort and change the definition of 'dirname_source' in this script ($0)  "
read -p " Press [Enter] key to continue (or Press Ctrl-C to abort) "
echo
echo "*==================================================================*"
#
#--- detecting the existence of the directory of source package
#
if [ ! -d ${SOURCE_DIR} ]
then
  echo " ====> WARNING: directory of source code of obs pre-process MOSAIC : ${SOURCE_DIR}  does NOT exist."
  echo " ====> Warning: abort compilation of obs pre-process MOSAIC for RTMA3D."
  exit 2
fi

#
#--- compilation of code
#

#==================#
# load modules
modules_dir=${TOP_RTMA}/modulefiles
if [ $target = wcoss -o $target = cray ]; then
    module purge
    module load $modules_dir/modulefile.ProdGSI.$target
elif [ $target = theia ]; then
    module purge
    source $modules_dir/modulefile.ProdGSI.$target
    module list
elif [ $target = dell ]; then
    module purge
    source $modules_dir/modulefile.ProdGSI.$target
    export NETCDF_INCLUDE=-I/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/include
    export NETCDF_CFLAGS=-I/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/include
    export NETCDF_LDFLAGS_CXX="-L/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/lib -lnetcdf -lnetcdf_c++"
    export NETCDF_LDFLAGS_CXX4="-L/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/lib -lnetcdf -lnetcdf_c++4"
    export NETCDF_CXXFLAGS=-I/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/include
    export NETCDF_FFLAGS=-I/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/include
    export NETCDF_ROOT=/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0
    export NETCDF_LIB=/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/lib
    export NETCDF_LDFLAGS_F="-L/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/lib -lnetcdff"
    export NETCDF_LDFLAGS_C="-L/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/lib -lnetcdf"
    export NETCDF_LDFLAGS="-L/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/lib -lnetcdff"
    export NETCDF=/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0
    export NETCDF_INC=/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/include
    export NETCDF_CXX4FLAGS=-I/usrx/local/prod/packages/ips/18.0.1/netcdf/4.5.0/include
else
    echo " ----> WARNING: module file has not been configured for this machine: $target "
    echo " ----> warning: abort compilation "
    exit 9
fi

#==================#
# compiling
cd ${SOURCE_DIR}
echo " ====>  compiling is under directory: ${SOURCE_DIR} "

make clean  -f makefile_${target}
echo " make -f makefile_${target}  >& ./log.make.process_mosaic "
make -f makefile_${target}  >& ./log.make.process_NSSL_mosaic

if [ $? -eq 0 ] ; then
  echo " code was built successfully."
  echo " cp -p ${BUILD_DIR}/process_NSSL_mosaic.exe   ${EXEC}/process_NSSL_mosaic.exe "
  cp -p ${BUILD_DIR}/process_NSSL_mosaic.exe   ${EXEC}/process_NSSL_mosaic.exe
  ls -l ${EXEC}/process_NSSL_mosaic.exe
else
  echo " ================ WARNING =============== " 
  echo " Compilation of process_NSSL_mosaic code was failed."
  echo " Check up with the log file under ${SOURCE_DIR}"
  echo "   ----> log.make.process_NSSL_mosaic  : "
  echo " ================ WARNING =============== " 
fi

#===================================================================#

# set +x
date

exit 0
