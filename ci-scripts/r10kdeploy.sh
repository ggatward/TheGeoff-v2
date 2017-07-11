#!/bin/bash 
 
# Push Puppet Modules out via r10k
#
# e.g. ${WORKSPACE}/scripts/r10kdeploy.sh
#
 
# Read in common parameter variables
ORG=$1
SATELLITE=$2
SAT_USER=$3

# Script-specific input
R10K_ENV=$4
R10K_USER=$5

# use hammer on the satellite to find all capsules. Then use R10K to push the modules
# into the puppet environmnet directory on each capsule
ssh -q -l ${R10K_USER} ${SATELLITE} \
    "cd /etc/puppet ; r10k deploy environment ${R10K_ENV} -c /etc/puppet/r10k/r10k_SOE.yaml -pv"

