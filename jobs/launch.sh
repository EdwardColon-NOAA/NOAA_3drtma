#!/bin/bash -l

# --- for debug --- #
date
export PS4=' $SECONDS + ' 
set -x

COMMAND=$1
kwd_task="POST"

#############################################################
# load modulefile and set up the environment for job runnning
#############################################################
MODULEFILES=${MODULEFILES:-${HOMErtma3d}/modulefiles}

if [ "${machine}" = "theia" ] ; then
  module purge
# . /etc/profile
# . /apps/lmod/lmod/init/bash >/dev/null # Module Support
  case "$COMMAND" in
    *"${kwd_task}"*)
      modulefile_run=${modulefile_run:-"${MODULEFILES}/${machine}/run/modulefile.run.post.${machine}"}
      ;;
    *)
      modulefile_run=${modulefile_run:-"${MODULEFILES}/${machine}/run/modulefile.run.gsi.${machine}"}
      ;;
  esac
  source $modulefile_run
  module list
elif [ "${machine}" = "jet" ] ; then
  module purge
# . /etc/profile
# . /apps/lmod/lmod/init/bash >/dev/null # Module Support
  case "$COMMAND" in
    *"${kwd_task}"*)
      modulefile_run=${modulefile_run:-"${MODULEFILES}/${machine}/run/modulefile.run.post.${machine}"}
      ;;
    *)
      modulefile_run=${modulefile_run:-"${MODULEFILES}/${machine}/run/modulefile.run.gsi.${machine}"}
      ;;
  esac
  source $modulefile_run
  module list
else
  echo "modulefile has not set up for this unknow machine. Job abort!"
  exit 1
fi

###########################################################################
# obtain unique process id (pid) and define the name of  temp directories
###########################################################################
if [ "${machine}" = "theia" ] ; then    ### PBS job Scheduler
  export job=${job:-"${PBS_JOBNAME}"}    # job is defined as job name
  export jid=`echo ${PBS_JOBID} | cut -f1 -d.`  # removal of tailing sub-server string
# export jid=`echo ${PBS_JOBID} | awk -F'.' '{print $1}'`
  export jobid=${jobid:-"${job}.${jid}"}
  export np=`cat $PBS_NODEFILE | wc -l`
  export NCDUMP="ncdump"
  export MPIRUN=${MPIRUN:-"mpirun -np $np"}
  echo " number of cores : $np for job $job with id as $jobid "
elif [ "${machine}" = "jet" ] ;  then    ### PBS job Scheduler
  export job=${job:-"${PBS_JOBNAME}"}    # job is defined as job name
  export jid=`echo ${PBS_JOBID} | cut -f1 -d.`  # removal of tailing sub-server string
# export jid=`echo ${PBS_JOBID} | awk -F'.' '{print $1}'`
  export jobid=${jobid:-"${job}.${jid}"}
  export np=`cat $PBS_NODEFILE | wc -l`
  export NCDUMP="ncdump"
  export MPIRUN=${MPIRUN:-"mpirun -np $np"}
  echo " number of cores : $np for job $job with id as $jobid "
elif [ "${machine}" = "wcoss" ] ; then  ### LSB scheduler
  export job=${job:-"${LSB_JOBNAME}"}    # job is defined as job name
  export jid=`echo ${LSB_JOBID} `
  export jobid=${jobid:-"${job}.${jid}"}
  echo " job $job with id as $jobid "
  export MPIRUN=${MPIRUN:-"aprun"}
else
  export job=${job:-"${outid}.o$$"}
  export jobid=${jobid:-"${outid}.o$$"}
  export jid=$$
  export MPIRUN=${MPIRUN:-"mpirun"}
fi

############################################################
# Notice: the following line is to                         #
#            name the running directory with job name.     #
#                              (not used for NCO.)         #
############################################################
if [ "${rundir_task}" ]; then
  export DATA=${rundir_task}.${jid}
fi

$COMMAND
