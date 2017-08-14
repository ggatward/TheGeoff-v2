#!/usr/bin/env groovy


// Variables that need to be referenced by multiple 'node' blocks need to be defined outside the blocks
def gitUrl = ''
def masterBranch = ''
def sat_params = ''
def devHash = ''
def devHashShort = ''
def soeMinorVer = ''
def vmwHost = ''
def vmwDC = ''
def vmwCluster = ''
def vmwTemplFolder = ''


// Only 1 concurrent build is allowed at a time.
// Newer builds are pulled off the queue first. When a build reaches the
// milestone at the end of the lock, all jobs started prior to the current
// build that are still waiting for the lock will be aborted
lock(resource: 'Deployment', inversePrecedence: true){
  node('soe') {
    wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
      // Wipe the workspace so we are building completely clean
      deleteDir()

      // Notify the relevent parties that the build has started (Only if NOT user initiated)
      if(user.toString() == 'SYSTEM') {
        notifyStarted(config.notifyEnabled)
      }

      // This initial checkout is light-weight so we can determine our current branch
      checkout scm
      devHash = sh(returnStdout: true, script:"git rev-parse HEAD")
      devHashShort = devHash[0..6]

      // Load the per-branch configuration file (YML)
      loadBranchConfig("${BRANCH_NAME}")

      // Set local defs from config yml
      soeMajorVer = config.soeMajorVer
      gitUrl = config.git.gitUrl
      masterBranch = config.git.masterBranch
      def sat_org = config.satellite.sat_org
      def sat_host = config.satellite.sat_host
      def sat_user = config.satellite.sat_user
      def r10k_user = config.satellite.r10k_user
      def puppet_locs = config.satellite.puppet_locs
      vmwHost = config.VMware.vmwHost
      vmwDC = config.VMware.vmwDC
      vmwCluster = config.VMware.vmwCluster
      vmwTemplFolder = config.VMware.vmwTemplFolder
      // String the common elements needed by the scripts into a single param for convenience
      sat_params = sat_org + " " + sat_host + " " + sat_user

      stage('Checkout') {
        // Now we can do a full checkout including cleaning our workspace (we can't do that with the lightweight checkout)
        checkout([$class: 'GitSCM', branches: [[name: "*/${BRANCH_NAME}"]],
          doGenerateSubmoduleConfigurations: false,
          extensions: [[$class: 'CleanBeforeCheckout']],
          submoduleCfg: [],
          userRemoteConfigs: [[url: gitUrl]]
        ])

        // Extract the latest tag so we can build the version (Default to 0 if no tags present)
        def lastTagMinor = sh(returnStdout: true, script:"git describe --tags \$(git rev-list --tags --max-count=1) | cut -f2 -d.").trim()
        if (lastTagMinor == '') {
          lastTagMinor = '0'
        }

        if (BRANCH_NAME == masterBranch) {
          version = soeMajorVer + "." + lastTagMinor
          echo 'Deploying production SOE version ' + version
        } else {
           // Increment minor version.
          int lastTagMinorInt = lastTagMinor as Integer
          int MinorVer = (lastTagMinorInt + 1)
          soeMinorVer = MinorVer as String

          version = soeMajorVer + "." + soeMinorVer + "-" + currentBuild.number.toString().padLeft(3,'0')
          echo 'Building ' + BRANCH_NAME + ' SOE version ' + version + "-git-" + devHashShort
        }

        // Set a default jobstatus. This variable is used to trap the return code from shell scripts.
        def jobstatus = 0
      }

      // Push kickstart artefacts to Satellite.
      // The artefacts should be marked as either dev or prod within the Git branch.
      stage('Push Kickstarts') {
        jobstatus = sh(returnStatus: true, script:". ci-scripts/pushkickstarts.sh ${sat_params} kickstarts")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }
      }


      // Push puppet modules to Satellite via r10k. The puppet environment uses the current Git branch in the name.
      stage('Deploy Puppet Modules') {
        jobstatus = sh(returnStatus: true, script:". ci-scripts/r10kdeploy.sh ${sat_params} RHEL_SOE_${BRANCH_NAME} ${r10k_user} ${puppet_locs}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }
      }

      // stash the project so far so we can unstash to each parallel branch
      stash name: 'RHEL_SOE'
    }
  } // end of node


  // If we have set buildHosts to 'false' we need to cleanly exit here.
  echo "DEBUG: buildHosts = " + config.buildHosts
  if (config.buildHosts == false) {
    echo "Build/test of hosts not requested"
    return
  }
  try {
    // ** Parallel execution example from https://jenkins.io/doc/pipeline/examples : 'Parallel From List'
    stage('Build VMs') {
      // Define an empty array to hold our parallel tasks
      def rebuildInParallel = [:]
      def jobResults = [:]


      // If we are building full KS hosts, loop through the defined hosts and add parallel tasks for each
      if (config.buildKS) {
        for (i in config.ksHosts) {
          def host = i.name
          def bootMethod = i.reboot

          // Convert into a step and add it to the map as the value.
          def stepName = "KS ${host}"
          rebuildInParallel[stepName] = ksRebuildSteps(sat_params, host, bootMethod, vmwHost)
        }
      }


      // If we are building Template hosts, loop through the defined hosts and add parallel tasks for each
      if (config.buildTemplates) {
        if (BRANCH_NAME != masterBranch) {
          for (i in config.templKsHosts) {
            def host = i.name
            def bootMethod = i.reboot

            // Convert into a step and add it to the map as the value.
            def stepName = "KS Template ${host}"
            rebuildInParallel[stepName] = templRebuildSteps(sat_params, host, bootMethod, vmwHost)
          }
        }  // End of 'if development...'
      }    // End of 'build templates'
      // Run the parallel tasks. The steps within the rebuild are defined in the '***RebuildSteps' function(s)
//      parallel rebuildInParallel
    }      // End of 'Build Test VMs' stage


    // If we are building Template hosts, perform the image cloning steps next
    if (config.buildTemplates) {
      if (BRANCH_NAME != masterBranch) {
        stage('VMWare Templating') {
          // Define an empty array to hold our parallel tasks
          def cloneInParallel = [:]
          def jobResults = [:]

          for (i in config.templKsHosts) {
            // Pull the defined RHEL version for this host
            def host = i.name
            def rhelVer = i.template

            // Convert into a step
            def stepName = "Cloning ${host}"
            cloneInParallel[stepName] = cloneSteps(sat_params, host, rhelVer, vmwHost, vmwDC, vmwCluster, vmwTemplFolder)
          }

          // Run the parallel tasks. The steps within the rebuild are defined in the '***RebuildSteps' function(s)
          parallel cloneInParallel

        } // End of 'VMware Templating' stage

        stage('Deploy VMs') {
          // Define an empty array to hold our parallel tasks
          def deployInParallel = [:]
          def jobResults = [:]

          for (i in config.templHosts) {
            def host = i.name

            // Convert into a step
            def stepName = "Deploying ${host}"
            deployInParallel[stepName] = deploySteps(sat_params, host, vmwHost, vmwDC, vmwCluster, vmwTemplFolder)
          }

          // Run the parallel tasks. The steps within the rebuild are defined in the '***RebuildSteps' function(s)
          parallel deployInParallel

        } // End of 'Deploy VMs' stage
      }   // End of 'if development...'
    }     // End of 'Build Templates' block


    stage('Functional Tests') {
      // Define an empty array to hold our parallel tasks
      def testInParallel = [:]
      def jobResults = [:]

      // If we are building full KS hosts, loop through the defined hosts and add parallel tasks for each
      if (config.buildKS) {
        for (i in config.ksHosts) {
          def host = i.name
          // Convert into a step and add it to the map as the value, with a name for the parallel step as the key.
          def stepName = "Testing ${host}"
          testInParallel[stepName] = testSteps(sat_params, host)
        }
      }

      // If we are building Template hosts, loop through the defined hosts and add parallel tasks for each
      if (config.buildTemplates) {
        for (i in config.templHosts) {
          def host = i.name

          // Convert into a step and add it to the map as the value, with a name for the parallel step as the key.
          def stepName = "Testing ${host}"
          testInParallel[stepName] = testSteps(sat_params, host)
        }
      }

      // Run the parallel tasks. The steps within the rebuild are defined in the '***RebuildSteps' function(s)
      parallel testInParallel

    } // End of 'Functional Tests' stage
  }
  finally {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()

        // Unstash the test results for each test host
        if (config.buildKS) {
          for (i in config.ksHosts) {
            def host = i.name
            unstash "testresults_${host}"
          }
        }

        // Unstash the test results for each test host
        if (config.buildTemplates) {
          for (i in config.templHosts) {
            def host = i.name
            unstash "testresults_${host}"
          }
        }


      // Try to display the converted JUnit tests
//        junit allowEmptyResults: true, testResults: 'test_results/*.xml'


        // Process the aggregated TAP results
        step([$class: 'TapPublisher',
          discardOldReports: true,
          enableSubtests: false,
          failIfNoResults: true,
          failedTestsMarkBuildAsFailure: true,
          flattenTapResult: false,
          includeCommentDiagnostics: false,
          outputTapToConsole: true,
          planRequired: true,
          showOnlyFailures: false,
          skipIfBuildNotOk: true,
          stripSingleParents: false,
          testResults: 'test_results/*.tap',
          todoIsFailure: false,
          validateNumberOfTests: true,
          verbose: true,
        ])
      }
    }
  }
  // If we got here we can add an icon to the build history to show success so far
  manager.addBadge('success.gif',"Passed all tests")

} // Release 'Deployment' lock

// Approval & Promotion are only relevant if we are running the dev branch
if (BRANCH_NAME != masterBranch) {
  stage('Approval') {
    def userInput = true
    def didTimeout = false
    try {
      milestone()
      notifyPromoteReady()
//      timeout(time:1, unit:'DAYS') {
      timeout(time:1, unit:'HOURS') {
//      timeout(time:1, unit:'MINUTES') {
        userInput = input(message: "Approve promotion to ${masterBranch}?")
      }
    } catch(err) { // Timeout or Abort selected
      def appUser = err.getCauses()[0].getUser()
      if('SYSTEM' == appUser.toString()) {  // SYSTEM means timeout.
        didTimeout = true
        echo 'Approval timeout reached, or superseded by newer build'
      } else {
        userInput = false
        echo "Aborted by: [${appUser}]"
      }
    }
    if (didTimeout) {
      currentBuild.result = 'ABORTED'
      return
    } else if (userInput == false) {
      currentBuild.result = 'ABORTED'
      return
    } else {
      // If we approve promotion we will pass this milestone. Any jobs older than this one
      // still waiting for promotion will be aborted
      milestone()
    }
  }

  // If we have aborted earlier, return to the higher level here so that the next stage is not run
  if (currentBuild.result == 'ABORTED') {
    return
  }

  stage('Promotion') {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // create a lock so only one promote can run at a time
        lock(resource: 'Promotion', inversePrecedence: true) {
          // Checkout the master branch
          checkout([$class: 'GitSCM', branches: [[name: "master"]],
            doGenerateSubmoduleConfigurations: false,
            extensions: [[$class: 'CleanBeforeCheckout']],
            submoduleCfg: [],
            userRemoteConfigs: [[url: gitUrl]]
          ])

          def jobstatus = 0

          // The above gives us an 'untracked' master (detached HEAD). Checkout master to reattach
          sh 'git checkout master'

          // new we can merge our development branch into master
          def user = user.toString()
          sh "git merge ${devHash}"

          // Next we need to manipulate the artefacts to 'productionise' them
          jobstatus = sh(returnStatus: true, script:". ci-scripts/promote.sh ${devHashShort} ${soeMajorVer} ${soeMinorVer}")
          if (jobstatus != 0) {
            notifyFailed()
            error 'Exiting due to script errors'
          }

          // Finally we need to commit the finished master branch and push back to git
          sh "git commit -a -m 'dev-to-prod replacements'"
          sh "git push"
          sh "git tag -a v${soeMajorVer}.${soeMinorVer} -m 'Promotion'"
          sh "git push --tags"

          // And to make the display nice we will add the tag to the dev build history
          manager.addBadge('green.gif',"v${soeMajorVer}.${soeMinorVer}")


        } // Release 'Promotion' lock
      }
    }     // End Node
  }       // End Stage
}



///////////////////////////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////////////////////////

// Steps for rebuilding a Kickstart host
//    - Full Kickstart (defined by Satellite host group membership)
def ksRebuildSteps(sat_params, host, bootMethod, vmwHost) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()

        echo("Building ${host}...")
        // Extract our stashed git repos to the new workspace
        unstash 'RHEL_SOE'
        jobstatus = sh(returnStatus: true, script:". ci-scripts/buildtestvms.sh ${sat_params} ${host} ${bootMethod}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }
        // If we are using Jenkins to reboot via vCenter we do that bit here...
        if (bootMethod == 'vmware') {
          withCredentials([usernamePassword(credentialsId: 'JenkinsVmw', usernameVariable: 'vmwuser', passwordVariable: 'vmwpass')]) {
            ansiblePlaybook(
              colorized: true,
              credentialsId: '99b1cb01-3542-4059-bbc3-1d01cb5f942e',
              installation: 'Ansible',
              inventory: 'ci-scripts/ansible/hosts',
              playbook: 'ci-scripts/ansible/reboot_vmware.yml',
              sudoUser: null,
              extraVars: [
                host: "${host}",
                vmwhost: "${vmwHost}",
                vmwuser: "${vmwuser}",
                vmwpass: [value: "${vmwpass}", hidden: true],
              ])
          }
        }

        jobstatus = sh(returnStatus: true, script:". ci-scripts/waitforbuild.sh ${sat_params} ${host}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }
      }
    }
  }
}

// Steps for rebuilding a gold template host
//    - Basic Kickstart (defined by Satellite host group membership)
//    - Convert to Template
//    - Deploy template to required environments (uses user_post script to customise image)
def templRebuildSteps(sat_params, host, bootMethod, vmwHost) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()

        echo("Building ${host}...")
        // Extract our stashed git repos to the new workspace
        unstash 'RHEL_SOE'
        jobstatus = sh(returnStatus: true, script:". ci-scripts/buildtestvms.sh ${sat_params} ${host} ${bootMethod}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }

        // If we are using Jenkins to reboot via vCenter we do that bit here...
        if (bootMethod == 'vmware') {
          withCredentials([usernamePassword(credentialsId: 'JenkinsVmw', usernameVariable: 'vmwuser', passwordVariable: 'vmwpass')]) {
            ansiblePlaybook(
              colorized: true,
              credentialsId: '99b1cb01-3542-4059-bbc3-1d01cb5f942e',
              installation: 'Ansible',
              inventory: 'ci-scripts/ansible/hosts',
              playbook: 'ci-scripts/ansible/reboot_vmware.yml',
              sudoUser: null,
              extraVars: [
                host: "${host}",
                vmwhost: "${vmwHost}",
                vmwuser: "${vmwuser}",
                vmwpass: [value: "${vmwpass}", hidden: true],
              ])
          }
        }

        jobstatus = sh(returnStatus: true, script:". ci-scripts/waitforbuild.sh ${sat_params} ${host}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }

        // Login to the built host and run the 'sysprep' script to anonymise it
        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'SOE_ROOT',
          usernameVariable: 'USERNAME', passwordVariable: 'ROOTPASS']]) {
          jobstatus = sh(returnStatus: true, script:". ci-scripts/sysprep.sh ${sat_params} ${host} ${ROOTPASS}")
          if (jobstatus != 0) {
            notifyFailed()
            error 'Exiting due to script errors'
          }
        }
      }
    }
  }
}

def cloneSteps(sat_params, host, rhelVer, vmwHost, vmwDC, vmwCluster, vmwTemplFolder) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()
        unstash 'RHEL_SOE'

        // Delete the old template first (uses vSphere plugin)
        vSphere buildStep: [$class: 'Delete',
          failOnNoExist: false,
          vm: "${rhelVer}_Dev_Template"], serverName: 'vcenter_server'

        // We can't clone a VM without a snapshot, so lets take one, after deleting the existing one
        vSphere buildStep: [$class: 'DeleteSnapshot',
          consolidate: false,
          failOnNoExist: false,
          snapshotName: "${host}-snap",
          vm: "${host}"], serverName: 'vcenter_server'

        vSphere buildStep: [$class: 'TakeSnapshot',
          description: 'Post KS snapshot',
          includeMemory: false,
          snapshotName: "${host}-snap",
          vm: "${host}"], serverName: 'vcenter_server'

        // Now we clone the built VM and then convert that clone into a template.
        // We do this with an Ansible play as the vsphere plugin doesnt work properly.
        // (Ultimately we could run all vSphere actions via ansible but currently
        // snapshots don't work 100% via ansible)
        withCredentials([usernamePassword(credentialsId: 'JenkinsVmw',
          usernameVariable: 'vmwuser', passwordVariable: 'vmwpass')]) {
          ansiblePlaybook(
            colorized: true,
            credentialsId: '99b1cb01-3542-4059-bbc3-1d01cb5f942e',
            installation: 'Ansible',
            inventory: 'ci-scripts/ansible/hosts',
            playbook: 'ci-scripts/ansible/create_template.yml',
            sudoUser: null,
            extraVars: [
              host: "${host}",
              template: "${rhelVer}_Dev_Template",
              vmwhost: "${vmwHost}",
              vmwdc: "${vmwDC}",
              vmwcluster: "${vmwCluster}",
              vmwfolder: "${vmwTemplFolder}",
              vmwuser: "${vmwuser}",
              vmwpass: [value: "${vmwpass}", hidden: true],
            ])
        }

        // Redeploy template test VM  (redeploy buildbot3/4 but need to fix MAC address?)

      }
    }
  }
}


// Function to deploy VMs from our template images
def deploySteps(sat_params, host, vmwHost, vmwDC, vmwCluster, vmwTemplFolder) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()
        unstash 'RHEL_SOE'

        // Reprovision VMs via Satellite
        jobstatus = sh(returnStatus: true, script:". ci-scripts/deployvmw.sh ${sat_params} ${host}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }


      }
    }
  }
}


// Function defining our TAPS testing
def testSteps(sat_params, host) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()

        echo("Testing ${host}...")
        // Extract our stashed git repos to the new workspace
        unstash 'RHEL_SOE'

        // Get the build host root password from the Jenkins Credential Store
        // Use that to run the bats tests (needs root ssh)
        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'SOE_ROOT',
          usernameVariable: 'USERNAME', passwordVariable: 'ROOTPASS']]) {
            jobstatus = sh(returnStatus: true, script:". ci-scripts/pushtests.sh ${sat_params} ${host} ${ROOTPASS}")
            if (jobstatus != 0) {
              notifyFailed()
              error "Exiting due to script errors (jobstatus = ${jobstatus})"
            }
          }
        // Archive the test results for aggregation later
        stash includes: 'test_results/*.tap,test_results/*.xml', name: "testresults_${host}"
      }
    }
  }
}


//    notifyComplete()
//} catch (e) {
//    currentBuild.result = "FAILED"
//    notifyFailed()
//    throw e
//}


/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////
// Define functions used within pipeline

// Function to read per-branch YML configuration
def loadBranchConfig(String branch) {
  if (fileExists("./${branch}.yml")) {
    config = readYaml file: "./${branch}.yml"
    println "config ==> ${config}"
  } else {
    println "Loading defaults for Jenkinsfile development"
    config = readYaml file: "./default.yml"
    println "config ==> ${config}"
  }
}

// Email functions
def notifyStarted() {
  if (config.notifyEnabled) {
    emailext (
      body: "<p>Started running SOE build</p>",
      subject: "Jenkins Build Started: Job \'${env.JOB_NAME} [${env.BUILD_NUMBER}]\'",
      recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']],
      replyTo: 'noreply@example.com',
      mimeType: 'text/html'
    )
  }
}

def notifyPromoteReady() {
  emailext (
    body: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has completed successfully and is now eligible for promotion.</p><p>Please go to this link to approve: <a href='${env.BUILD_URL}..'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a></p>",
    subject: "SUCCESSFUL: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
    recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']],
    replyTo: 'noreply@example.com',
    mimeType: 'text/html'
  )
}

def notifyComplete() {
  emailext (
    body: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has been promoted to production successfully</p>",
    subject: "COMPLETED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
    recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']],
    replyTo: 'noreply@example.com',
    mimeType: 'text/html'
  )
}

def notifyFailed() {
  emailext (
    attachLog: true,
    body: "<p>Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has failed.</p><p>Please go to this link: <a href='${env.BUILD_URL}'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a></p>",
    subject: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
    recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']],
    replyTo: 'noreply@example.com',
    mimeType: 'text/html'
  )
}
