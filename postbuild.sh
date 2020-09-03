#!/bin/bash

################################################################################
#
# Copyright 2017-2018 Centrify Corporation
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Sample poistbuild script AWS autoscaling orchestration with CentrifyCC
#

CSTATUS=$(cinfo --clientchannel-status | awk -F: '{print $2}' | awk '{print $1}')
echo "checking cagent backchannel post install [Status:"${CSTATUS}"] ..." >> $centrifycc_deploy_dir/deploy.log 2>&1

if [ "${CSTATUS}" != "Online" ];
then
    WaitLoop=1
    WaitTotal=10
    while [ ${WaitLoop} -lt ${WaitTotal} ];
    do
      CSTATUS=$(cinfo --clientchannel-status | awk -F: '{print $2}' | awk '{print $1}')
      if [ "${CSTATUS}" == "Online" ];
      then
        echo "cagent backchannel status is "${CSTATUS} >> $centrifycc_deploy_dir/deploy.log 2>&1
        break
      else 
        echo "waiting to see if cagent backchannel comes online post install "$WaitLoop" of "${WaitTotal}" [Status:"${CSTATUS}"] ..." >> $centrifycc_deploy_dir/deploy.log 2>&1
        sleep 5
      fi
      ((WaitLoop++))
    done
else 
    echo "cagent backchannel status is "${CSTATUS}
fi

#
# handle if the back channel does not come online, last attempt - restart service
#

CSTATUS=$(cinfo --clientchannel-status | awk -F: '{print $2}' | awk '{print $1}')
CAGENT_PATH="/opt/centrify/sbin/cagent -operation"

if [ "${CSTATUS}" != "Online" ];
then
  echo "cagent backchannel not online, restarting service" >> $centrifycc_deploy_dir/deploy.log 2>&1
  $CAGENT_PATH stop >> $centrifycc_deploy_dir/deploy.log 2>&1;
  CPID=$(pgrep cagent)
  while [ ! -z "${CPID}" ]
  do
    echo 'waiting for cagent to die after '$(CAGENT)" stop"  >> $centrifycc_deploy_dir/deploy.log 2>&1
    sleep 1
    CPID=$(pgrep cagent)
  done

  if ! $CAGENT_PATH start >> $centrifycc_deploy_dir/deploy.log 2>&1;
  then
      echo "restart cagent service failed" >> $centrifycc_deploy_dir/deploy.log 2>&1
      exit 1
  else 
      echo "restart cagent service succesfull" >> $centrifycc_deploy_dir/deploy.log 2>&1
  fi

  WaitLoop=1
  WaitTotal=10
  while [ ${WaitLoop} -lt ${WaitTotal} ];
    do
      CSTATUS=$(cinfo --clientchannel-status | awk -F: '{print $2}' | awk '{print $1}')
      if [ "${CSTATUS}" == "Online" ];
      then
        echo "cagent backchannel status is "${CSTATUS} >> $centrifycc_deploy_dir/deploy.log 2>&1
        break
      else 
        echo "waiting to see if cagent backchannel comes online post restart "$WaitLoop" of "${WaitTotal}" [Status:"${CSTATUS}"] ..." >> $centrifycc_deploy_dir/deploy.log 2>&1
        sleep 5
      fi
      ((WaitLoop++))
    done
fi

CSTATUS=$(cinfo --clientchannel-status | awk -F: '{print $2}' | awk '{print $1}')

if [ "${CSTATUS}" != "Online" ];
then
  echo "client backchannel is not online after waiting and service restart -  fatal" >> $centrifycc_deploy_dir/deploy.log 2>&1
  cinfo -V >> $centrifycc_deploy_dir/deploy.log 2>&1
  exit 1
fi

# vault ec2-user and mark to be managed

OTP=`openssl rand -base64 8`  >> $centrifycc_deploy_dir/deploy.log 2>&1
echo $OTP | passwd --stdin ec2-user >> $centrifycc_deploy_dir/deploy.log 2>&1
if ! csetaccount --managed true --password ${OTP} --permission \"role:AWS-ec2-user-access:View,Login\" ec2-user >> $centrifycc_deploy_dir/deploy.log 2>&1;
then
  echo 'csetaccount failed' >> $centrifycc_deploy_dir/deploy.log 2>&1
fi

echo "postbuild: starting" >> $centrifycc_deploy_dir/deploy.log 2>&1

#
# Install ccli
#

export CENTRIFY_CCLI_GIT_PATH='https://github.com/centrify/centrifycli/releases/download/v1.0.5.0/ccli-v1.0.5.0-linux-x64.tar.gz'
export CENTRIFY_CCLI_BIN_PATH='/usr/local/bin'
export CENTRIFY_CCLI_BIN=$CENTRIFY_CCLI_BIN_PATH'/ccli'
export CENTRIFY_CCLI_DL='/tmp/ccli.tar.gz'

if ! curl --silent --fail -o ${CENTRIFY_CCLI_DL} -L ${CENTRIFY_CCLI_GIT_PATH} >> $centrifycc_deploy_dir/deploy.log 2>&1;
then
  echo "curl download of ccli failed" >> $centrifycc_deploy_dir/deploy.log 2>&1 
  exit 1
else
  echo "postbuild: "${CENTRIFY_CCLI}" bundle created from "${CENTRIFY_CCLI_GIT_PATH} >> $centrifycc_deploy_dir/deploy.log 2>&1 
fi

if ! tar -C ${CENTRIFY_CCLI_BIN_PATH} -xf ${CENTRIFY_CCLI_DL} >> $centrifycc_deploy_dir/deploy.log 2>&1;
then
  echo "postbuild: tar extract of ccli failed" >> $centrifycc_deploy_dir/deploy.log 2>&1
  exit 1
else 
  echo "postbuild: ccli installed "${CENTRIFY_CCLI_BIN} >> $centrifycc_deploy_dir/deploy.log 2>&1
  chmod 700 ${CENTRIFY_CCLI_BIN} >> $centrifycc_deploy_dir/deploy.log 2>&1
  chown root:root ${CENTRIFY_CCLI_BIN} >> $centrifycc_deploy_dir/deploy.log 2>&1
  echo "postbuild: ccli initialization starts" >> $centrifycc_deploy_dir/deploy.log 2>&1
  ${CENTRIFY_CCLI_BIN} -url https://${CENTRIFYCC_TENANT_URL} saveconfig >> $centrifycc_deploy_dir/deploy.log 2>&1 
  rm -f ${CENTRIFY_CCLI_DL}
  echo "postbuild: ccli initialization completed" >> $centrifycc_deploy_dir/deploy.log 2>&1
fi

#
# Install jq
#

if ! yum -y -q install jq >> $centrifycc_deploy_dir/deploy.log 2>&1;
then
  echo "postbuild: failed to install jq via yum" >> $centrifycc_deploy_dir/deploy.log 2>&1
  exit 1
else
    echo "postbuild: jq installed" >> $centrifycc_deploy_dir/deploy.log 2>&1
fi

#
# Pull Customer Registered Centrify REPO and SUDOERS.D from PAS vault secrets using ccli
#

echo "postbuild: deploying repo & sudo files from "${CENTRIFYCC_TENANT_URL} >> $centrifycc_deploy_dir/deploy.log 2>&1 

RepoID=$(${CENTRIFY_CCLI_BIN} /Redrock/query -s -m -ms postbuild -j "{ 'Script':'select DataVault.ID,DataVault.SecretName from DataVault where DataVault.SecretName = \'centrify.repo\' ' }" | jq -r '.Result.Results [] | .Row | .ID')
SudoID=$(${CENTRIFY_CCLI_BIN} /Redrock/query -s -m -ms postbuild -j "{ 'Script':'select DataVault.ID,DataVault.SecretName from DataVault where DataVault.SecretName = \'centrify.sudo\' ' }" | jq -r '.Result.Results [] | .Row | .ID')

shopt -s nocasematch
  [[ "${RepoID}" =~ .*"null".* ]] && echo 'failed to get centrify.repo secret ID from PAS DB - ccli returned ['${RepoID}']' >> $centrifycc_deploy_dir/deploy.log 2>&1 
  [[ "${SudoID}" =~ .*"null".* ]] && echo 'failed to get centrify.sudo secret ID from PAS DB - ccli returned ['${SudoID}']' >> $centrifycc_deploy_dir/deploy.log 2>&1 
shopt -u nocasematch

if ! ${CENTRIFY_CCLI_BIN} /ServerManage/RetrieveSecretContents -s -m -ms postbuild -j "{'ID': '$RepoID'}" | jq -r '.Result | .SecretText' > /etc/yum.repos.d/centrify.repo;
then 
    echo 'postbuild: failed to create /etc/yum.repos.d/centrify.repo' >> $centrifycc_deploy_dir/deploy.log 2>&1
else
    echo 'postbuild: deployed /etc/yum.repos.d/centrify.repo OK' >> $centrifycc_deploy_dir/deploy.log 2>&1
fi

if ! ${CENTRIFY_CCLI_BIN} /ServerManage/RetrieveSecretContents -s -m -ms postbuild -j "{'ID': '$SudoID'}" | jq -r '.Result | .SecretText' > /etc/sudoers.d/centrify;
then 
    echo 'postbuild: failed to create /etc/sudoers.d/centrify' >> $centrifycc_deploy_dir/deploy.log 2>&1
else 
    echo 'postbuild: deployed /etc/sudoers.d/centrify OK' >> $centrifycc_deploy_dir/deploy.log 2>&1
fi

# Define OS owner:perms for postbuild files

for FileName in /etc/sudoers.d/centrify /etc/yum.repos.d/centrify.repo;
do
  chown root:root $FileName >> $centrifycc_deploy_dir/deploy.log 2>&1
  chmod 640 $FileName >> $centrifycc_deploy_dir/deploy.log 2>&1
done

# Set GB TimeZone

echo 'postbuild: setting GB TimeZone in /etc/sysconfig/clock' >> $centrifycc_deploy_dir/deploy.log 2>&1
/bin/sed -i -r 's/ZONE="UTC"/ZONE="GB"/g' /etc/sysconfig/clock >> $centrifycc_deploy_dir/deploy.log 2>&1

echo 'postbuild: symbolically linking /usr/share/zoneinfo/GB /etc/localtime' >> $centrifycc_deploy_dir/deploy.log 2>&1
ln -sf /usr/share/zoneinfo/GB /etc/localtime >> $centrifycc_deploy_dir/deploy.log 2>&1

# what next - docs say a reboot - WTF

echo 'postbuild: completed OK' >> $centrifycc_deploy_dir/deploy.log 2>&1
