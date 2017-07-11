ENVPATH=$1
logger -t r10k "Deploying $ENVPATH"
for i in `ls $ENVPATH`; do
  ln -sd $ENVPATH/$i /etc/puppet/environments/$i
  unlink $ENVPATH/$i/$i

  # Create/Update puppet environments in Satellite
#  PUPPET_LOCATIONS=HOME,REMOTE,SITE3
  PUPPET_LOCATIONS=HOME
  if [ $(hammer environment list | awk '/^[0-9]/ { print $3 }' | grep -c $i) -eq 0 ]; then
    hammer environment create --name $i --locations ${PUPPET_LOCATIONS} --organizations DIG
  else
    hammer environment update --name $i --locations ${PUPPET_LOCATIONS} --organizations DIG
  fi

  # Import the puppet classes
  hammer proxy import-classes --id 1 --environment $i
done

# rsync to capusles
for capsule in $(hammer --csv capsule list | grep -iv Id | cut -f2 -d,); do
  logger -t r10k "Deploying puppet modules for $ENVPATH to $capsule"
  rsync -avz --delete $ENVPATH/* $capsule:$ENVPATH
  ssh -q $capsule "for i in \$(ls ${ENVPATH}); do ln -sf ${ENVPATH}/\$i /etc/puppet environments/\$i; done"
  ssh -q $capsule "for i in \$(ls ${ENVPATH}); do unlink ${ENVPATH}/\$i/\$i; done"
done


