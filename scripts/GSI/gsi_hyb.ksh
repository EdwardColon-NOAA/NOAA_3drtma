#!/bin/ksh --login

np=`cat $PBS_NODEFILE | wc -l`

module load newdefaults
module load intel
module load impi

# Set up paths to unix commands
RM=/bin/rm
CP=/bin/cp
MV=/bin/mv
LN=/bin/ln
MKDIR=/bin/mkdir
CAT=/bin/cat
ECHO=/bin/echo
LS=/bin/ls
CUT=/bin/cut
WC=/usr/bin/wc
DATE=/bin/date
AWK="/bin/awk --posix"
SED=/bin/sed
TAIL=/usr/bin/tail
CNVGRIB=/apps/cnvgrib/1.2.3/bin/cnvgrib
MPIRUN=mpirun

# Set endian conversion options for use with Intel compilers
## export F_UFMTENDIAN="big;little:10,15,66"
## export F_UFMTENDIAN="big;little:10,13,15,66"
## export GMPIENVVAR=F_UFMTENDIAN
## export MV2_ON_DEMAND_THRESHOLD=256

# Set the path to the gsi executable
GSI=${GSI_ROOT}/HRRR_gsi_hyb

# Set the path to the GSI static files
fixdir=${FIX_ROOT}

# Make sure DATAHOME is defined and exists
if [ ! "${DATAHOME}" ]; then
  ${ECHO} "ERROR: \$DATAHOME is not defined!"
  exit 1
fi

#  PREPBUFR
if [ ! "${PREPBUFR}" ]; then
  ${ECHO} "ERROR: \$PREPBUFR is not defined!"
  exit 1
fi
if [ ! -d "${PREPBUFR}" ]; then
  ${ECHO} "ERROR: directory '${PREPBUFR}' does not exist!"
  exit 1
fi

#  NCEPSNOW
if [ ! "${NCEPSNOW}" ]; then  ${ECHO} "ERROR: \$NCEPSNOW is not defined!"
  exit 1
fi
if [ ! -d "${NCEPSNOW}" ]; then
  ${ECHO} "ERROR: directory '${NCEPSNOW}' does not exist!"
  exit 1
fi

# Make sure GSI_ROOT is defined and exists
if [ ! "${GSI_ROOT}" ]; then
  ${ECHO} "ERROR: \$GSI_ROOT is not defined!"
  exit 1
fi
if [ ! -d "${GSI_ROOT}" ]; then
  ${ECHO} "ERROR: GSI_ROOT directory '${GSI_ROOT}' does not exist!"
  exit 1
fi

# Make sure DATAHOME_BK is defined and exists
if [ ! "${DATAHOME_BK}" ]; then
  ${ECHO} "ERROR: \$DATAHOME_BK is not defined!"
  exit 1
fi
if [ ! -d "${DATAHOME_BK}" ]; then
  ${ECHO} "ERROR: DATAHOME_BK directory '${DATAHOME_BK}' does not exist!"
  exit 1
fi

# Check to make sure the number of processors for running GSI was specified
if [ -z "${GSIPROC}" ]; then
  ${ECHO} "ERROR: The variable $GSIPROC must be set to contain the number of processors to run GSI"
  exit 1
fi

# Check to make sure that STATIC_PATH exists
if [ ! -d ${STATIC_DIR} ]; then
  ${ECHO} "ERROR: ${STATIC_DIR} does not exist"
  exit 1
fi

# Check to make sure that ENKF_FCST exists
if [ ! -d ${ENKF_FCST} ]; then
  ${ECHO} "ERROR: ${ENKF_FCST} does not exist"
  exit 1
fi

# Check to make sure that FULLCYC exists
if [ ! "${FULLCYC}" ]; then
  ${ECHO} "ERROR: FULLCYC '${FULLCYC}' does not exist"
  exit 1
fi

# Make sure START_TIME is defined and in the correct format
if [ ! "${START_TIME}" ]; then
  ${ECHO} "ERROR: \$START_TIME is not defined!"
  exit 1
else
  if [ `${ECHO} "${START_TIME}" | ${AWK} '/^[[:digit:]]{10}$/'` ]; then
    START_TIME=`${ECHO} "${START_TIME}" | ${SED} 's/\([[:digit:]]\{2\}\)$/ \1/'`
  elif [ ! "`${ECHO} "${START_TIME}" | ${AWK} '/^[[:digit:]]{8}[[:blank:]]{1}[[:digit:]]{2}$/'`" ]; then
    ${ECHO} "ERROR: start time, '${START_TIME}', is not in 'yyyymmddhh' or 'yyyymmdd hh' format"
    exit 1
  fi
  START_TIME=`${DATE} -d "${START_TIME}"`
fi

# Make sure the GSI executable exists
if [ ! -x "${GSI}" ]; then
  ${ECHO} "ERROR: ${GSI} does not exist!"
  exit 1
fi

# Compute date & time components for the analysis time
YYYYJJJHH00=`${DATE} +"%Y%j%H00" -d "${START_TIME}"`
YYYYMMDDHH=`${DATE} +"%Y%m%d%H" -d "${START_TIME}"`
YYYYMMDD=`${DATE} +"%Y%m%d" -d "${START_TIME}"`
YYYY=`${DATE} +"%Y" -d "${START_TIME}"`
MM=`${DATE} +"%m" -d "${START_TIME}"`
DD=`${DATE} +"%d" -d "${START_TIME}"`
HH=`${DATE} +"%H" -d "${START_TIME}"`

# Create the working directory and cd into it
workdir=${DATAHOME}
${RM} -rf ${workdir}
${MKDIR} -p ${workdir}
# if [ "`stat -f -c %T ${workdir}`" == "lustre" ]; then
#  lfs setstripe --count 8 ${workdir}
# fi
cd ${workdir}

# Define the output log file depending on if this is the full or partial cycle
ifsoilnudge=.true.
if [ ${FULLCYC} -eq 0 ]; then
  logfile=${DATABASE_DIR}/loghistory/HRRR_GSI_HYB_PCYC.log
  ifsoilnudge=.true.
elif [ ${FULLCYC} -eq 1 ]; then
  logfile=${DATABASE_DIR}/loghistory/HRRR_GSI_HYB.log
  ifsoilnudge=.true.
elif [ ${FULLCYC} -eq 2 ]; then
  logfile=${DATABASE_DIR}/loghistory/HRRR_GSI_HYB_early.log
  ifsoilnudge=.true.
else  
  echo "ERROR: Unknown CYCLE ${FULLCYC} definition!"
  exit 1
fi

# Save a copy of the GSI executable in the workdir
${CP} ${GSI} .

# Bring over background field (it's modified by GSI so we can't link to it)
time_str=`${DATE} "+%Y-%m-%d_%H_%M_%S" -d "${START_TIME}"`
${ECHO} " time_str = ${time_str}"

# Look for bqckground from pre-forecast background
if [ -r ${DATAHOME_BK}/wrfout_d01_${time_str} ]; then
  ${ECHO} " Cycled run using ${DATAHOME_BK}/wrfout_d01_${time_str}"
  cp ${DATAHOME_BK}/wrfout_d01_${time_str} ./wrf_inout
  ${ECHO} " Cycle ${YYYYMMDDHH}: GSI background=${DATAHOME_BK}/wrfout_d01_${time_str}" >> ${logfile}

# No background available so abort
else
  ${ECHO} "${DATAHOME_BK}/wrfout_d01_${time_str} does not exist!!"
  ${ECHO} "ERROR: No background file for analysis at ${time_run}!!!!"
  ${ECHO} " Cycle ${YYYYMMDDHH}: GSI failed because of no background" >> ${logfile} 
  exit 1
fi

# Snow cover building and trimming currently set to run in the 00z cycle
update_snow='00'

# Compute date & time components for the snow cover analysis time relative to current analysis time
YYJJJHH00000000=`${DATE} +"%y%j%H00000000" -d "${START_TIME} 2 hours ago"`

if [[ ${HH} -eq ${update_snow} ]]; then
  echo "Update snow cover based on imssnow"
  if [ -r "${NCEPSNOW}/latest.SNOW_IMS" ]; then
     ${CP} ${NCEPSNOW}/latest.SNOW_IMS ./imssnow2
  elif [ -r "${NCEPSNOW}/${YYJJJHH00000000}" ]; then
     ${CP} ${NCEPSNOW}/${YYJJJHH00000000} ./imssnow2
  else
    ${ECHO} "${NCEPSNOW} data does not exist!!"
    ${ECHO} "ERROR: No snow triming for background at ${time_str}!!!!"
  fi  
  if [ -r "imssnow2" ]; then
     ${CNVGRIB} -g21 imssnow2 imssnow
     ${CP} ${STATIC_DIR}/WPS/geo_em.d01.nc ./geo_em.d01.nc
     ${CP} ${STATIC_DIR}/UPP/nam_imsmask ./nam_imsmask
     ${MPIRUN} -np 1 ${GSI_ROOT}/process_NESDIS_imssnow.exe > stdout_snowupdate 2>&1
  else
    ${ECHO} "ERROR: No imssnow2 file for snow triming for background at ${time_str}!!!!"
  fi  
else
  ${ECHO} "NOTE: No update for snow cover at ${time_str}!"
fi

# Update SST currently set to run in the 01z cycle
update_SST='01'

# Compute date & time components for the SST analysis time relative to current analysis time
YYJJJ00000000=`${DATE} +"%y%j00000000" -d "${START_TIME} 1 day ago"`
YYJJJ1200=`${DATE} +"%y%j1200" -d "${START_TIME} 1 day ago"`

if [ ${HH} -eq ${update_SST} ]; then
  echo "Update SST"
  if [ -r "${SST_ROOT}/latest.SST" ]; then
    cp ${SST_ROOT}/latest.SST .
  elif [ -r "${SST_ROOT}/${YYJJJ00000000}" ]; then
    cp ${SST_ROOT}/${YYJJJ00000000} latest.SST
  else
    ${ECHO} "${SST_ROOT} data does not exist!!"
    ${ECHO} "ERROR: No SST update at ${time_str}!!!!"
  fi  
  if [ -r "latest.SST" ]; then
    if [ -r "${SST_ROOT14km}/latest.ETA_SST" ]; then
      cp ${SST_ROOT14km}/latest.ETA_SST SST14km
    elif [ -r "${SST_ROOT14km}/${YYJJJ1200}.nam_grid" ]; then
      cp ${SST_ROOT14km}/${YYJJJ1200}.nam_grid SST14km
    else
      ${ECHO} "WARNING: No latest hi-res SST file for update at ${time_str}!!!!"
    fi  
    ${CNVGRIB} -g21 latest.SST SSTRTG
    ${CP} ${STATIC_DIR}/UPP/RTG_SST_landmask.dat ./RTG_SST_landmask.dat
    ${CP} ${STATIC_DIR}/WPS/geo_em.d01.nc ./geo_em.d01.nc
    ${MPIRUN} -np 1 ${GSI_ROOT}/process_SST.exe > stdout_sstupdate 2>&1
  else
    ${ECHO} "ERROR: No latest SST file for update at ${time_str}!!!!"
  fi  
else
  ${ECHO} "NOTE: No update for SST at ${time_str}!"
fi

# Link to the prepbufr data
${LN} -s ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.prepbufr ./prepbufr

if [ -r "${DATAOBSHOME}/NSSLRefInGSI.bufr" ]; then
  ${LN} -s ${DATAOBSHOME}/NSSLRefInGSI.bufr ./refInGSI
else
  ${ECHO} "Warning: ${DATAOBSHOME}/NSSLRefInGSI.bufr dones not exist!"
fi

if [ -r "${DATAOBSHOME}/LightningInGSI.bufr" ]; then
  ${LN} -s ${DATAOBSHOME}/LightningInGSI.bufr ./lghtInGSI
else
  ${ECHO} "Warning: ${DATAOBSHOME}/LightningInGSI.bufr dones not exist!"
fi

if [ -r "${DATAOBSHOME}/NASALaRCCloudInGSI_bufr.bufr" ]; then
  ${LN} -s ${DATAOBSHOME}/NASALaRCCloudInGSI_bufr.bufr ./larcInGSI
else
  ${ECHO} "Warning: ${DATAOBSHOME}/NASALaRCCloudInGSI_bufr.bufr does not exist!"
  ${ECHO} "Warning: try ${DATAOBSHOME}/NASALaRCCloudInGSI.bufr!"
  if [ -r "${DATAOBSHOME}/NASALaRCCloudInGSI.bufr" ]; then
    ${LN} -s ${DATAOBSHOME}/NASALaRCCloudInGSI.bufr ./larcInGSI
  else
    ${ECHO} "Warning: ${DATAOBSHOME}/NASALaRCCloudInGSI.bufr does not exist!"
  fi
fi

# Link statellite radiance data
# if [ -r "${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bamua" ]; then
#  ${LN} -s ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bamua ./amsuabufr
# else
#   ${ECHO} "Warning: ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bamua dones not exist!"
# fi
# if [ -r "${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bamub" ]; then
#   ${LN} -s ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bamub ./amsubbufr
# else
#   ${ECHO} "Warning: ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bamub dones not exist!"
# fi
# if [ -r "${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bhrs3" ]; then
#   ${LN} -s ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bhrs3 ./hirs3bufr
# else
#   ${ECHO} "Warning: ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bhrs3 dones not exist!"
# fi
# if [ -r "${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bhrs4" ]; then
#   ${LN} -s ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bhrs4 ./hirs4bufr
# else
#   ${ECHO} "Warning: ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bhrs4 dones not exist!"
# fi
# if [ -r "${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bmhs" ]; then
#   ${LN} -s ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bmhs ./mhsbufr
# else
#   ${ECHO} "Warning: ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.1bmhs dones not exist!"
# fi

# Link the radial velocity data

## if [ -r "${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.radwnd" ]; then
##   ${LN} -s ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.radwnd ./radarbufr
## else
##   ${ECHO} "Warning: ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.radwnd dones not exist!"
## fi
## if [ -r "${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.nexrad" ]; then
##   ${LN} -s ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.nexrad ./l2rwbufr
## else
##   ${ECHO} "Warning: ${DATAOBSHOME}/newgblav.${YYYYMMDD}.rap.t${HH}z.nexrad dones not exist!"
## fi

## 
## Find closest GFS EnKF forecast to analysis time
##
## 
## Link to pre-processed GFS EnKF forecast members
##
for mem in `ls ${DATAROOT}/gfsenkf/enspreproc_arw_mem???`
do
  memname=`basename ${mem}`
  ${LN} -s ${mem} ${memname}
done

${LS} enspreproc_arw_mem??? > filelist

# Determine if hybrid option is available
beta1_inv=1.0
ifhyb=.false.
nummem=`more filelist | wc -l`
nummem=$((nummem - 3 ))
if [[ ${nummem} -eq 80 ]]; then
  echo "Do hybrid with ${memname}"
  beta1_inv=0.25
  ifhyb=.true.
  ${ECHO} " Cycle ${YYYYMMDDHH}: GSI hybrid uses ${memname} with n_ens=${nummem}" >> ${logfile}
fi

# Set fixed files
#   berror   = forecast model background error statistics
#   specoef  = CRTM spectral coefficients
#   trncoef  = CRTM transmittance coefficients
#   emiscoef = CRTM coefficients for IR sea surface emissivity model
#   aerocoef = CRTM coefficients for aerosol effects
#   cldcoef  = CRTM coefficients for cloud effects
#   satinfo  = text file with information about assimilation of brightness temperatures
#   satangl  = angle dependent bias correction file (fixed in time)
#   pcpinfo  = text file with information about assimilation of prepcipitation rates
#   ozinfo   = text file with information about assimilation of ozone data
#   errtable = text file with obs error for conventional data (regional only)
#   convinfo = text file with information about assimilation of conventional data
#   bufrtable= text file ONLY needed for single obs test (oneobstest=.true.)
#   bftab_sst= bufr table for sst ONLY needed for sst retrieval (retrieval=.true.)

anavinfo=${fixdir}/anavinfo_arw_netcdf
BERROR=${fixdir}/rap_berror_stats_global_RAP_tune
SATANGL=${fixdir}/global_satangbias.txt
SATINFO=${fixdir}/global_satinfo.txt
CONVINFO=${fixdir}/nam_regional_convinfo_RAP.txt
OZINFO=${fixdir}/global_ozinfo.txt    
PCPINFO=${fixdir}/global_pcpinfo.txt
OBERROR=${fixdir}/nam_errtable.r3dv


# Fixed fields
cp $anavinfo anavinfo
cp $BERROR   berror_stats
cp $SATANGL  satbias_angle
cp $SATINFO  satinfo
cp $CONVINFO convinfo
cp $OZINFO   ozinfo
cp $PCPINFO  pcpinfo
cp $OBERROR  errtable

# CRTM Spectral and Transmittance coefficients
CRTMFIX=${fixdir}/CRTM_Coefficients
emiscoef_IRwater=${CRTMFIX}/Nalli.IRwater.EmisCoeff.bin
emiscoef_IRice=${CRTMFIX}/NPOESS.IRice.EmisCoeff.bin
emiscoef_IRland=${CRTMFIX}/NPOESS.IRland.EmisCoeff.bin
emiscoef_IRsnow=${CRTMFIX}/NPOESS.IRsnow.EmisCoeff.bin
emiscoef_VISice=${CRTMFIX}/NPOESS.VISice.EmisCoeff.bin
emiscoef_VISland=${CRTMFIX}/NPOESS.VISland.EmisCoeff.bin
emiscoef_VISsnow=${CRTMFIX}/NPOESS.VISsnow.EmisCoeff.bin
emiscoef_VISwater=${CRTMFIX}/NPOESS.VISwater.EmisCoeff.bin
emiscoef_MWwater=${CRTMFIX}/FASTEM5.MWwater.EmisCoeff.bin
aercoef=${CRTMFIX}/AerosolCoeff.bin
cldcoef=${CRTMFIX}/CloudCoeff.bin

ln -s $emiscoef_IRwater ./Nalli.IRwater.EmisCoeff.bin
ln -s $emiscoef_IRice ./NPOESS.IRice.EmisCoeff.bin
ln -s $emiscoef_IRsnow ./NPOESS.IRsnow.EmisCoeff.bin
ln -s $emiscoef_IRland ./NPOESS.IRland.EmisCoeff.bin
ln -s $emiscoef_VISice ./NPOESS.VISice.EmisCoeff.bin
ln -s $emiscoef_VISland ./NPOESS.VISland.EmisCoeff.bin
ln -s $emiscoef_VISsnow ./NPOESS.VISsnow.EmisCoeff.bin
ln -s $emiscoef_VISwater ./NPOESS.VISwater.EmisCoeff.bin
ln -s $emiscoef_MWwater ./FASTEM5.MWwater.EmisCoeff.bin
ln -s $aercoef  ./AerosolCoeff.bin
ln -s $cldcoef  ./CloudCoeff.bin

# Copy CRTM coefficient files based on entries in satinfo file
for file in `awk '{if($1!~"!"){print $1}}' ./satinfo | sort | uniq` ;do 
   ln -s ${CRTMFIX}/${file}.SpcCoeff.bin ./
   ln -s ${CRTMFIX}/${file}.TauCoeff.bin ./
done

# Get aircraft reject list
cp ${AIRCRAFT_REJECT}/current_bad_aircraft.txt current_bad_aircraft

sfcuselists=current_mesonet_uselist.txt
#sfcuselists=${YYYY}-${MM}-${DD}_meso_uselist.txt
sfcuselists_path=${SFCOBS_USELIST}
cp ${sfcuselists_path}/${sfcuselists} gsd_sfcobs_uselist.txt

cp ${fixdir}/gsd_sfcobs_provider.txt gsd_sfcobs_provider.txt

# Only need this file for single obs test
bufrtable=${fixdir}/prepobs_prep.bufrtable
cp $bufrtable ./prepobs_prep.bufrtable

# Set some parameters for use by the GSI executable and to build the namelist
export JCAP=62
export LEVS=60
export DELTIM=${DELTIM:-$((3600/($JCAP/20)))}
ndatrap=62
grid_ratio=4
cloudanalysistype=5

# Build the GSI namelist on-the-fly
. ${fixdir}/gsiparm.anl.sh
cat << EOF > gsiparm.anl
$gsi_namelist
EOF

## satellite bias correction
cp ${fixdir}/rap_satbias_starting_file.txt ./satbias_in
cp ${fixdir}/rap_satbias_pc_starting_file.txt ./satbias_pc

# Run GSI
${MPIRUN} -np $np ${GSI} < gsiparm.anl > stdout 2>&1
error=$?
if [ ${error} -ne 0 ]; then
  ${ECHO} "ERROR: ${GSI} crashed  Exit status=${error}"
  cp stdout ../.
  exit ${error}
fi

ls -l > GSI_workdir_list

# Look for successful completion messages in rsl files
nsuccess=`${TAIL} -20 stdout | ${AWK} '/PROGRAM GSI_ANL HAS ENDED/' | ${WC} -l`
ntotal=1 
${ECHO} "Found ${nsuccess} of ${ntotal} completion messages"
if [ ${nsuccess} -ne ${ntotal} ]; then
   ${ECHO} "ERROR: ${GSI} did not complete sucessfully  Exit status=${error}"
   cp stdout ../.
   cp GSI_workdir_list ../.
   if [ ${error} -ne 0 ]; then
     exit ${error}
   else
     exit 1
   fi
fi

# Loop over first and last outer loops to generate innovation
# diagnostic files for indicated observation types (groups)
#
# NOTE:  Since we set miter=2 in GSI namelist SETUP, outer
#        loop 03 will contain innovations with respect to 
#        the analysis.  Creation of o-a innovation files
#        is triggered by write_diag(3)=.true.  The setting
#        write_diag(1)=.true. turns on creation of o-g
#        innovation files.
#

loops="01 03"
for loop in $loops; do

case $loop in
  01) string=ges;;
  03) string=anl;;
   *) string=$loop;;
esac

#  Collect diagnostic files for obs types (groups) below
   listall="hirs2_n14 msu_n14 sndr_g08 sndr_g11 sndr_g11 sndr_g12 sndr_g13 sndr_g08_prep sndr_g11_prep sndr_g12_prep sndr_g13_prep sndrd1_g11 sndrd2_g11 sndrd3_g11 sndrd4_g11 sndrd1_g12 sndrd2_g12 sndrd3_g12 sndrd4_g12 sndrd1_g13 sndrd2_g13 sndrd3_g13 sndrd4_g13 hirs3_n15 hirs3_n16 hirs3_n17 amsua_n15 amsua_n16 amsua_n17 amsub_n15 amsub_n16 amsub_n17 hsb_aqua airs_aqua amsua_aqua imgr_g08 imgr_g11 imgr_g12 pcp_ssmi_dmsp pcp_tmi_trmm conv sbuv2_n16 sbuv2_n17 sbuv2_n18 omi_aura ssmi_f13 ssmi_f14 ssmi_f15 hirs4_n18 hirs4_metop-a amsua_n18 amsua_metop-a mhs_n18 mhs_metop-a amsre_low_aqua amsre_mid_aqua amsre_hig_aqua ssmis_las_f16 ssmis_uas_f16 ssmis_img_f16 ssmis_env_f16 iasi_metop-a"
   for type in $listall; do
      count=`ls pe*.${type}_${loop}* | wc -l`
      if [[ $count -gt 0 ]]; then
         `cat pe*.${type}_${loop}* > diag_${type}_${string}.${YYYYMMDDHH}`
      fi
   done
done

# save results from 1st run
${CP} fort.201    fit_p1.${YYYYMMDDHH}
${CP} fort.202    fit_w1.${YYYYMMDDHH}
${CP} fort.203    fit_t1.${YYYYMMDDHH}
${CP} fort.204    fit_q1.${YYYYMMDDHH}
${CP} fort.207    fit_rad1.${YYYYMMDDHH}
${CP} stdout      stdout_var
cat fort.* > ${DATABASE_DIR}/log/fits_${YYYYMMDDHH}.txt

## second GSI run

mv gsiparm.anl gsiparm.anl_var
mv sigf03 sigf03_step1
mv siganl sigf03

ndatrap=67
grid_ratio=1
cloudanalysistype=6
ifhyb=.false.

# Build the GSI namelist on-the-fly
. ${fixdir}/gsiparm.anl.sh
cat << EOF > gsiparm.anl
$gsi_namelist
EOF

# Run GSI
${MPIRUN} -np $np ${GSI} < gsiparm.anl > stdout 2>&1
error=$?
if [ ${error} -ne 0 ]; then
  ${ECHO} "ERROR: ${GSI} crashed  Exit status=${error}"
  cp stdout ../.
  exit ${error}
fi
ls -l > GSI_workdir_list_cloud

# Look for successful completion messages in rsl files
nsuccess=`${TAIL} -20 stdout | ${AWK} '/PROGRAM GSI_ANL HAS ENDED/' | ${WC} -l`
ntotal=1
${ECHO} "Found ${nsuccess} of ${ntotal} completion messages"
if [ ${nsuccess} -ne ${ntotal} ]; then
   ${ECHO} "ERROR: ${GSI} did not complete sucessfully  Exit status=${error}"
   cp stdout ../stdout_cloud
   cp GSI_workdir_list_cloud ../.
   if [ ${error} -ne 0 ]; then
     exit ${error}
   else
     exit 1
   fi
fi

exit 0