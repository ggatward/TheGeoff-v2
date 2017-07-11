#!/bin/bash

# Search for kickstarts within our SOE repo

# Syntax  pushkickstart.sh <ORG> <SATELLITE> <SAT_USER> <kickstart dir>

# Read in common parameter variables
ORG=$1
SATELLITE=$2
SAT_USER=$3

# Script-specific inpirt
workdir=$4

# setup artefacts environment
ARTEFACTS=artefacts/kickstarts
mkdir -p $ARTEFACTS

# copy erb files from the main SOE directory to a specific kickstart artefact dir (clean temp space)
rsync -td --out-format="#%n#" --delete-excluded --include=*.erb --exclude=* "${workdir}/" \
	"${ARTEFACTS}" | grep -e '\.erb#$'

# sync our kickstart artefect dir with the one in our homedir on Satellite. We delete extraneous 
# kickstarts on the satellite so that we don't keep pushing obsolete kickstarts into satellite
rsync --delete -va -e "ssh -q -l ${SAT_USER}" -va ${ARTEFACTS} ${SATELLITE}:

# either update or create each kickstart in turn
cd ${ARTEFACTS}
for I in *.erb; do
  name=$(sed -n 's/^name:\s*\(.*\)/\1/p' ${I})
  id=0
  id=$(ssh -q -l ${SAT_USER} ${SATELLITE} \
            "/usr/bin/hammer --csv template list --per-page 9999" | grep ",${name}" | cut -d, -f1)
  ttype=$(sed -n 's/^kind:\s*\(.*\)/\1/p' ${I})
  if [[ ${id} -ne 0 ]]; then
    ssh -q -l ${SAT_USER} ${SATELLITE} \
      "/usr/bin/hammer template update --id ${id} --file kickstarts/${I} --type ${ttype}"
  else
    ssh -q -l ${SAT_USER} ${SATELLITE} \
      "/usr/bin/hammer template create --file kickstarts/${I} --name \"${name}\" --type ${ttype} --organizations \"${ORG}\""
  fi
done


