#!/bin/bash
######################################################################################################################
#
# This is a single shell script that will create all the resources needed to deploy a ROSA HCP cluster via the CLI. The script will take care of:
#
# - Set up your AWS account and roles (eg. the account-wide IAM roles and policies, cluster-specific Operator roles and policies, and OpenID Connect (OIDC) identity provider).
# - Create the VPC;
# - Create your ROSA HCP Cluster with a minimal configuration (2 workers/Single-AZ; 3 workers/Multi-AZ).
#
# It takes approximately 15 minutes to create/destroy the cluster and its related VPC, AWS roles, etc.
#
#
# Once you are ready to delete it, the script will perform the reverse deleting what was previously created.
# It will look for the "$CLUSTER_LOG" file in order to be able to identify some resources (i.e. VPC_Id, Subnets, ...).
#
# Feel free to modify it in order to suits your needs.
#
########################################################################################################################
#
# About the author:
#
# Owner: 	Gianfranco Mollo
# GitHub: 	https://github.com/gmolloATredhat
# 		https://github.com/joemolls
# License: 	GNU GENERAL PUBLIC LICENSE (GPL)
# 
#
########################################################################################################################
############################################################
# Custom name                                              #
############################################################
NOW=$(date +"%y%m%d%H%M")
CLUSTER_NAME=${1:-gm-$NOW}
PREFIX=${2:-TestManagedHCP}
############################################################
# Delete HCP                                               #
############################################################
Delete_HCP()
{
#set -x
INSTALL_DIR=$(pwd)
CLUSTER_NAME=$(ls $INSTALL_DIR|grep *.log| awk -F. '{print $1}')
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
#
# start removing the NGW since it takes a lot of time
while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways | jq -r '.NatGateways[].NatGatewayId') 2>&1 >> $CLUSTER_LOG
#
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
OIDC_ID=$(rosa list oidc-provider -o json|grep arn| awk -F/ '{print $3}'|cut -c 1-32)
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "# Start deleting ROSA HCP cluster $CLUSTER_NAME, VPC, roles, etc. " 2>&1 |tee -a $CLUSTER_LOG
echo "# Further details can be found in $CLUSTER_LOG LOG file" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#
rosa delete cluster -c $CLUSTER_NAME --yes 2>&1 >> $CLUSTER_LOG
echo "Cluster deletion in progress " 2>&1 |tee -a $CLUSTER_LOG
echo "INFO: To watch your cluster uninstallation logs, run 'rosa logs uninstall -c ${CLUSTER_NAME} --watch'" 2>&1 |tee -a $CLUSTER_LOG
#
rosa logs uninstall -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
rosa delete operator-roles --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
echo "operator-roles deleted !" 2>&1 |tee -a $CLUSTER_LOG
rosa delete oidc-provider --oidc-config-id $OIDC_ID --mode auto --yes 2>&1 >> $CLUSTER_LOG
echo "oidc-provider deleted !" 2>&1 |tee -a $CLUSTER_LOG
#
VPC_ID=$(cat $CLUSTER_LOG |grep VPC_ID_VALUE|awk '{print $2}')
echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a $CLUSTER_LOG
#
#   while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways | jq -r '.NatGateways[].NatGatewayId') 2>&1 >> $CLUSTER_LOG
# NOTE: waiting for the NAT-GW to die - se non crepa non andiamo da nessuna parte
echo "waiting for the NAT-GW to die " 2>&1 |tee -a $CLUSTER_LOG
#sleep 100
#
    while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> $CLUSTER_LOG
    while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> $CLUSTER_LOG
    while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> $CLUSTER_LOG
   while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> $CLUSTER_LOG
   while read -r ig_id ; do aws ec2 detach-internet-gateway --internet-gateway-id $ig_id --vpc-id $VPC_ID; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> $CLUSTER_LOG
   while read -r ig_id ; do aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $ig_id; done < <(aws ec2 describe-internet-gateways | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> $CLUSTER_LOG
   while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> $CLUSTER_LOG
#
aws ec2 delete-vpc --vpc-id=$VPC_ID 2>&1 >> $CLUSTER_LOG
echo "VPC ${VPC_ID} deleted !" 2>&1 |tee -a $CLUSTER_LOG
#
rosa delete account-roles --mode auto --prefix $PREFIX --yes 2>&1 >> $CLUSTER_LOG
echo "account-roles deleted !" 2>&1 |tee -a $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "done! " 2>&1 |tee -a $CLUSTER_LOG
echo "Cluster " $CLUSTER_NAME " was deleted !" 2>&1 |tee -a $CLUSTER_LOG
echo "The old LOG file ${CLUSTER_LOG} in is now moved to /tmp folder" 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
mv $CLUSTER_LOG /tmp
Countdown
Fine
}
#######################################################################################################################################
Fine() {
    echo "Thanks for using this script. Feedback is greatly appreciated, if you want you can leave yours by sending an email to gmollo@redhat.com"
    exit 0
}

Errore() {
    echo "Wrong option."
    clear
}

Countdown() {
 hour=0
 min=0
 sec=10
        while [ $hour -ge 0 ]; do
                 while [ $min -ge 0 ]; do
                         while [ $sec -ge 0 ]; do
                                 echo -ne "$hour:$min:$sec\033[0K\r"
                                 let "sec=sec-1"
                                 sleep 1
                         done
                         sec=59
                         let "min=min-1"
                 done
                 min=59
                 let "hour=hour-1"
         done
}
#
############################################################
# Single AZ VPC                                            #
############################################################
#
SingleAZ-VPC() {
echo "#"
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
#rosa verify permissions 2>&1 >> $CLUSTER_LOG
#rosa verify quota --region=$AWS_REGION
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#
VPC_ID_VALUE=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)

echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a $CLUSTER_LOG
#
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 |tee -a $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PUBLIC_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)
echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
#
PRIV_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)
echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
echo "Creating the IGW: " $IGW 2>&1 |tee -a $CLUSTER_LOG
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW 2>&1 >> $CLUSTER_LOG
#
PUBLIC_RT_ID=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb 2>&1 >> $CLUSTER_LOG
#
EIP_ADDRESS=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text)
echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 |tee -a $CLUSTER_LOG
echo "Waiting for NGW to warm up " 2>&1 |tee -a $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
#
PRIVATE_RT_ID1=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! " 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
}
#
############################################################
# Single AZ (Private)                                      #
############################################################
#
SingleAZ-VPC-Priv() {
echo "#" 
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#
VPC_ID_VALUE=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)

echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a $CLUSTER_LOG
#
# 
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PRIV_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)

echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
PRIVATE_RT_ID1=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)

echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 |tee -a $CLUSTER_LOG
#aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! " 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
}
#
############################################################
# Multi AZ                                                 #
############################################################
#
MultiAZ-VPC() {
echo "#" 
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#
VPC_ID_VALUE=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)

echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a $CLUSTER_LOG
# 
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
# Find out how many az are available based on chosen region
AZ_ARRAY=($(aws ec2 describe-availability-zones --region $AWS_REGION|jq -r '.AvailabilityZones[].ZoneName'|tr '\n' ' '))
#
# Dynamically and randomly choose the destination AZs based on how many of them the user wants to use
AZ_COUNTER={:-${#AZ_ARRAY[@]}}
is_integer () {
        [[ "$1" =~ ^[[:digit:]]+$ ]] && [[ "$1" -ge 2 ]]
}

while ( ! is_integer "$AZ_COUNTER" );do
read -r -p "Maximum number of az is ${#AZ_ARRAY[@]}, on how many availability zones you want to deploy your rosa cluster? (min: 2 max(default): ${#AZ_ARRAY[@]})[${#AZ_ARRAY[@]}]: " AZ_COUNTER
done

[[ -z "$AZ_COUNTER" || "$AZ_COUNTER" -gt ${#AZ_ARRAY[@]} ]] && AZ_COUNTER=${#AZ_ARRAY[@]}
echo "AZ_COUNTER will be $AZ_COUNTER is less or equal than ${#AZ_ARRAY[@]}"

DIFF=$(( ${#AZ_ARRAY[@]} - $AZ_COUNTER ))

LOOPCOUNT=$DIFF
while [ "$LOOPCOUNT" -gt 0 ]
do
        AZ_ARRAY=(${AZ_ARRAY[@]/${AZ_ARRAY[$RANDOM % ${#AZ_ARRAY[@]}]}})
        LOOPCOUNT=$(($LOOPCOUNT-1))
done


#
AZ_PUB_ARRAY=()
AZ_PRIV_ARRAY=()
#declare -A AZ_PAIRED_ARRAY - moved out of the function, otherwise it won't work if called elsewhere in the script
x=0
y=128
echo "Listing all the availability zones inside the $AWS_REGION: ${AZ_ARRAY[@]}" 2>&1 >> $CLUSTER_LOG

echo "Creating the Public and Private Subnets" 2>&1 |tee -a $CLUSTER_LOG
for az in ${AZ_ARRAY[@]}
        do
        export AZP=$(echo $az| sed -e 's/\(.*\)/\U\1/g;s/-/_/g')
        export PUBLIC_SUB_NAME=PUBLIC_SUB_${AZP}
        export PRIV_SUB_NAME=PRIV_SUB_${AZP}
        declare PUBLIC_SUB_${AZP}=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.${x}.0/20 --availability-zone ${az} --query Subnet.SubnetId --output text) 2>&1 >> $CLUSTER_LOG
        echo "Creating the Public Subnet ${!PUBLIC_SUB_NAME} in availability zone $az" 2>&1 |tee -a $CLUSTER_LOG
        aws ec2 create-tags --resources ${!PUBLIC_SUB_NAME} --tags Key=Name,Value=$CLUSTER_NAME-public 2>&1 >> $CLUSTER_LOG
        x=$(($x ++16))
        AZ_PUB_ARRAY+=(${!PUBLIC_SUB_NAME})
        declare PRIV_SUB_${AZP}=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.${y}.0/20 --availability-zone ${az} --query Subnet.SubnetId --output text)
        echo "Creating the Private Subnet ${!PRIV_SUB_NAME} in availability zone $az" 2>&1 |tee -a $CLUSTER_LOG
        aws ec2 create-tags --resources ${!PRIV_SUB_NAME} --tags Key=Name,Value=$CLUSTER_NAME-private 2>&1 >> $CLUSTER_LOG
        y=$(($y ++16))
        AZ_PRIV_ARRAY+=(${!PRIV_SUB_NAME})
        AZ_PAIRED_ARRAY+=([${!PUBLIC_SUB_NAME}]=${!PRIV_SUB_NAME})
done

#
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)

echo "Creating the IGW: " $IGW 2>&1 |tee -a $CLUSTER_LOG
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
#
PUBLIC_RT_ID=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
#
i=1
for pubsnt in ${!AZ_PAIRED_ARRAY[@]}
        do
        aws ec2 associate-route-table --subnet-id $pubsnt --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
        EIP_ADDRESS=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
        NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway --subnet-id $pubsnt --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text)
        echo "EIP_ADDRESS " $EIP_ADDRESS 2>&1 >> $CLUSTER_LOG
        echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 |tee -a $CLUSTER_LOG
        echo "Waiting for 120 sec. NGW to warm up " 2>&1 |tee -a $CLUSTER_LOG
        sleep 120 |pv -t
        aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
        PRIVATE_RT_ID=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
        echo "Creating the Private Route Table: " $PRIVATE_RT_ID 2>&1 |tee -a $CLUSTER_LOG
        aws ec2 create-route --route-table-id $PRIVATE_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
        aws ec2 associate-route-table --subnet-id ${AZ_PAIRED_ARRAY[$pubsnt]} --route-table-id $PRIVATE_RT_ID 2>&1 >> $CLUSTER_LOG
        aws ec2 create-tags --resources $PRIVATE_RT_ID $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb${i} 2>&1 >> $CLUSTER_LOG
        i=$(($i++1))
done
unset i
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! " 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
}

#
############################################################
# AWS CLI                                                  #
############################################################
AWS_CLI() {
#set -x
# Check if AWS CLI is installed
if [ -x "$(command -v /usr/local/bin/aws)" ]
then
    # AWS CLI is installed, check for updates
    echo "AWS CLI is already installed. Checking for updates..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    aws --version
    echo "AWS CLI update completed."
    rm -rf aws awscliv2.zip
else
    echo "AWS CLI is not installed. Going to download and install it ..."
    dirname='/usr/local/aws-cli'
    if [ -d $dirname ]; then sudo rm -rf $dirname; fi
    # Download and install AWS CLI
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -u awscliv2.zip
    sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    #sudo ./aws/install
    # Clean up
    rm -rf aws awscliv2.zip
    # Verify the installation
    echo "Verifying AWS CLI installation..."
    aws --version
    echo "AWS CLI installation completed."
fi
    Countdown
}
#
############################################################
# ROSA CLI                                                 #
############################################################
ROSA_CLI() {
#set -xe
# Check if ROSA CLI is installed
if [ -x "$(command -v /usr/local/bin/rosa)" ]
then
    CHECK_IF_UPDATE_IS_NEEDED=`rosa version|grep "There is a newer release version"| awk -F\' '{print $1 ", going to install version --> " $2}'`
        if [ -z ${CHECK_IF_UPDATE_IS_NEEDED:+word} ]
        then
                ROSA_VERSION=$(/usr/local/bin/rosa version)
                echo " "
                echo " "
                echo "ROSA CLI is already installed. Checking for updates..."
                echo "There is no need to update ROSA CLI, installed version is --> " $ROSA_VERSION
        else
        # ROSA CLI is installed, checking for updates
                echo "ROSA CLI is already installed. Checking for updates..."
                ROSA_ACTUAL_V=$(rosa version|awk -F. 'NR==1{print $1"."$2"."$3 }')
                echo "ROSA actual version is --> " $ROSA_ACTUAL_V
                NEXT_V=$(rosa version|grep "There is a newer release version"| awk -F\' 'NR==1{print $1 ", going to install version --> " $2}')
                echo $NEXT_V
                echo "###############################"
                echo "###############################"
                echo "###############################"
        # Download and install ROSA CLI
                curl https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz --output rosa-linux.tar.gz
                tar xvf rosa-linux.tar.gz
                sudo mv rosa /usr/local/bin/rosa
        # Clean up
                rm -rf rosa-linux.tar.gz
        # Trigger the update
                rosa version
                echo "ROSA CLI update completed."
        fi
else
  # ROSA CLI is not installed, download and install
    echo "ROSA CLI is not installed. Going to download and install the latest version ..."
    # Download and install ROSA CLI
    curl https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz --output rosa-linux.tar.gz
    tar xvf rosa-linux.tar.gz
    sudo mv rosa /usr/local/bin/rosa
    # Clean up
    rm -rf rosa-linux.tar.gz
    # Verify the installation
    echo "Verifying ROSA CLI installation..."
    rosa version
fi
    Countdown
}
############################################################
# HCP Public Cluster                                       #
############################################################
HCP-Public()
{
#set -x 
INSTALL_DIR=$(pwd)
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=$(rosa whoami|grep "AWS Account ID:"|awk '{print $4}')
#
aws configure
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
echo "#"
#
SingleAZ-VPC
#
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
INSTALL_ARN=$(rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}')
WORKER_ARN=$(rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}')
SUPPORT_ARN=$(rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}')
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a $CLUSTER_LOG
echo "OIDC_ID " $OIDC_ID 2>&1 2>&1 >> $CLUSTER_LOG
echo "Creating operator-roles" 2>&1 >> $CLUSTER_LOG
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG
SUBNET_IDS=$PRIV_SUB_2a","$PUBLIC_SUB_2a
#
echo "Creating ROSA HCP cluster " 2>&1 |tee -a $CLUSTER_LOG
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> $CLUSTER_LOG
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 |tee -a $CLUSTER_LOG
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "Creating the cluster-admin user" 2>&1 |tee -a $CLUSTER_LOG
rosa create admin --cluster=$CLUSTER_NAME 2>&1 |tee -a $CLUSTER_LOG
#
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo "Done!!! " 2>&1 |tee -a $CLUSTER_LOG
echo "Cluster " $CLUSTER_NAME " has been installed and is up and running" 2>&1 |tee -a $CLUSTER_LOG
echo "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
Fine
}
#
# 
############################################################
# HCP PrivateLink Cluster                                  #
############################################################
# 
function HCP-Private()
{ 
set -x
INSTALL_DIR=$(pwd)
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=$(rosa whoami|grep "AWS Account ID:"|awk '{print $4}')
#
aws configure
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ (Private) ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
#
SingleAZ-VPC-Priv
#
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
INSTALL_ARN=$(rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}')
WORKER_ARN=$(rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}')
SUPPORT_ARN=$(rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}')
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a $CLUSTER_LOG
echo "OIDC_ID " $OIDC_ID 2>&1 2>&1 >> $CLUSTER_LOG
echo "Creating operator-roles" 2>&1 >> $CLUSTER_LOG
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG
SUBNET_IDS=$PRIV_SUB_2a
#
echo "Creating ROSA HCP cluster " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 >> $CLUSTER_LOG
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --private-link --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> $CLUSTER_LOG
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 |tee -a $CLUSTER_LOG
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "Creating the cluster-admin user" 2>&1 |tee -a $CLUSTER_LOG
rosa create admin --cluster=$CLUSTER_NAME 2>&1 |tee -a $CLUSTER_LOG
#   
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Done!!! " 2>&1 |tee -a $CLUSTER_LOG
echo "Cluster " $CLUSTER_NAME " has been installed and is up and running" 2>&1 |tee -a $CLUSTER_LOG
echo "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
Fine
}
#
############################################################
# HCP Public Cluster (Multi AZ)                            #
############################################################
HCP-Public-MultiAZ()
{
#set -x
INSTALL_DIR=$(pwd)
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=$(rosa whoami|grep "AWS Account ID:"|awk '{print $4}')
#
#
aws configure
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Multi-AZ ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
echo "#"
#
MultiAZ-VPC
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
INSTALL_ARN=$(rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}')
WORKER_ARN=$(rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}')
SUPPORT_ARN=$(rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}')
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a $CLUSTER_LOG
echo "OIDC_ID " $OIDC_ID 2>&1 2>&1 >> $CLUSTER_LOG
echo "Creating operator-roles" 2>&1 >> $CLUSTER_LOG
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG
SUBNET_IDS=$PRIV_SUB_2a","$PRIV_SUB_2b","$PRIV_SUB_2c","$PUBLIC_SUB_2a","$PUBLIC_SUB_2b","$PUBLIC_SUB_2c
#
echo "Creating ROSA HCP cluster " 2>&1 |tee -a $CLUSTER_LOG
echo "" 2>&1 >> $CLUSTER_LOG
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --multi-az --region ${AWS_REGION} --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> $CLUSTER_LOG
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 |tee -a $CLUSTER_LOG
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "Creating the cluster-admin user" 2>&1 |tee -a $CLUSTER_LOG
rosa create admin --cluster=$CLUSTER_NAME 2>&1 |tee -a $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Done!!! " 2>&1 |tee -a $CLUSTER_LOG
echo "Cluster " $CLUSTER_NAME " has been installed and is up and running" 2>&1 |tee -a $CLUSTER_LOG
echo "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
Fine
}
########################################################################################################################
# Checks
########################################################################################################################
various_checks(){
#set -x
# Check if ROSA CLI is installed
if [ -x "$(command -v /usr/local/bin/rosa)" ]
 then
        if [[ "$(rosa whoami 2>&1)" =~ "User is not logged in to OCM" ]];
                then 
		echo " "
		echo " "
		echo " "
		echo " "
		echo " "
		option_picked "Warning: Before to proceed you must login to OCM/ROSA !"
		echo " "
		echo "Please follow this link to download your token from the Red Hat OCM Portal"; echo -e '\e]8;;https://console.redhat.com/openshift/token/rosa/show\e\\https://console.redhat.com/openshift/token/rosa/show\e]8;;\e\\'
		echo " "
		echo "Example:  "
		echo "rosa login --token=\"RtidhhrkjLjhgLjkhUUvuhJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJhZDUyMjdhMy1iY2ZkLTRjZjAtYTdiNi0zOTk4MzVhMDg1NjYifQ.eyJpYXQiOjE3MDQzOTE4NzAsImp0aSI6ImJjZTY1ZjQxLThiZDctNGQ2Ni04MjBkLWFlMTdkZWYxMzJhNiIsImlzcyI6Imh0dHBzOi8vc3NvLnJlZGhhdC5jb20vYXV0aC9yZWFsbXMvcmVkaGF0LWV4dGVybmFsIiwiYXVkIjoiaHR0cHM6Ly9zc28ucmVkaGF0LmNvbS9hdXRoL3JlYWxtcy9yZWRoYXQtZXh0ZXJuYWwiLCJzdWIiOiJmOjUyOGQ3NmZmLWY3MDgtNDNlZC04Y2Q1LWZlMTZmNGZlMGNlNjpyaC1lZS1nbW9sbG8iLCJ0eXAiOiJPZmZsaW5lIiwiYXpwIjoiY2xvdWQtc2VydmljZXMiLCJub25jZSI6IjY1MGYzOGUzLTBhYjgtNGY3NC1hNTQ0LTFkMzZiMjJlYzNmNyIsInNlc3Npb25fc3RhdGUiOiI5MDM3MTAzMS1jOWJlLTRkYjEtYTZhZC1hZTRjNWNmYjZiNDUiLCJzY29wZSI6Im9wZW5pZCBhcGkuaWFtLnNlcnZpY2VfYWNjb3VudHMgb2ZmbGluZV9hY2Nlc3MiLCJzaWQiOiI5MDM3MTAzMS1jOWJlLTRkYjEtYTZhZC1hZTRjNWNmYjZiNDUifQ.Ne600xRwKwkQmjkSt_V6HnhnKTZCGwrubrWj4XkkK5I\"" 
		echo " "
		echo " "
                Fine
        else
                echo "You are logged to OCM/ROSA "
        fi
 else
   ROSA_CLI
   echo " "
   option_picked "Warning: Before to proceed you must login to OCM/ROSA !"
   echo " "
   echo "Please follow this link to download your token from the Red Hat OCM Portal"; echo -e '\e]8;;https://console.redhat.com/openshift/token/rosa/show\e\\https://console.redhat.com/openshift/token/rosa/show\e]8;;\e\\'	
   echo " "
   echo " "
   Fine
fi
}
########################################################################################################################
# Menu
########################################################################################################################
show_menu(){
various_checks
clear
    normal=`echo "\033[m"`
    menu=`echo "\033[36m"` #Blue
    number=`echo "\033[33m"` #yellow
    bgred=`echo "\033[41m"`
    fgred=`echo "\033[31m"`
    printf "\n${menu}*********************************************${normal}\n"
    printf "\n${menu}*         ROSA HCP Installation Menu        *${normal}\n"
    printf "\n${menu}*********************************************${normal}\n"
    printf "${menu}**${number} 1)${menu} HCP Public (Single-AZ) ${normal}\n"
    printf "${menu}**${number} 2)${menu} HCP Public (Multi-AZ) ${normal}\n"
    printf "${menu}**${number} 3)${menu} HCP PrivateLink (Single-AZ) ${normal}\n"
    printf "${menu}**${number} 4)${menu} Delete HCP ${normal}\n"
    printf "${menu}**${number} 5)${menu} AWS_CLI ${normal}\n"
    printf "${menu}**${number} 6)${menu} ROSA_CLI ${normal}\n"
    printf "${menu}*********************************************${normal}\n"
    printf "Please enter a menu option and enter or ${fgred}x to exit. ${normal}"
    read opt
}

option_picked(){
    msgcolor=`echo "\033[01;31m"` # bold red
    normal=`echo "\033[00;00m"` # normal white
    message=${@:-"${normal}Error: No message passed"}
    printf "${msgcolor}${message}${normal}\n"
}

clear
show_menu
while [ $opt != '' ]
    do
    if [ $opt = '' ]; then
      exit;
    else
      case $opt in
        1) clear;
            option_picked "Option 1 Picked - Installing ROSA with HCP Public (Single-AZ)";
            HCP-Public;
            show_menu;
        ;;
        2) clear;
            option_picked "Option 3 Picked - Installing ROSA with HCP Public (Multi-AZ)";
            HCP-Public-MultiAZ;
            show_menu;
        ;;
        3) clear;
            option_picked "Option 2 Picked - Installing ROSA with HCP PrivateLink (Single-AZ)";
            HCP-Private;
            show_menu;
        ;;
        4) clear;
            option_picked "Option 4 Picked - Removing ROSA with HCP";
            Delete_HCP;
            show_menu;
        ;;
        5) clear;
            option_picked "Option 5 Picked - Installing/Updating AWS CLI ";
            AWS_CLI;
            show_menu;
        ;;
        6) clear;
            option_picked "Option 6 Picked - Installing/Updating ROSA CLI";
            ROSA_CLI
            show_menu;
        ;;
        x)Fine;
        ;;
        \n)exit;
        ;;
        *)clear;
            option_picked "Pick an option from the menu";
            show_menu;
        ;;
      esac
    fi
done
