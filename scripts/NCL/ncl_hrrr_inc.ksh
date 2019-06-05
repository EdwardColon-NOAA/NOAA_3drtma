#!/bin/ksh --login
#
##########################################################################
#
#Script Name: ncl.ksh
# 
#     Author: Christopher Harrop
#             Forecast Systems Laboratory
#             325 Broadway R/FST
#             Boulder, CO. 80305
#
#   Released: 10/30/2003
#    Version: 1.0
#    Changes: None
#
# Purpose: This script generates NCL graphics from wrf output.  
#
#               EXE_ROOT = The full path of the ncl executables
#          DATAHOME = Top level directory of wrf output and
#                          configuration data.
#             START_TIME = The cycle time to use for the initial time. 
#                          If not set, the system clock is used.
#              FCST_TIME = The two-digit forecast that is to be ncled
# 
# A short and simple "control" script could be written to call this script
# or to submit this  script to a batch queueing  system.  Such a "control" 
# script  could  also  be  used to  set the above environment variables as 
# appropriate  for  a  particular experiment.  Batch  queueing options can
# be  specified on the command  line or  as directives at  the top of this
# script.  A set of default batch queueing directives is provided.
#
##########################################################################

if [ "${PBS_NODEFILE:-unset}" != "unset" ]; then
        THREADS=$(cat $PBS_NODEFILE | wc -l)
else
        THREADS=1
fi
echo "Using $THREADS thread(s) for procesing."

# Load modules (in jobs/launch.sh)
# export MODULE_FILE="/home/rtrr/PARM_EXEC/modulefiles/modulefile.jet.NCL"
# source ${MODULE_FILE}

# Make sure we are using GMT time zone for time computations
# export NCL_VER=6.1.2  # for testing
# export DATAROOT="/home/rtrr/hrrr"  # for testing
# export FCST_TIME=3  # for testing
# export START_TIME=2014111719  # for testing
export TZ="GMT"
export NCARG_ROOT="/apps/ncl/6.5.0-CentOS6.10_64bit_nodap_gnu447"
export NCARG_LIB="/apps/ncl/6.5.0-CentOS6.10_64bit_nodap_gnu447/lib"
export NCL_HOME="/whome/Brian.D.Jamison/fim/svncode/ncl/fimall"
export UDUNITS2_XML_PATH=$NCARG_ROOT/lib/ncarg/udunits/udunits2.xml

# Set up paths to shell commands
LS=/bin/ls
LN=/bin/ln
RM=/bin/rm
MKDIR=/bin/mkdir
CP=/bin/cp
MV=/bin/mv
ECHO=/bin/echo
CAT=/bin/cat
GREP=/bin/grep
CUT=/bin/cut
AWK="/bin/gawk --posix"
SED=/bin/sed
DATE=/bin/date
BC=/usr/bin/bc
XARGS=${XARGS:-/usr/bin/xargs}
BASH=${BASH:-/bin/bash}
NCL=`which ncl`
CTRANS=`which ctrans`
PS2PDF=/usr/bin/ps2pdf
CONVERT=`which convert`
MONTAGE=`which montage`
PATH=${NCARG_ROOT}/bin:${PATH}

# typeset -RZ2 FCST_TIME
# typeset -RZ2 FCST_TIME_AHEAD1
# typeset -RZ2 FCST_TIME_AHEAD2
# typeset -RZ2 FCST_TIME_BACK1
# typeset -RZ2 FCST_TIME_BACK3
typeset -Z6 j
typeset -Z6 k

# ulimit -s 512000
ulimit -s 1024000

EXE_ROOT=/misc/whome/wrfruc/bin/ncl/nclhrrr
EXE_ROOT2=/misc/whome/wrfruc/bin/ncl/nclhrrrdeveldiff

# Print run parameters
${ECHO}
${ECHO} "ncl.ksh started at `${DATE}`"
${ECHO}
${ECHO} "DATAROOT = ${DATAROOT}"
${ECHO} "DATAHOME = ${DATAHOME}"
${ECHO} "     EXE_ROOT = ${EXE_ROOT}"
${ECHO} "     EXE_ROOT2 = ${EXE_ROOT2}"

# Check to make sure the EXE_ROOT var was specified
if [ ! -d ${EXE_ROOT} ]; then
  ${ECHO} "ERROR: EXE_ROOT, '${EXE_ROOT}', does not exist"
  exit 1
fi
if [ ! -d ${EXE_ROOT2} ]; then
  ${ECHO} "ERROR: EXE_ROOT2, '${EXE_ROOT2}', does not exist"
  exit 1
fi

# Check to make sure that the DATAHOME exists
if [ ! -d ${DATAHOME} ]; then
  ${ECHO} "ERROR: DATAHOME, '${DATAHOME}', does not exist"
  exit 1
fi
# If START_TIME is not defined, use the current time
if [ ! "${START_TIME}" ]; then
  ${ECHO} "START_TIME not defined - get from date"
  START_TIME=$( date +"%Y%m%d %H" )
  START_TIME_BACK1=$( date +"%Y%m%d %H" -d "1 hour ago" )
  START_TIME_BACK2=$( date +"%Y%m%d %H" -d "2 hours ago" )
  START_TIME=$( date +"%Y%m%d%H" -d "${START_TIME}" )
  START_TIME_BACK1=$( date +"%Y%m%d%H" -d "${START_TIME_BACK1}" )
  START_TIME_BACK2=$( date +"%Y%m%d%H" -d "${START_TIME_BACK2}" )
else
  ${ECHO} "START_TIME defined and is ${START_TIME}"
  START_TIME=$( date +"%Y%m%d %H" -d "${START_TIME%??} ${START_TIME#????????}" )
  START_TIME_BACK1=$( date +"%Y%m%d %H" -d "${START_TIME} 1 hour ago" )
  START_TIME_BACK2=$( date +"%Y%m%d %H" -d "${START_TIME} 2 hours ago" )
  START_TIME=$( date +"%Y%m%d%H" -d "${START_TIME}" )
  START_TIME_BACK1=$( date +"%Y%m%d%H" -d "${START_TIME_BACK1}" )
  START_TIME_BACK2=$( date +"%Y%m%d%H" -d "${START_TIME_BACK2}" )
fi

set -x
NCLPRD=nclprd_inc
if [ ! ${NCLPRD} ]; then
  ${ECHO} "ERROR: NCLPRD, \$NCLPRD, is not defined."
  exit 1
fi
POSTPRD_ANL=postprd
anl_grb2=wrfprs_anl.grib2
POSTPRD_FGS=postprd_fgs
fgs_grb2=wrfprs_fgs.grib2
POSTPRD=postprd_inc
inc_grb2=wrfprs_inc.grib2
if [ ! ${POSTPRD} ]; then
  ${ECHO} "ERROR: POSTPRD, \$POSTPRD, is not defined."
  exit 1
fi
mkdir -p  ${DATAHOME}/${POSTPRD}
cd ${DATAHOME}/${POSTPRD}
if [ -f ${DATAHOME}/${POSTPRD_ANL}/wrfprs_hrconus_00.grib2 ] ; then
  rm -f ./${anl_grb2}
  ln -sf ${DATAHOME}/${POSTPRD_ANL}/wrfprs_hrconus_00.grib2  ./${anl_grb2}
else
  echo "missing ${DATAHOME}/${POSTPRD_ANL}/wrfprs_hrconus_00.grib2."
  exit 1
fi
if [ -f ${DATAHOME}/${POSTPRD_FGS}/wrfprs_hrconus_00.grib2 ] ; then
  rm -f ./${fgs_grb2}
  ln -sf ${DATAHOME}/${POSTPRD_FGS}/wrfprs_hrconus_00.grib2  ./${fgs_grb2}
else
  echo "missing ${DATAHOME}/${POSTPRD_fgs}/wrfprs_hrconus_00.grib2."
  exit 1
fi

rm -f ./${inc_grb2}
srun -n 1 wgrib2 ${anl_grb2} -var -lev -rpn "sto_1" -import_grib ${fgs_grb2} -rpn "sto_2" -set_grib_type same -rpn "rcl_1:rcl_2:-" -set_scaling same same -grib_out ${inc_grb2}
set +x
if [ -f ./${inc_grb2} ] ; then
  ln -sf ./${inc_grb2}  ${DATAHOME}/${POSTPRD}/wrfprs_hrconus_00.grib2
else
  echo "missing ${DATAHOME}/${POSTPRD}/${inc_grb2}"
  exit 1
fi

# To be valid at the same time, FCST_TIME_AHEAD1 matches with START_TIME_BACK1,
# and FCST_TIME_AHEAD2 matches with START_TIME_BACK2

FCST_TIME_AHEAD1=99
FCST_TIME_AHEAD2=99
if (( ${FCST_TIME} <= 22 )); then
  FCST_TIME_AHEAD1=$(($FCST_TIME + 1))
  FCST_TIME_AHEAD2=$(($FCST_TIME + 2))
else
  if (( ${FCST_TIME} == 23 )); then
    FCST_TIME_AHEAD1=$(($FCST_TIME + 1))
  fi
fi

# These used for 1hr 80m wind speed change, and esbl 1h 80m change
FCST_TIME_BACK1=-9
if (( ${FCST_TIME} >= 1 )); then
  FCST_TIME_BACK1=$(($FCST_TIME - 1))
fi

# Used for 3h pressure change
FCST_TIME_BACK3=-9
if (( ${FCST_TIME} >= 3 )); then
  FCST_TIME_BACK3=$(($FCST_TIME - 3))
fi

# Print out times
# ${ECHO} "   START TIME = "`${DATE} +%Y%m%d%H -d "${START_TIME}"`
${ECHO} "   START_TIME = ${START_TIME}"
${ECHO} "   START_TIME_BACK1 = ${START_TIME_BACK1}"
${ECHO} "   START_TIME_BACK2 = ${START_TIME_BACK2}"
${ECHO} "   FCST_TIME = ${FCST_TIME}"
${ECHO} "   FCST_TIME_AHEAD1 = ${FCST_TIME_AHEAD1}"
${ECHO} "   FCST_TIME_AHEAD2 = ${FCST_TIME_AHEAD2}"
${ECHO} "   FCST_TIME_BACK1 = ${FCST_TIME_BACK1}"
if (( ${FCST_TIME} <= 3 )); then
  ${ECHO} "   FCST_TIME_BACK3 = ${FCST_TIME_BACK3}"
fi

# Set up the work directory and cd into it
# workdir=nclprd/${FCST_TIME}part1   # for testing
workdir=${DATAHOME}/${NCLPRD}/${FCST_TIME}
${RM} -rf ${workdir}
${MKDIR} -p ${workdir}
cd ${workdir}

# Link to input file
BACK1_DATAROOT=${DATAROOT}/${START_TIME_BACK1}
BACK2_DATAROOT=${DATAROOT}/${START_TIME_BACK2}
# DATAHOME=${DATAROOT}/${START_TIME}  # for testing
${LN} -s ${DATAHOME}/${POSTPRD}/wrfprs_hrconus_${FCST_TIME}.grib2 hrrrfile.grb
${ECHO} "hrrrfile.grb" > arw_file.txt
if (( ${FCST_TIME_AHEAD1} != 99 )); then
  ${LN} -s ${BACK1_DATAROOT}/${POSTPRD}/wrfprs_hrconus_${FCST_TIME_AHEAD1}.grib2 back1file.grb
  ${ECHO} "back1file.grb" > back1_file.txt
  ${LN} -s ${BACK1_DATAROOT}/${POSTPRD}/wrfprs_hrconus_${FCST_TIME}.grib2 back1fileback1hour.grb
  ${ECHO} "back1fileback1hour.grb" > back1_file_back1_hour.txt
fi
if (( ${FCST_TIME_AHEAD2} != 99 )); then
  ${LN} -s ${BACK2_DATAROOT}/${POSTPRD}/wrfprs_hrconus_${FCST_TIME_AHEAD2}.grib2 back2file.grb
  ${ECHO} "back2file.grb" > back2_file.txt
  ${LN} -s ${BACK2_DATAROOT}/${POSTPRD}/wrfprs_hrconus_${FCST_TIME_AHEAD1}.grib2 back2fileback1hour.grb
  ${ECHO} "back2fileback1hour.grb" > back2_file_back1_hour.txt
fi
if (( ${FCST_TIME_BACK1} != -9 )); then
  ${LN} -s ${DATAHOME}/${POSTPRD}/wrfprs_hrconus_${FCST_TIME_BACK1}.grib2 back1hour.grb
  ${ECHO} "back1hour.grb" > back1_hour.txt
fi
if (( ${FCST_TIME_BACK3} != -9 )); then
  ${LN} -s ${DATAHOME}/${POSTPRD}/wrfprs_hrconus_${FCST_TIME_BACK3}.grib2 back3file.grb
  ${ECHO} "back3file.grb" > back3_file.txt
fi

ls -al hrrrfile.grb
ls -al back1file.grb
ls -al back1fileback1hour.grb
ls -al back2file.grb
ls -al back2fileback1hour.grb
ls -al back1hour.grb
ls -al back3file.grb

set -A ncgms  sfc_temp   \
              2m_temp    \
              2m_ptemp   \
              2m_dewp    \
              2m_rh      \
              2ds_temp   \
              10m_wind   \
              80m_wind   \
              80m_wchg   \
              850_wind   \
              250_wind   \
              ua_vort    \
              sfc_pwtr   \
              sfc_totp   \
              sfc_cref   \
              sfc_ptyp   \
              sfc_cape   \
              sfc_cin    \
              sfc_acp    \
              sfc_weasd  \
              sfc_1hsnw  \
              sfc_acsnw  \
              sfc_snod   \
              sfc_acsnod \
              sfc_acpcp  \
              sfc_sfcp   \
              sfc_hpbl   \
              ua_rh      \
              ua_rh8     \
              sfc_rhpw   \
              ua_vvel    \
              sfc_vis    \
              ua_ceil    \
              ua_ctop    \
              max_wind   \
              10m_gust   \
              mdn_wind   \
              mup_wind   \
              esbl_hlcy  \
              esbl_cref  \
              esbl_wchg  \
              esbl_acp   \
              esblmn_acp \
              esbl_totp  \
              esblmn_totp \
              esbl_acsnw \
              esblmn_acsnw \
              esbl_hvyacp \
              sfc_hlcy  \
              mx16_hlcy \
              in25_hlcy \
              in16_hlcy \
              sfc_ca1   \
              sfc_ca2   \
              sfc_ca3   \
              sfc_ci1   \
              sfc_ci2   \
              sfc_ci3   \
              sfc_ltg1  \
              sfc_ltg2  \
              sfc_ltg3  \
              sfc_pchg  \
              sfc_lcl   \
              sfc_tcc   \
              sfc_lcc   \
              sfc_mcc   \
              sfc_hcc   \
              sfc_mnvv  \
              sfc_mref  \
              sfc_mucp  \
              sfc_mulcp \
              sfc_mxcp  \
              sfc_1hsm  \
              sfc_3hsm  \
              sfc_vig   \
              sfc_s1shr \
              sfc_6kshr \
              500_temp  \
              700_temp  \
              850_temp  \
              925_temp  \
              sfc_1ref  \
              sfc_bli   \
              nta_ulwrf \
              sfc_lhtfl \
              sfc_shtfl \
              sfc_flru  \
              80m_wpwr  \
              sfc_solar \
              sfc_ectp  \
              sfc_vil   \
              sfc_rvil  \
              sat_G113bt \
              sat_G114bt \
              sat_G123bt \
              sat_G124bt \
              sfc_cpofp  \
              sfc_vbdsf  \
              sfc_vddsf  \
              m10_ref    \
              sfc_ssrun  \
              sfc_3hssrun

# set -A monpngs montage.png

set -A webpfx temp temp ptemp dewp rh temp wind wind wchg wind wind vort pwtr totp cref \
              ptyp cape cin acp weasd 1hsnw acsnw snod acsnod cpcp sfcp hpbl rh rh rhpw vvel vis ceil ctop \
              wind gust wind wind hlcy cref wchg acp acp totp totp acsnw acsnw hvyacp hlcy hlcy hlcy hlcy ca1 ca2 ca3 \
              ci1 ci2 ci3 ltg1 ltg2 ltg3 pchg lcl tcc lcc mcc hcc \
              mnvv mref mucp mulcp mxcp 1hsm 3hsm vig s1shr 6kshr temp temp temp temp \
              1ref bli ulwrf lhtfl shtfl flru wpwr solar ectp vil rvil G113bt G114bt G123bt G124bt \
              cpofp vbdsf vddsf ref ssrun 3hssrun

set -A fhr 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15

set -A websfx sfc 2m 2m 2m 2m 2ds 10m 80m 80m 850 250 500 sfc sfc sfc sfc sfc sfc sfc sfc \
              sfc sfc sfc sfc sfc sfc sfc 500 850 sfc 700 sfc ua ua max 10m mdn mup esbl esbl esbl esbl \
              esblmn esbl esblmn esbl esblmn esbl sfc mx16 in25 in16 sfc sfc sfc sfc sfc sfc sfc sfc sfc sfc sfc sfc sfc \
              sfc sfc sfc sfc sfc sfc sfc sfc sfc sfc sfc sfc 500 700 850 925 sfc sfc nta sfc sfc \
              sfc 80m sfc sfc sfc sfc sat sat sat sat sfc sfc sfc m10 sfc sfc

set -A tiles dum t1 t2 t3 t4 t5 t6 t7 t8 z0 z1 z2 z3 z4 z5 z6 z7

# set -A webmon montage

i=0
p=0
while [ ${i} -lt ${#ncgms[@]} ]; do
  j=000000
  k=000000
  numtiles=${#tiles[@]}
  (( numtiles=numtiles - 1 ))  
  while [ ${j} -le ${numtiles} ]; do
    (( k=j + 1 ))  
    pngs[${p}]=${ncgms[${i}]}.${k}.png
#    echo ${pngs[${p}]}
    if [ ${j} -eq 000000 ]; then 
      if [ "${websfx[${i}]}" = "ua" ]; then 
        webnames[${p}]=${webpfx[${i}]}
      else 
        webnames[${p}]=${webpfx[${i}]}_${websfx[${i}]}
      fi   
    else 
      if [ "${websfx[${i}]}" = "ua" ]; then 
        webnames[${p}]=${webpfx[${i}]}_${tiles[${j}]}
      else 
        webnames[${p}]=${webpfx[${i}]}_${tiles[${j}]}${websfx[${i}]}
      fi   
    fi   
#    echo ${webnames[${p}]}
    (( j=j + 1 ))  
# p is total number of images (image index)
    (( p=p + 1 ))  
  done 
  (( i=i + 1 ))  
done

ncl_error=0

# Run the NCL scripts for each plot
cp /whome/wrfruc/bin/ncl/Airpor* .
# cp ${EXE_ROOT}/names_grib2.txt .
  cp ${EXE_ROOT2}/names_grib2.txt .
i=0
echo "FIRST While, ${#ncgms[@]} items"
CMDFN=/tmp/cmd.hrrr_part1.$$
${RM} -f $CMDFN

while [ ${i} -lt ${#ncgms[@]} ]; do

  plot=${ncgms[${i}]}
  ${ECHO} "Starting rr_${plot}.ncl at `${DATE}`"
#  ${NCL} < ${EXE_ROOT}/rr_${plot}.ncl
#  error=$?
#  if [ ${error} -ne 0 ]; then
#    ${ECHO} "ERROR: rr_${plot} crashed!  Exit status=${error}"
#    ncl_error=${error}
#  fi
#  ${ECHO} "Finished rr_${plot}.ncl at `${DATE}`"

# echo ${NCL} ${EXE_ROOT}/rr_${plot}.ncl >> $CMDFN
  echo ${NCL} ${EXE_ROOT2}/rrdiff_${plot}.ncl >> $CMDFN

  (( i=i + 1 ))

done

${CAT} $CMDFN | ${XARGS} -P $THREADS -I {} ${BASH} -c "{}" 
ncl_error=$?
${RM} -f $CMDFN

# # Run ctrans on all the .ncgm files to translate them into Sun Raster files
# i=0
# while [ ${i} -lt ${#ncgms[@]} ]; do
# 
#   plot=${ncgms[${i}]}
# #  ${ECHO} "Starting ctrans for ${plot}.ncgm at `${DATE}`"
# ## normal image
# #  ${CTRANS} -d sun ${plot}.ncgm -resolution 1132x906 > ${plot}.ras
# #
# ## montage image
# #  ${CTRANS} -d sun ${plot}.ncgm -resolution 2678x1673 > ${plot}_mon.ras
# #
# #  error=$?
# #  if [ ${error} -ne 0 ]; then
# #    ${ECHO} "ERROR: ctrans ${plot}.ncgm crashed!  Exit status=${error}"
# #    ncl_error=${error}
# #  fi
# #  ${ECHO} "Finished ctrans for ${plot}.ncgm at `${DATE}`"
# 
#   echo "${CTRANS} -d sun ${plot}.ncgm -resolution 1132x906 > ${plot}.ras" >> $CMDFN
#   echo "${CTRANS} -d sun ${plot}.ncgm -resolution 2678x1673 > ${plot}_mon.ras" >> $CMDFN
# 
#   (( i=i + 1 )) 
# 
# done
# 
# ${CAT} $CMDFN | ${XARGS} -P $THREADS -I {} ${BASH} -c "{}" 
# ncl_error=$?
# ${RM} -f $CMDFN
# 
# # Convert the .ras files into .png files
# i=0
# while [ ${i} -lt ${#ncgms[@]} ]; do
# 
#   plot=${ncgms[${i}]}
#   ${ECHO} "Starting convert for ${plot}.ras at `${DATE}`"
# 
#   if [ -s ${plot}.ras ]; then 
# # normal image
# #    ${CONVERT} -colors 128 -trim -border 5x5 -bordercolor black ${plot}.ras ${plot}.png
# #    error=$?
# #    if [ ${error} -ne 0 ]; then
# #      ${ECHO} "ERROR: convert ${plot}.ras crashed!  Exit status=${error}"
# #      ncl_error=${error}
# #    fi
#    echo ${CONVERT} -colors 128 -trim -border 5x5 -bordercolor black ${plot}.ras ${plot}.png >> $CMDFN
#    
#   else 
#     ${ECHO} "No file to convert, exit gracefully"
#     ncl_error=0
#   fi
#   ${ECHO} "Finished convert for ${plot}.ras at `${DATE}`"
# 
#   if [ -s ${plot}_mon.ras ]; then 
# # montage image
# #    ${CONVERT} -colors 128 -trim -border 190x12 -bordercolor black ${plot}_mon.ras ${plot}_mon.png
# #    error=$?
# #    if [ ${error} -ne 0 ]; then
# #      ${ECHO} "ERROR: convert ${plot}_mon.ras crashed!  Exit status=${error}"
# #      ncl_error=${error}
# #    fi
#     echo ${CONVERT} -colors 128 -trim -border 190x12 -bordercolor black ${plot}_mon.ras ${plot}_mon.png >> $CMDFN
#   else 
#     ${ECHO} "No file to convert, exit gracefully"
#     ncl_error=0
#   fi
#   ${ECHO} "Finished convert for ${plot}_mon.ras at `${DATE}`"
# 
#   (( i=i + 1 )) 
#   
# done
# 
# ${CAT} $CMDFN | ${XARGS} -P $THREADS -I {} ${BASH} -c "{}" 
# ncl_error=$?
# ${RM} -f $CMDFN
# 
# # put together the montage images
# ${MONTAGE} sfc_cref_mon-0.png 2m_temp_mon-0.png 10m_wind_mon-0.png ua_ceil_mon-0.png -tile 2x2 -geometry 1877x1048+21+4 -background black montage.png

# Copy png files to their proper names
i=0
while [ ${i} -lt ${#pngs[@]} ]; do
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  fulldir=${DATAHOME}/${NCLPRD}/full
  ${MKDIR} -p ${fulldir}
  webfile=${fulldir}/${webnames[${i}]}_f${FCST_TIME}.png
#  webfile=${webnames[${i}]}_f${FCST_TIME}.png    # for testing
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  t1dir=${DATAHOME}/${NCLPRD}/t1
  ${MKDIR} -p ${t1dir}
  webfile=${t1dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  t2dir=${DATAHOME}/${NCLPRD}/t2
  ${MKDIR} -p ${t2dir}
  webfile=${t2dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  t3dir=${DATAHOME}/${NCLPRD}/t3
  ${MKDIR} -p ${t3dir}
  webfile=${t3dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  t4dir=${DATAHOME}/${NCLPRD}/t4
  ${MKDIR} -p ${t4dir}
  webfile=${t4dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  t5dir=${DATAHOME}/${NCLPRD}/t5
  ${MKDIR} -p ${t5dir}
  webfile=${t5dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  t6dir=${DATAHOME}/${NCLPRD}/t6
  ${MKDIR} -p ${t6dir}
  webfile=${t6dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  t7dir=${DATAHOME}/${NCLPRD}/t7
  ${MKDIR} -p ${t7dir}
  webfile=${t7dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  t8dir=${DATAHOME}/${NCLPRD}/t8
  ${MKDIR} -p ${t8dir}
  webfile=${t8dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  z0dir=${DATAHOME}/${NCLPRD}/z0
  ${MKDIR} -p ${z0dir}
  webfile=${z0dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  z1dir=${DATAHOME}/${NCLPRD}/z1
  ${MKDIR} -p ${z1dir}
  webfile=${z1dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  z2dir=${DATAHOME}/${NCLPRD}/z2
  ${MKDIR} -p ${z2dir}
  webfile=${z2dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  z3dir=${DATAHOME}/${NCLPRD}/z3
  ${MKDIR} -p ${z3dir}
  webfile=${z3dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  z4dir=${DATAHOME}/${NCLPRD}/z4
  ${MKDIR} -p ${z4dir}
  webfile=${z4dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  z5dir=${DATAHOME}/${NCLPRD}/z5
  ${MKDIR} -p ${z5dir}
  webfile=${z5dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  z6dir=${DATAHOME}/${NCLPRD}/z6
  ${MKDIR} -p ${z6dir}
  webfile=${z6dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
  pngfile=${pngs[${i}]}
  ${CONVERT} -trim ${pngfile} ${pngfile}
  z7dir=${DATAHOME}/${NCLPRD}/z7
  ${MKDIR} -p ${z7dir}
  webfile=${z7dir}/${webnames[${i}]}_f${FCST_TIME}.png
  ${MV} ${pngfile} ${webfile}
  (( i=i + 1 ))
done

# # Copy montage files to their proper names
# i=0
# while [ ${i} -lt ${#monpngs[@]} ]; do
#   pngfile=${monpngs[${i}]}
#   fulldir=${DATAHOME}/${NCLPRD}/full
#   ${MKDIR} -p ${fulldir}
#   webfile=${fulldir}/${webmon[${i}]}_f${FCST_TIME}.png
# #   webfile=${webmon[${i}]}_f${FCST_TIME}.png    # for testing
#   ${MV} ${pngfile} ${webfile}
# 
#   (( i=i + 1 ))
# done

# Remove the workdir
${RM} -rf ${workdir}

${ECHO} "ncl.ksh completed at `${DATE}`"

exit ${ncl_error}
