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

# -------------#
# Write SSM tag 
# -------------#

echo 'postbuild: writing SSM tag to instance' >> $centrifycc_deploy_dir/deploy.log 2>&1

InstanceID=$(curl --fail -s http://169.254.169.254/latest/meta-data/instance-id)
[[ -z ${InstanceID}]] && echo 'postbuild: instanceID is null, check http://169.254.169.254/latest/meta-data/instance-id' >> $centrifycc_deploy_dir/deploy.log 2>&1

if ! mkdir -m 700 ~root/.aws;
then
    echo 'postbuild: failed to create ~root/.aws' >> $centrifycc_deploy_dir/deploy.log 2>&1; exit 1
fi

# Write aws cli config

cat << EOF > ~root/.aws/config
[default]
region=eu-west-2
output=json
EOF

CheckSize=$(stat -c %s ~root/.aws/config)
if [ "$CheckSize" -gt 0 ];
then
    echo 'postbuild: ~root/.aws/config created OK' >> $centrifycc_deploy_dir/deploy.log 2>&1
    chmod 400 ~root/.aws/config
else
    echo 'postbuild: creation of ~root/.aws/config failed' >> $centrifycc_deploy_dir/deploy.log 2>&1;exit 1
fi

# Write aws cli credentials from PAS secrets

AWSAccessKeyID=$(${CENTRIFY_CCLI_BIN} /Redrock/query -s -m -ms postbuild -j "{ 'Script':'select DataVault.ID,DataVault.SecretName from DataVault where DataVault.SecretName = \'AWS-AccessKeyID\' ' }" | jq -r '.Result.Results [] | .Row | .ID')
AWSSecretAccessKey=$(${CENTRIFY_CCLI_BIN} /Redrock/query -s -m -ms postbuild -j "{ 'Script':'select DataVault.ID,DataVault.SecretName from DataVault where DataVault.SecretName = \'AWS-SecretAccessKey\' ' }" | jq -r '.Result.Results [] | .Row | .ID')

shopt -s nocasematch
  [[ "${AWSAccessKey}" =~ .*"null".* ]] && echo 'failed to get AWS-AccessKey secret ID from PAS DB - ccli returned ['${AWSAccessKey}']' >> $centrifycc_deploy_dir/deploy.log 2>&1 
  [[ "${AWSSecretAccessKey}" =~ .*"null".* ]] && echo 'failed to get AWS-SecretAccessKey secret ID from PAS DB - ccli returned ['${AWSSecretAccessKey}']' >> $centrifycc_deploy_dir/deploy.log 2>&1 
shopt -u nocasematch

if ! echo "[default]" > ~root/.aws/credentials
then
    echo 'postbuild: creation of ~root/.aws/credentials failed' >> $centrifycc_deploy_dir/deploy.log 2>&1;exit 1
else
    echo 'postbuild: ~root/.aws/credentials created OK' >> $centrifycc_deploy_dir/deploy.log 2>&1
    chmod 400 ~root/.aws/credentials
    if ! ${CENTRIFY_CCLI_BIN} /ServerManage/RetrieveSecretContents -s -m -ms postbuild -j "{'ID': '$AWSAccessKey'}" | jq -r '.Result | .SecretText' >> ~root/.aws/credentials
    then
        echo 'postbuild: failed to write AWS AccessKey ID to ~root/.aws/credentials' >> $centrifycc_deploy_dir/deploy.log 2>&1;exit 1
        if ! ${CENTRIFY_CCLI_BIN} /ServerManage/RetrieveSecretContents -s -m -ms postbuild -j "{'ID': '$AWSSecretAccessKey'}" | jq -r '.Result | .SecretText' >> ~root/.aws/credentials
        then
            echo 'postbuild: failed to write AWS AccessKey ID to ~root/.aws/credentials' >> $centrifycc_deploy_dir/deploy.log 2>&1;exit 1
        fi
    fi
else
    CheckSum=$(md5sum ~root/.aws/credentials | awk '{print $1}')
    [[ -z "$CheckSum"]] && echo 'postbuild: could not md5sum ~root/.aws/credentials $CheckSum' >> $centrifycc_deploy_dir/deploy.log 2>&1
    [[ "$CheckSum" -ne "c3022e6375f3c86a83880eddac86398c" ]] && echo 'postbuild: checksum validation on ~root/.aws/credentials failed' >> $centrifycc_deploy_dir/deploy.log 2>&1;exit 1

    if ! aws ec2 create-tags --resources $InstanceID --tags Key=ASGroup,value=CentrifyUnix >> $centrifycc_deploy_dir/deploy.log 2>&1;
    then
        echo 'postbuild: aws cli failed to write EC2 SSM tag on $InstanceID [Key=ASGroup,value=CentrifyUnix]' >> $centrifycc_deploy_dir/deploy.log 2>&1;exit 1
    else
        echo 'postbuild: aws cli wrote EC2 SSM tag on $InstanceID' >> $centrifycc_deploy_dir/deploy.log 2>&1
    fi
fi

echo 'postbuild: completed OK' >> $centrifycc_deploy_dir/deploy.log 2>&1
