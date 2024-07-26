#!/bin/bash
#set -x
################################################################################################################
##  +-----------------------------------+-----------------------------------+
##  |                                                                       |
##  | Copyright (c) 2023-2024, Gianfranco Mollo <gmollo@redhat.com>.        |
##  |                                                                       |
##  | This program is free software: you can redistribute it and/or modify  |
##  | it under the terms of the GNU General Public License as published by  |
##  | the Free Software Foundation, either version 3 of the License, or     |
##  | (at your option) any later version.                                   |
##  |                                                                       |
##  | This program is distributed in the hope that it will be useful,       |
##  | but WITHOUT ANY WARRANTY; without even the implied warranty of        |
##  | MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         |
##  | GNU General Public License for more details.                          |
##  |                                                                       |
##  | You should have received a copy of the GNU General Public License     |
##  | along with this program. If not, see <http://www.gnu.org/licenses/>.  |
##  |                                                                       |
#   |  About the author:                                                    |
#   |                                                                       |
#   |  Owner: 	Gianfranco Mollo                                            |
#   |  GitHub: 	https://github.com/gmolloATredhat                           |
#   |		https://github.com/joemolls                                 |
##  |                                                                       |
##  +-----------------------------------------------------------------------+
##
##  DESCRIPTION
#
#
#
#   This is a single shell script that will create all the resources needed to deploy a ROSA HCP cluster via the CLI. The script will take care of:
#
#   - Set up your AWS account and roles (eg. the account-wide IAM roles and policies, cluster-specific Operator roles and policies, and OpenID Connect (OIDC) identity provider).
#   - Create the VPC;
#   - Create your ROSA HCP Cluster with a minimal configuration (eg. 2 workers/Single-AZ; 3 workers/Multi-Zone).
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
#
SCRIPT_VERSION=v1.13.0
#
#
########################################################################################################################
# Optional statistics (eg. os type, version, platform)
# LAPTOP=$(uname -srvm)
#
#
#
#
########################################################################################################################
# MANDATORY Variables - Warning do not delete or comment the following variables
########################################################################################################################
INSTALL_DIR=$(pwd)
NOW=$(date +"%y%m%d%H%M")
CLUSTER_NAME=${1:-gm-$NOW}
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
PREFIX=${2:-$CLUSTER_NAME}
# Warning do not delete or comment the following variables
OS=$(uname -s)
ARC=$(uname -m)
AWS_REGION=$(aws configure get region)
#CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
#CURRENT_HCP=$(rosa list clusters|grep -v "No clusters"|grep -v ID|wc -l)
#
# Here you can change the default instance type for the compute nodes(--compute-machine-type). 
# Determines the amount of memory and vCPU allocated to each compute node.
#
DEF_MACHINE_TYPE="m5.xlarge"
DEF_GRAVITON_MACHINE_TYPE="m6g.xlarge"
#
#############################################################################################
# Select and delete an HCP along with the VPC it belongs to
#############################################################################################
Delete_One_HCP() {
#set -x
CHECK_GM="Delete_One_HCP"
CLUSTER_LIST=$(rosa list clusters|grep -i "hosted cp"|grep -v uninstalling|awk '{print $2}')
echo ""
echo ""
# if1 #########################################################################################################
if [ -n "$CLUSTER_LIST" ]; then
   COUNTER=""
   echo "Current HCP cluster list:"
   echo "$CLUSTER_LIST"
   echo ""
   echo ""
   echo -n  "Please pick one or hit ENTER to quit: "
   read -r CLUSTER_NAME
	for a in $CLUSTER_LIST
    	do
		COUNTER=$((COUNTER=+1))
# if2 #########################################################################################################
		if [ "$CLUSTER_NAME" == $a ]; then
		option_picked_green "Let's get started with " "$CLUSTER_NAME" " cluster"
                rosa describe cluster -c $CLUSTER_NAME > $CLUSTER_NAME.txt
		echo ""
		echo ""
		CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
    #############################################################################################################################################################
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "# Start deleting ROSA HCP cluster $CLUSTER_NAME, VPC, roles, etc. " 2>&1 |tee -a "$CLUSTER_LOG"
echo "# Further details can be found in $CLUSTER_LOG LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
		#
		# Collecting a few details
		#
		OIDC_ID=$(cat $CLUSTER_NAME.txt |grep OIDC| awk -F/ '{print $4}'|cut -c 1-32)
		DEPLOYMENT=$(cat $CLUSTER_NAME.txt |grep "Data Plane"|awk -F: '{print $2}'| xargs)
		DESIRED_NODES=$(cat $CLUSTER_NAME.txt |grep -i "Compute (desired)"|awk -F: '{print $2}'| xargs)
		CURRENT_NODES=$(cat $CLUSTER_NAME.txt |grep -i "Compute (current)"|awk -F: '{print $2}'| xargs)
#
		SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk -F: '{print $2}'|awk -F, '{print $1}'| xargs)
	        PRIVATE=$(cat $CLUSTER_NAME.txt|grep Private|awk -F: '{print $2}'|xargs)
    #############################################################################################################################################################
    #
		if  [ "$PRIVATE" == "Yes" ]; then
    JUMP_HOST="$CLUSTER_NAME"-jump-host
		JUMP_HOST_ID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=$JUMP_HOST Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text)
        		if [[ $JUMP_HOST_ID ]]
        		then
        		 aws ec2 terminate-instances --instance-ids "$JUMP_HOST_ID" 2>&1 |tee -a "$CLUSTER_LOG"
        		 JUMP_HOST_KEY=$(aws ec2 describe-instances --filters Name=tag:Name,Values=$JUMP_HOST --query "Reservations[*].Instances[*].KeyName" --output text)
        		 echo "Deleting the key-pair named " "$JUMP_HOST_KEY" 2>&1 |tee -a "$CLUSTER_LOG"
        		 aws ec2 delete-key-pair --key-name "$JUMP_HOST_KEY" 2>&1 |tee -a "$CLUSTER_LOG"
        		 mv "$JUMP_HOST_KEY" /tmp
        		else
        		 echo ""
        		fi
      else
       echo ""
      fi
    #############################################################################################################################################################
#
		# Find $VPC_ID and start deleting NGW
		#
		VPC_ID=$(aws ec2 describe-subnets --subnet-ids $SUBN|grep -i vpc|awk -F\" '{print $4}')
# # # # # # # # echo "VPC_ID_VALUE " $VPC_ID 2>&1 >> "$CLUSTER_LOG"
		echo "Cluster " $CLUSTER_NAME "is a" $DEPLOYMENT "deployment with"$CURRENT_NODES"of "$DESIRED_NODES "nodes within the AWS VPC" $VPC_ID 2>&1 |tee -a "$CLUSTER_LOG"
		# start removing the NGW since it takes a lot of time
		echo "Removing the NGW since it takes a lot of time to get deleted"
        	while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID| jq -r '.NatGateways[].NatGatewayId') 2>&1 >> "$CLUSTER_LOG"
		#
		# Find $PREFIX
		#
		PREFIX=$CLUSTER_NAME
		echo "Operator roles prefix: " $PREFIX
		#
		#Get started
		#
		echo "Running \"rosa delete cluster\"" 2>&1 |tee -a "$CLUSTER_LOG"
		rosa delete cluster -c $CLUSTER_NAME --yes 2>&1 >> "$CLUSTER_LOG"
		echo "Running \"rosa logs unistall\"" 2>&1 |tee -a "$CLUSTER_LOG"
		rosa logs uninstall -c $CLUSTER_NAME --watch 2>&1 >> "$CLUSTER_LOG"
#
		echo "Deleting operator-roles" 2>&1 |tee -a "$CLUSTER_LOG"
		rosa delete operator-roles --prefix $PREFIX -m auto -y 2>&1 >> "$CLUSTER_LOG"
		echo "Deleting OIDC " $OIDC_ID 2>&1 |tee -a "$CLUSTER_LOG"
		rosa delete oidc-provider --oidc-config-id "$OIDC_ID" -m auto -y 2>&1 >> "$CLUSTER_LOG"
		#
		echo "Deleting account-roles " 2>&1 |tee -a "$CLUSTER_LOG"
		rosa delete account-roles --prefix $PREFIX -m auto -y  2>&1 >> "$CLUSTER_LOG"
		#
		#################################################################################################################################
		# Delete the VPC it belongs to
		#
		#SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk -F: '{print $2}')
  		SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk '{print $3}'|xargs|tr ',' '\n')
  		VPC_ID=$(aws ec2 describe-subnets --subnet-ids $SUBN|grep -i vpc|awk -F\" '{print $4}'|xargs)
#
    		echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a "$CLUSTER_LOG"
		#
		#
   		while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> "$CLUSTER_LOG"
   		while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> "$CLUSTER_LOG"
   		while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> "$CLUSTER_LOG"
   		while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> "$CLUSTER_LOG"
#
# Detach and delete IGW
#
IG_2B_DELETED=$(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId")
aws ec2 detach-internet-gateway --internet-gateway-id $IG_2B_DELETED --vpc-id $VPC_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $IG_2B_DELETED 2>&1 >> "$CLUSTER_LOG"
#
   		while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> "$CLUSTER_LOG"
		#
		aws ec2 delete-vpc --vpc-id=$VPC_ID 2>&1 >> $CLUSTER_LOG
		option_picked_green "VPC ${VPC_ID} deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
		echo " "
		option_picked_green "HCP Cluster $CLUSTER_NAME deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
		mv "$CLUSTER_LOG" /tmp
		mv "$CLUSTER_NAME".txt /tmp
		CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
		CURRENT_HCP=$(rosa list clusters|grep -v "No clusters"|grep -v ID|wc -l)
	else
		if [ $COUNTER = $CURRENT_VPC ]; then option_picked "This option doesn't match with $a or simply no HCP Cluster was chosen from the above list, returning to the Tools menu !"
                else
                	echo ""
                fi
        fi
	done
else
option_picked "Unfortunately there are NO HCP clusters in this accout"
fi
#################################################################################################################################
#
#
echo "" 
echo ""
ppp=x
echo "Press ENTER to go back to the Menu"
read -r ppp
}
#######################################################################################################################################
#######################################################################################################################################
#
#
#
################################################
# Delete almost everything
################################################
Delete_ALL() {
# set -x
CHECK_GM="Delete_ALL"
#
#
# how many clusters do we have ?
#
CLUSTER_LIST=$(rosa list clusters|grep -i "hosted cp"|grep -v uninstalling|awk '{print $2}')
#CLUSTER_LIST=$(rosa list clusters|grep -i "hosted cp"|awk '{print $2}')
# if1 ##################################################################################################################################
if [ -n "$CLUSTER_LIST" ]; then
   echo "Current HCP cluster list:"
   echo "$CLUSTER_LIST"
   echo ""
   echo ""
	for a in $CLUSTER_LIST
	do
  VPC_ID=""
  CLUSTER_NAME=$a
  CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
#
	JUMP_HOST="$CLUSTER_NAME"-jump-host
	JUMP_HOST_ID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=$JUMP_HOST Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text)
	if [[ $JUMP_HOST_ID ]]
	then
        aws ec2 terminate-instances --instance-ids "$JUMP_HOST_ID" 2>&1 |tee -a "$CLUSTER_LOG"
        JUMP_HOST_KEY=$(aws ec2 describe-instances --filters Name=tag:Name,Values=$JUMP_HOST --query "Reservations[*].Instances[*].KeyName" --output text)
        echo "Deleting the key-pair named " "$JUMP_HOST_KEY" 2>&1 |tee -a "$CLUSTER_LOG"
        aws ec2 delete-key-pair --key-name "$JUMP_HOST_KEY" 2>&1 |tee -a "$CLUSTER_LOG"
	mv "$JUMP_HOST_KEY" /tmp
	else
      	echo ""
	fi
#
# Collecting a few details
#
  rosa describe cluster -c "$CLUSTER_NAME" > $CLUSTER_NAME.txt
  OIDC_ID=$(cat $CLUSTER_NAME.txt |grep OIDC| awk -F/ '{print $4}'|cut -c 1-32 )
  DEPLOYMENT=$(cat $CLUSTER_NAME.txt |grep "Data Plane"|awk -F: '{print $2}')
  DESIRED_NODES=$(cat $CLUSTER_NAME.txt |grep -i "Compute (desired)"|awk -F: '{print $2}')
  CURRENT_NODES=$(cat $CLUSTER_NAME.txt |grep -i "Compute (current)"|awk -F: '{print $2}')
# Find VPC_ID
  SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk '{print $3}'|xargs|tr ',' '\n')
  VPC_ID=$(aws ec2 describe-subnets --subnet-ids $SUBN|grep -i vpc|awk -F\" '{print $4}'|xargs)
#
#
  echo "#" 2>&1 >> "$CLUSTER_LOG"
  echo "# Start deleting ROSA HCP cluster $CLUSTER_NAME, VPC, roles, etc. "  2>&1 >> "$CLUSTER_LOG"
  echo "# Further details can be found in $CLUSTER_LOG LOG file" 2>&1 >> "$CLUSTER_LOG"
  echo "#" 2>&1 >> "$CLUSTER_LOG"
#
#
  echo "############################################################################################################# "
  echo "# "
  echo "#  Picked ==> " "$CLUSTER_NAME"
  echo "#  Cluster " $a "is a " $DEPLOYMENT "deployment with "$CURRENT_NODES" of"$DESIRED_NODES "nodes in VPC "$VPC_ID
# start removing the NGW since it takes a lot of time
  while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways --filter 'Name=vpc-id,Values='$VPC_ID| jq -r '.NatGateways[].NatGatewayId') 2>&1 >> "$CLUSTER_LOG"
#
# Find $PREFIX
#
### PREFIX=$(rosa list account-roles| grep $a|grep Install|awk '{print $1}'| sed 's/.\{24\}$//')
  #PREFIX=$(cat $CLUSTER_NAME.txt |grep openshift-cluster-csi|awk -F- '{print $2}'|awk -F/ '{print $2}')
  PREFIX="$CLUSTER_NAME"
# echo "#  Operator roles prefix ==> " "$PREFIX"
#
#Get started 
   option_picked "#  Going to delete the HCP cluster named " "$CLUSTER_NAME" " and the VPC " "$VPC_ID" 2>&1 |tee -a "$CLUSTER_LOG"
#
rosa delete cluster -c $CLUSTER_NAME --yes 2>&1 >> "$CLUSTER_LOG"
  echo "#  You can watch logs with \"$ tail -f $CLUSTER_LOG\"" 2>&1 |tee -a "$CLUSTER_LOG"
rosa logs uninstall -c $CLUSTER_NAME --watch 2>&1 >> "$CLUSTER_LOG"
  echo "#  Deleting operator-roles with PREFIX= " "$PREFIX" 2>&1 |tee -a "$CLUSTER_LOG"
rosa delete operator-roles --prefix $PREFIX -m auto -y 2>&1 >> "$CLUSTER_LOG"
  echo "#  Deleting OIDC " $OIDC_ID 2>&1 |tee -a "$CLUSTER_LOG"
rosa delete oidc-provider --oidc-config-id "$OIDC_ID" -m auto -y 2>&1 >> "$CLUSTER_LOG"
#
  echo "#  Deleting account-roles with PREFIX= " "$PREFIX" 2>&1 |tee -a "$CLUSTER_LOG"
rosa delete account-roles --mode auto --prefix $PREFIX --yes 2>&1 >> "$CLUSTER_LOG"
#

#########################
# Find VPC_ID
  SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk '{print $3}'|xargs|tr ',' '\n')
  VPC_ID=$(aws ec2 describe-subnets --subnet-ids $SUBN|grep -i vpc|awk -F\" '{print $4}'|xargs)
#
    echo "########### " 2>&1 |tee -a "$CLUSTER_LOG"
    echo "#  Start deleting VPC ${VPC_ID} " 2>&1 |tee -a "$CLUSTER_LOG"
#
#
   while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> "$CLUSTER_LOG"
   while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> "$CLUSTER_LOG"
   while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> "$CLUSTER_LOG"
   while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> "$CLUSTER_LOG"
#
#
# Detach and delete IGW
#
IG_2B_DELETED=$(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId")
aws ec2 detach-internet-gateway --internet-gateway-id $IG_2B_DELETED --vpc-id $VPC_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $IG_2B_DELETED 2>&1 >> "$CLUSTER_LOG"
#
   while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> "$CLUSTER_LOG"
#
aws ec2 delete-vpc --vpc-id=$VPC_ID 2>&1 >> $CLUSTER_LOG
option_picked_green "#  VPC ${VPC_ID} deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
  echo "############################################################################################################# "
mv "$CLUSTER_LOG" /tmp
mv "$CLUSTER_NAME".txt /tmp
CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
CURRENT_HCP=$(rosa list clusters|grep -v "No clusters"|grep -v ID|wc -l)
#########################
#
done
else
	echo "" 
	echo "" 
	option_picked "Unfortunately there are NO HCP clusters at the moment in this accout"
	echo "" 
	echo "" 
	ppp=x
	echo "Press ENTER to go back to the Menu"
	read -r ppp
fi
# fi1 ##################################################################################################################################
}
#######################################################################################################################################
#
#############################################################################################
# Delete VPC                                                                                #
#############################################################################################
#######################################################################################################################################
Delete_VPC()
{
CHECK_GM="Delete_VPC"

    echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a "$CLUSTER_LOG"
#
#
   while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> "$CLUSTER_LOG"
#
   while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> "$CLUSTER_LOG"
#
   while read -r vpcendpoint_id ; do aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $vpcendpoint_id; done < <(aws ec2 describe-vpc-endpoints | jq -r '.VpcEndpoints[].VpcEndpointId') 2>&1 >> "$CLUSTER_LOG"
#
   while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> "$CLUSTER_LOG"
#
   while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> "$CLUSTER_LOG"
#
# Detach and delete IGW
#
IG_2B_DELETED=$(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId")
aws ec2 detach-internet-gateway --internet-gateway-id $IG_2B_DELETED --vpc-id $VPC_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $IG_2B_DELETED 2>&1 >> "$CLUSTER_LOG"
#
   while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> "$CLUSTER_LOG"
#
aws ec2 delete-vpc --vpc-id=$VPC_ID 2>&1 >> $CLUSTER_LOG
CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
echo "VPC ${VPC_ID} deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
}
#######################################################################################################################################
#######################################################################################################################################
#######################################################################################################################################
#######################################################################################################################################
#
#############################################################################################
# Delete 1 VPC                                                                              #
#############################################################################################
#######################################################################################################################################
Delete_1_VPC() {
#
#set -x
CHECK_GM="Delete_1_VPC"
CLUSTER_NAME=delete-vpc
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
#
VPC_LIST=$(aws ec2 describe-vpcs |grep -i vpcid|awk  '{print $2}'|awk -F\"  '{print $2}')
#VPC_COUNT=$(aws ec2 describe-vpcs |grep -i vpcid|wc -l)

if [ -n "$VPC_LIST" ]; then
   echo "Current VPCs:"
   echo $VPC_LIST
   echo ""
   echo ""
   echo -n  "Please pick one or hit ENTER to quit: "
   read -r VPC_ID
   for a in $VPC_LIST
    do
	COUNTER=$((COUNTER=+1))
	if [ "$VPC_ID" == $a ]; then
		echo  "Going to delete --> " "$VPC_ID"
		#############################################################################################################################################################
                #############################################################################################################################################################
                #############################################################################################################################################################
        	echo ""
        	echo "#############################################################################"
        	echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a $CLUSTER_LOG
# NOTE: waiting for the NAT-GW to die - se non crepa non andiamo da nessuna parte
		echo "Waiting for NGW to die (~2 min) "
        	while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-nat-gateways --filter 'Name=vpc-id,Values='$VPC_ID| jq -r '.NatGateways[].NatGatewayId') 2>&1 >> $CLUSTER_LOG
		sleep_120
#
        	while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> $CLUSTER_LOG
        	while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> $CLUSTER_LOG
# 
   while read -r vpcendpoint_id ; do aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $vpcendpoint_id; done < <(aws ec2 describe-vpc-endpoints | jq -r '.VpcEndpoints[].VpcEndpointId') 2>&1 >> "$CLUSTER_LOG"
#
        	while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id" 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> $CLUSTER_LOG
        	while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> $CLUSTER_LOG
#
# Detach and delete IGW
#
IG_2B_DELETED=$(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId")
aws ec2 detach-internet-gateway --internet-gateway-id $IG_2B_DELETED --vpc-id $VPC_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $IG_2B_DELETED 2>&1 >> "$CLUSTER_LOG"
#
        	while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> $CLUSTER_LOG
        	aws ec2 delete-vpc --no-cli-pager --vpc-id=$VPC_ID 2>&1 >> $CLUSTER_LOG
          	echo ""
        	echo ""
        	echo "#############################################################################"
        	echo ""
        	echo ""
        	CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
        	option_picked_green "VPC ${VPC_ID} deleted !" 2>&1 |tee -a $CLUSTER_LOG
		#mv *.log /tmp
		mv "$CLUSTER_LOG" /tmp
		            #############################################################################################################################################################
                #############################################################################################################################################################
                #############################################################################################################################################################
	else
		if [ $COUNTER = $CURRENT_VPC ]; then option_picked "That doesn't match or no VPC was chosen, returning to the Tools Menu !"
		else
		echo ""
		fi
        fi
	done
else
echo " "
echo " "
option_picked "Unfortunately there are NO VPCs in this AWS accout"
fi
#
#
#
echo ""
echo ""
ppp=x
echo "Press ENTER to go back to the Menu"
read -r ppp

}
#
Fine() {
    echo "Thanks for using this script. Feedback is greatly appreciated, if you want you can leave yours by sending an email to gmollo@redhat.com"
    exit 0
}
#
Errore() {
    option_picked "Wrong option: pick an option from the menu";
    clear
}

sleep_120() {
 hour=0
 min=2
 sec=0
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
#######################################################################################################################################
#######################################################################################################################################
#######################################################################################################################################
Countdown() {
 hour=0
 min=0
 sec=5
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
#######################################################################################################################################
Countdown_20() {
 hour=0
 min=0
 sec=20
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
SingleAZ_VPC() {
echo "#"
touch $CLUSTER_LOG
aws sts get-caller-identity 2>&1 >> "$CLUSTER_LOG"
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
#
VPC_ID_VALUE=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)

echo "Creating the VPC: " $VPC_ID_VALUE 2>&1 |tee -a "$CLUSTER_LOG"
#
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PUBLIC_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)
echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 |tee -a "$CLUSTER_LOG"
#
# Automated service preflight checks verify that these resources are tagged correctly before you can use them
#
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=kubernetes.io/role/elb,Value=1 2>&1 |tee -a "$CLUSTER_LOG"
#
PRIV_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)
echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 |tee -a "$CLUSTER_LOG"
#
# Automated service preflight checks verify that these resources are tagged correctly before you can use them
#
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=kubernetes.io/role/internal-elb,Value=1 2>&1 |tee -a "$CLUSTER_LOG"
#
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
echo "Creating the IGW: " $IGW 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW 2>&1 >> "$CLUSTER_LOG"
#
PUBLIC_RT_ID=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> "$CLUSTER_LOG"
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb 2>&1 >> "$CLUSTER_LOG"
#
EIP_ADDRESS=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text)
echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 |tee -a "$CLUSTER_LOG"
echo "Waiting for NGW to warm up " 2>&1 |tee -a "$CLUSTER_LOG"
sleep_120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
#
PRIVATE_RT_ID1=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
#
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID_VALUE --service-name com.amazonaws.${AWS_REGION}.s3 --route-table-ids $PRIVATE_RT_ID1
echo "Creating the VPC Endpoint: " $VPC_ID_VALUE  2>&1 |tee -a "$CLUSTER_LOG"
#
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "VPC creation ... done! " 2>&1 |tee -a "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
}
#
#
############################################################
# Create only a Single AZ VPC                              #
############################################################
#
SingleAZ_VPC_22() {
echo "#"
CLUSTER_NAME=${1:-vpc-$NOW}
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
aws sts get-caller-identity 2>&1 >> "$CLUSTER_LOG"
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
#
VPC_ID_VALUE=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)

echo "Creating the VPC: " $VPC_ID_VALUE 2>&1 |tee -a "$CLUSTER_LOG"
#
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PUBLIC_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)
echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 |tee -a "$CLUSTER_LOG"
#
# Automated service preflight checks verify that these resources are tagged correctly before you can use them
#
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=kubernetes.io/role/elb,Value=1 2>&1 |tee -a "$CLUSTER_LOG"
#
PRIV_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)
echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 |tee -a "$CLUSTER_LOG"
#
# Automated service preflight checks verify that these resources are tagged correctly before you can use them
#
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=kubernetes.io/role/internal-elb,Value=1 2>&1 |tee -a "$CLUSTER_LOG"
#
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
echo "Creating the IGW: " $IGW 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW 2>&1 >> "$CLUSTER_LOG"
#
PUBLIC_RT_ID=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> "$CLUSTER_LOG"
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb 2>&1 >> "$CLUSTER_LOG"
#
EIP_ADDRESS=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text)
echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 |tee -a "$CLUSTER_LOG"
echo "Waiting for NGW to warm up " 2>&1 |tee -a "$CLUSTER_LOG"
sleep_120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
#
PRIVATE_RT_ID1=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
#
aws ec2 create-vpc-endpoint --vpc-id $VPC_ID_VALUE --service-name com.amazonaws.${AWS_REGION}.s3 --route-table-ids $PRIVATE_RT_ID1
#
#
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "VPC creation ... done! " 2>&1 |tee -a "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
mv "$CLUSTER_LOG" /tmp
}
#
#
############################################################
# Multi AZ                                                 #
############################################################
#
MultiAZ_VPC() {
echo "#" 
aws sts get-caller-identity 2>&1 >> "$CLUSTER_LOG"
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
#
VPC_ID_VALUE=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)

echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a "$CLUSTER_LOG"
# 
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> "$CLUSTER_LOG"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
# Find out how many az are available based on chosen region
AZ_ARRAY=($(aws ec2 describe-availability-zones --region $AWS_REGION|jq -r '.AvailabilityZones[].ZoneName'|tr '\n' ' '))
#
#set -x
# Asking user prompt to find how many az should be used for deployment, based on the maximum available within the region
# Dynamically and randomly choose the destination AZs based on how many of them the user wants to use
#AZ_COUNTER=${AZ_COUNTER:-${#AZ_ARRAY[@]}} Old option that gives the default
AZ_COUNTER=""
is_integer () {
        [[ "$1" =~ ^[[:digit:]]+$ ]] && [[ "$1" -ge 2 ]]
}

while ( ! is_integer "$AZ_COUNTER" );do
	read -r -p "The maximum number of AZ(s) in AWS Region $AWS_REGION is ${#AZ_ARRAY[@]}, on how many availability zones you want to deploy your ROSA cluster? (min: 2 max: ${#AZ_ARRAY[@]}) [default: ${#AZ_ARRAY[@]}]: " AZ_COUNTER
done

# control variable, if user inputs a number greater than the maximum number of az available, it will be reduced to this one.
[[ "$AZ_COUNTER" -gt ${#AZ_ARRAY[@]} ]] && AZ_COUNTER=${#AZ_ARRAY[@]}

option_picked "The number of availability zones used will be $AZ_COUNTER which is less or equal than the maximum available of ${#AZ_ARRAY[@]}"

DIFF=$(( ${#AZ_ARRAY[@]} - $AZ_COUNTER ))

LOOPCOUNT=$DIFF
while [ "$LOOPCOUNT" -gt 0 ]
do
        AZ_ARRAY=(${AZ_ARRAY[@]/${AZ_ARRAY[$RANDOM % ${#AZ_ARRAY[@]}]}})
        LOOPCOUNT=$(($LOOPCOUNT-1))
done

echo ${AZ_ARRAY[@]}

#
AZ_PUB_ARRAY=()
AZ_PRIV_ARRAY=()
x=0
y=128
#echo "Listing all the availability zones inside the $AWS_REGION: ${AZ_ARRAY[*]}" 2>&1 >> "$CLUSTER_LOG"
echo "Listing the availability zones that will be used from AWS region $AWS_REGION: ${AZ_ARRAY[*]}" 2>&1 |tee -a "$CLUSTER_LOG"

echo "Creating the Public and Private Subnets" 2>&1 |tee -a "$CLUSTER_LOG"
for az in "${AZ_ARRAY[@]}"
        do
        export AZP=$(echo $az| sed -e 's/\(.*\)/\U\1/g;s/-/_/g')
        export PUBLIC_SUB_NAME=PUBLIC_SUB_${AZP}
        export PRIV_SUB_NAME=PRIV_SUB_${AZP}
        declare PUBLIC_SUB_${AZP}=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.${x}.0/20 --availability-zone ${az} --query Subnet.SubnetId --output text) 2>&1 >> "$CLUSTER_LOG"
        echo "Creating the Public Subnet ${!PUBLIC_SUB_NAME} in availability zone $az" 2>&1 |tee -a "$CLUSTER_LOG"
        aws ec2 create-tags --resources ${!PUBLIC_SUB_NAME} --tags Key=Name,Value=$CLUSTER_NAME-public 2>&1 >> "$CLUSTER_LOG"
        x=$(($x+16))
        AZ_PUB_ARRAY+=(${!PUBLIC_SUB_NAME})
        declare PRIV_SUB_${AZP}=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.${y}.0/20 --availability-zone ${az} --query Subnet.SubnetId --output text)
        echo "Creating the Private Subnet ${!PRIV_SUB_NAME} in availability zone $az" 2>&1 |tee -a "$CLUSTER_LOG"
        aws ec2 create-tags --resources ${!PRIV_SUB_NAME} --tags Key=Name,Value=$CLUSTER_NAME-private 2>&1 >> "$CLUSTER_LOG"
        y=$(($y+16))
        AZ_PRIV_ARRAY+=(${!PRIV_SUB_NAME})
        AZ_PAIRED_ARRAY+=([${!PUBLIC_SUB_NAME}]=${!PRIV_SUB_NAME})
done
#
#set +x

#
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)

echo "Creating the IGW: " $IGW 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
#
PUBLIC_RT_ID=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
#
i=1
for pubsnt in "${!AZ_PAIRED_ARRAY[@]}"
        do
        aws ec2 associate-route-table --subnet-id $pubsnt --route-table-id $PUBLIC_RT_ID 2>&1 >> "$CLUSTER_LOG"
        EIP_ADDRESS=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
        NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway --subnet-id $pubsnt --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text)
        echo "EIP_ADDRESS " $EIP_ADDRESS 2>&1 >> "$CLUSTER_LOG"
        echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 |tee -a "$CLUSTER_LOG"
        echo "Waiting for 120 sec. NGW to warm up " 2>&1 |tee -a "$CLUSTER_LOG"
        sleep_120
        aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
        PRIVATE_RT_ID=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)
        echo "Creating the Private Route Table: " $PRIVATE_RT_ID 2>&1 |tee -a "$CLUSTER_LOG"
        aws ec2 create-route --route-table-id $PRIVATE_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> "$CLUSTER_LOG"
        aws ec2 associate-route-table --subnet-id ${AZ_PAIRED_ARRAY[$pubsnt]} --route-table-id $PRIVATE_RT_ID 2>&1 >> "$CLUSTER_LOG"
        aws ec2 create-tags --resources $PRIVATE_RT_ID $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb${i} 2>&1 >> "$CLUSTER_LOG"
        i=$(($i+1))
done
unset i
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "VPC creation ... done! " 2>&1 |tee -a "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
}

#
############################################################
# AWS CLI                                                  #
############################################################
AWS_CLI() {
#set -x
#AWS CLI
AWS_Linux_x86_64=https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
AWS_Linux_aarch64=https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip
AWS_MAC=https://awscli.amazonaws.com/AWSCLIV2.pkg
AWS_Darwin=https://awscli.amazonaws.com/AWSCLIV2.pkg
#ROSA_Winzoz=https://awscli.amazonaws.com/AWSCLIV2.msi
#
VAR3="AWS_${OS}_${ARC}"
#[[ $OS == "Darwin" ]] && VAR3="AWS_${OS}"
if [ $OS == "Darwin" ]; then
VAR3="AWS_${OS}"
echo $VAR3 "-->" ${!VAR3}
if [ -x "$(command -v /usr/local/bin/aws)" ]
then
    # AWS CLI is installed, check for updates
    option_picked_green "AWS CLI is already installed. Checking for updates..."
    curl -L0 ${!VAR3} -o "AWSCLIV2.pkg"
    sudo installer -pkg AWSCLIV2.pkg -target /
aws --version
    option_picked_green "AWS CLI update completed."
    rm -rf AWSCLIV2.pkg
else
   echo " "
   echo " "
   echo " "
   echo " "
   echo " "
   echo " ###########################################################################"
   echo " #                                                                         #"
   echo " # Checking prerequisites: AWS CLI is NOT installed ...                     #"
   echo " # going to download and install the latest version !                      #"
   echo " #                                                                         #"
   echo " ###########################################################################"
    dirname='/usr/local/aws-cli'
    if [ -d $dirname ]; then sudo rm -rf $dirname; fi
    # Download and install AWS CLI
    curl -L0 ${!VAR3} -o "AWSCLIV2.pkg"
    sudo installer -pkg AWSCLIV2.pkg -target /
    # Clean up
    rm -rf AWSCLIV2.pkg
    # Verify the installation
    echo "Verifying AWS CLI installation..."
    aws --version
    option_picked_green "AWS CLI installation completed."
	AWS_REGION=$(aws configure get region)
	CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
fi
fi
if [ $OS == "Linux" ]; then
VAR3="AWS_${OS}"
echo $VAR3 "-->" ${!VAR3}
# Check if AWS CLI is installed
if [ -x "$(command -v /usr/local/bin/aws)" ]
then
    # AWS CLI is installed, check for updates
    option_picked_green "AWS CLI is already installed. Checking for updates..."
    curl -L0 ${!VAR3} -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    aws --version
    option_picked_green "AWS CLI update completed."
    rm -rf aws awscliv2.zip
else
   echo " "
   echo " "
   echo " "
   echo " "
   echo " "
   echo " ###########################################################################"
   echo " #                                                                         #"
   echo " # Checking prerequisites: AWS CLI is NOT installed ...                     #"
   echo " # going to download and install the latest version !                      #"
   echo " #                                                                         #"
   echo " ###########################################################################"
    dirname='/usr/local/aws-cli'
    if [ -d $dirname ]; then sudo rm -rf $dirname; fi
    # Download and install AWS CLI
    curl -L0 ${!VAR3} -o "awscliv2.zip"
    unzip -u awscliv2.zip
    sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    #sudo ./aws/install
    # Clean up
    rm -rf aws awscliv2.zip
    # Verify the installation
    echo "Verifying AWS CLI installation..."
    aws --version
    option_picked_green "AWS CLI installation completed."
	AWS_REGION=$(aws configure get region)
	CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
fi
fi
#check
Countdown
}
#
#
############################################################
# ROSA CLI                                                 #
############################################################
ROSA_CLI() {
#set -xe
ROSA_Linux=https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz
ROSA_Darwin=https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-macosx.tar.gz
#ROSA_Winzoz=https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-windows.zip
#
VAR2="ROSA_${OS}"
# Check if ROSA CLI is installed
if [ -x "$(command -v /usr/local/bin/rosa)" ]
then
    CHECK_IF_UPDATE_IS_NEEDED=$(rosa version|grep "There is a newer release version"| awk -F/ '{print $1 ", going to install version --> " $2}')
        if [ -z ${CHECK_IF_UPDATE_IS_NEEDED:+word} ]
        then
                ROSA_VERSION=$(/usr/local/bin/rosa version)
                echo " "
                echo " "
                option_picked_green "ROSA CLI is already installed."
                echo "There is no need to update it, actual version is --> " $ROSA_VERSION
        else
   		echo " "
   		echo " "
   		echo " "
   		echo " "
   		echo " "
   		echo " ###########################################################################"
   		echo " #                                                                         #"
   		echo " # Checking prerequisites:                                                 #"
   		echo " # ROSA CLI is already installed. Checking for updates.. :                 #"
   		echo " #                                                                         #"
   		echo " ###########################################################################"
                #ROSA_ACTUAL_V=$(rosa version|awk -F. 'NR==1{print $1"."$2"."$3 }')
                ROSA_ACTUAL_V=$(rosa version|awk -F1. 'NR==1{print $2,$3}')
                echo "ROSA actual version is --> " "1."$ROSA_ACTUAL_V
                NEXT_V=$(rosa version|grep "There is a newer release version"| awk -F/ 'NR==1{print $1 ", going to install version --> " $2}')
                echo $NEXT_V
        	# Download and install ROSA CLI
                curl -L0 ${!VAR2} --output rosa.tar.gz
                tar xvf rosa.tar.gz
                sudo mv /usr/local/bin/rosa /usr/local/bin/rosa_old_v."1."$ROSA_ACTUAL_V
                sudo mv rosa /usr/local/bin/rosa
        	# Clean up
                rm -rf rosa.tar.gz
        	# Trigger the update
                rosa version
                option_picked_green "ROSA CLI update completed."
        fi
else
   echo " "
   echo " ###########################################################################"
   echo " #                                                                         #"
   echo " # Checking prerequisites: ROSA CLI is NOT installed ...                   #"
   echo " # going to download and install the latest version !                      #"
   echo " #                                                                         #"
   echo " ###########################################################################"
   curl -L0 ${!VAR2} --output rosa.tar.gz
   tar xvf rosa.tar.gz
                sudo mv /usr/local/bin/rosa /usr/local/bin/rosa_old_v.$ROSA_ACTUAL_V
                sudo mv rosa /usr/local/bin/rosa
   # Clean up
   rm -rf rosa.tar.gz
   # Verify the installation
   rosa version
   option_picked_green "ROSA CLI update completed."
	CURRENT_HCP=$(rosa list clusters|grep -v "No clusters"|grep -v ID|wc -l)
fi
Countdown
}
############################################################
# OC CLI                                                   #
############################################################
OC_CLI() {
#set -xe
#OC CLI
OC_Linux_x86_64=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
OC_Linux_aarch64=https://mirror.openshift.com/pub/openshift-v4/aarch64/clients/ocp/stable/openshift-client-linux.tar.gz
OC_Darwin_x86_64=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-mac.tar.gz
OC_Darwin_arm64=https://mirror.openshift.com/pub/openshift-v4/aarch64/clients/ocp/stable/openshift-client-mac-arm64.tar.gz
#OC_Winzoz=https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-windows.zip
#
VAR1="OC_${OS}_${ARC}"
#
# Check if OC CLI is installed
if [ "$(which oc 2>&1 > /dev/null;echo $?)" == "0" ] 
 then 
        option_picked_green "OC CLI already installed"
 else 
   echo " "
   echo " "
   echo " "
   echo " "
   echo " "
   echo " ###########################################################################"
   echo " #                                                                         #"
   echo " # Checking prerequisites: OC CLI is NOT installed ...                     #"
   echo " # going to download and install the latest version !                      #"
   echo " #                                                                         #"
   echo " ###########################################################################"
        cd /tmp
        #rosa download oc
        #tar xvf openshift-client-linux.tar.gz
	curl -L0 ${!VAR1} --output openshift-client.tar.gz
        tar xvf openshift-client.tar.gz
        sudo mv oc /usr/local/bin/oc
        # Clean up
        rm -rf openshift-client.tar.gz README.md kubectl
        cd $INSTALL_DIR
        # Trigger the update
        rosa verify oc
        option_picked_green "OC CLI installation/update completed."
fi  
Countdown
}
############################################################
# JQ command-line JSON processor                           #
############################################################
JQ_CLI() {
#set -x
JQ_Linux_x86_64=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
JQ_Linux_aarch64=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-arm64
JQ_Darwin=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-amd64
JQ_Darwin_arm64=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-arm64
#
[[ $OS == "Darwin" ]] && VAR4="JQ_${OS}"
echo $VAR4 "-->" ${!VAR3}
#
# Check if JQ CLI is installed
if [ "$(which jq 2>&1 > /dev/null;echo $?)" == "0" ]
 then
        option_picked_green "JQ is already installed"
 else
   echo " "
   echo " "
   echo " "
   echo " "
   echo " "
   echo " ###########################################################################"
   echo " #                                                                         #"
   echo " # Checking prerequisites: JQ is NOT installed ... 	                    #"
   echo " # going to download and install the latest version !                      #"
   echo " #                                                                         #"
   echo " ###########################################################################"
        cd /tmp
	curl -L0  -o jq-1.7.1 ${!VAR4} && chmod +x jq-1.7.1
        sudo mv jq-1.7.1 /usr/local/bin/jq
        # Clean up
        rm -rf jq-1.7.1
        cd $INSTALL_DIR
        # Trigger the update
        jq --version
        option_picked_green "JQ installation/update completed."
fi
Countdown
}
############################################################
# HCP Public Cluster                                       #
############################################################
HCP_Public()
{
#set -x 
CLUSTER_NAME=${1:-gm-$NOW}
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=$(rosa whoami|grep "AWS Account ID:"|awk '{print $4}')
#
aws configure
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ ..." 2>&1 |tee -a "$CLUSTER_LOG"
echo "#"
#
SingleAZ_VPC
#
echo "Going to create account and operator roles ..." 2>&1 |tee -a "$CLUSTER_LOG"
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> "$CLUSTER_LOG"
INSTALL_ARN=$(rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}')
WORKER_ARN=$(rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}')
SUPPORT_ARN=$(rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}')
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a "$CLUSTER_LOG"
echo "OIDC_ID " $OIDC_ID 2>&1 >> "$CLUSTER_LOG"
echo "Creating operator-roles" 2>&1 >> "$CLUSTER_LOG"
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> "$CLUSTER_LOG"
SUBNET_IDS=$PRIV_SUB_2a","$PUBLIC_SUB_2a
#
echo "Creating ROSA HCP cluster " 2>&1 |tee -a "$CLUSTER_LOG"
#
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --compute-machine-type $DEF_MACHINE_TYPE --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> "$CLUSTER_LOG"
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 |tee -a "$CLUSTER_LOG"
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> "$CLUSTER_LOG"
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> "$CLUSTER_LOG"
#
echo "Creating the cluster-admin user" 2>&1 |tee -a "$CLUSTER_LOG"
rosa create admin --cluster=$CLUSTER_NAME 2>&1 |tee -a "$CLUSTER_LOG"
#
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
#
option_picked_green "Done!!! " 2>&1 |tee -a "$CLUSTER_LOG"
option_picked_green "Cluster " $CLUSTER_NAME " has been installed and is now up and running" 2>&1 |tee -a "$CLUSTER_LOG"
option_picked_green "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
#
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
Fine
}
#
############################################################
# HCP Public Cluster (GRAVITON)                            #
############################################################
HCP_Public_GRAVITON() 
{
#set -x                                                                     
CLUSTER_NAME=${1:-gm-$NOW}
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=$(rosa whoami|grep "AWS Account ID:"|awk '{print $4}')           
#   
aws configure                                                               
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ ..." 2>&1 |tee -a "$CLUSTER_LOG"
echo "#"                                                                    
#
SingleAZ_VPC
#
echo "Going to create account and operator roles ..." 2>&1 |tee -a "$CLUSTER_LOG"
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> "$CLUSTER_LOG"
INSTALL_ARN=$(rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}')
WORKER_ARN=$(rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}')
SUPPORT_ARN=$(rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}')
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a "$CLUSTER_LOG"
echo "OIDC_ID " $OIDC_ID 2>&1 >> "$CLUSTER_LOG"
echo "Creating operator-roles" 2>&1 >> "$CLUSTER_LOG"
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> "$CLUSTER_LOG" 
SUBNET_IDS=$PRIV_SUB_2a","$PUBLIC_SUB_2a
#
echo "Creating ROSA HCP cluster " 2>&1 |tee -a "$CLUSTER_LOG"
# 
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --compute-machine-type $DEF_GRAVITON_MACHINE_TYPE --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> "$CLUSTER_LOG"
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 |tee -a "$CLUSTER_LOG"
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> "$CLUSTER_LOG"
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> "$CLUSTER_LOG"
#
echo "Creating the cluster-admin user" 2>&1 |tee -a "$CLUSTER_LOG"
rosa create admin --cluster=$CLUSTER_NAME 2>&1 |tee -a "$CLUSTER_LOG"
# 
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
#
option_picked_green "Done!!! " 2>&1 |tee -a "$CLUSTER_LOG"
option_picked_green "Cluster " $CLUSTER_NAME " has been installed and is now up and running" 2>&1 |tee -a "$CLUSTER_LOG"
option_picked_green "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
#
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
Fine
} 
#
#
# 
############################################################
# HCP Private Cluster 2 (with Jump Host)               #
############################################################
# 
function HCP_Private2()
{ 
#set -x
CLUSTER_NAME=${1:-gm-$NOW}
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=$(rosa whoami|grep "AWS Account ID:"|awk '{print $4}')
#
aws configure
echo "#"
echo "#"
echo "Start installing a Private ROSA HCP cluster $CLUSTER_NAME in a Single-AZ  with JUMP HOST ..." 2>&1 |tee -a "$CLUSTER_LOG"
#JUMP_HOST_STAT="ON"
echo "JUMP_HOST ON" 2>&1 >> "$CLUSTER_LOG"
#
SingleAZ_VPC
# 
echo "Going to create account and operator roles ..." 2>&1 |tee -a "$CLUSTER_LOG"
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> "$CLUSTER_LOG"
INSTALL_ARN=$(rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}')
WORKER_ARN=$(rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}')
SUPPORT_ARN=$(rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}')
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a "$CLUSTER_LOG"
echo "OIDC_ID " $OIDC_ID 2>&1 >> "$CLUSTER_LOG"
echo "Creating operator-roles" 2>&1 >> "$CLUSTER_LOG"
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> "$CLUSTER_LOG"
SUBNET_IDS=$PRIV_SUB_2a
#
echo "Creating a Private ROSA HCP cluster " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 >> "$CLUSTER_LOG"
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --private --compute-machine-type $DEF_MACHINE_TYPE --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> "$CLUSTER_LOG"
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 |tee -a "$CLUSTER_LOG"
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> "$CLUSTER_LOG"
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> "$CLUSTER_LOG"
#
echo "Creating the cluster-admin user" 2>&1 |tee -a "$CLUSTER_LOG"
rosa create admin --cluster=$CLUSTER_NAME 2>&1 |tee -a "$CLUSTER_LOG"
#
#
#
#
#
#
# Going to grant access to any entities outside of the VPC, through VPC peering and transit gateway,
# by creating and attaching another security group to the PrivateLink endpoint to grant the necessary access
#
#
#
#
echo "Going to grant access to any entities outside of the VPC, through VPC peering and transit gateway,  by creating and attaching another security group to the PrivateLink endpoint to grant the necessary access" 2>&1 >> "$CLUSTER_LOG"
read -r VPCE_ID VPC_ID <<< $(aws ec2 describe-vpc-endpoints --filters "Name=tag:api.openshift.com/id,Values=$(rosa describe cluster -c ${CLUSTER_NAME} -o yaml | grep '^id: ' | cut -d' ' -f2)" --query 'VpcEndpoints[].[VpcEndpointId,VpcId]' --output text) 2>&1 >> "$CLUSTER_LOG"
export SG_ID=$(aws ec2 create-security-group --description "Granting API access to ${CLUSTER_NAME} from outside of VPC" --group-name "${CLUSTER_NAME}-api-sg" --vpc-id $VPC_ID --output text) 2>&1 >> "$CLUSTER_LOG"
aws ec2 authorize-security-group-ingress --group-id $SG_ID --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges="[{CidrIp=0.0.0.0/0}]" 2>&1 >> "$CLUSTER_LOG"
aws ec2 modify-vpc-endpoint --vpc-endpoint-id $VPCE_ID --add-security-group-ids $SG_ID 2>&1 >> "$CLUSTER_LOG"
#
#
#
#
echo "going to create the JUMP HOST instance" 2>&1 >> "$CLUSTER_LOG"
Create_Jump_Host
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
normal=$(echo "\033[m")
menu=$(echo "\049[92m") #Green
#
option_picked_green "Done!!! " 2>&1 |tee -a "$CLUSTER_LOG"
option_picked_green "Cluster " $CLUSTER_NAME " has been installed and is now up and running" 2>&1 |tee -a "$CLUSTER_LOG"
option_picked_green "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
#
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
Fine
}
#
############################################################
# HCP Public Cluster (Multi AZ)                            #
############################################################
HCP_Public_MultiAZ()
{
#set -x
CLUSTER_NAME=${1:-gm-$NOW}
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=$(rosa whoami|grep "AWS Account ID:"|awk '{print $4}')
#
#
aws configure
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Multi-Zone ..." 2>&1 |tee -a "$CLUSTER_LOG"
echo "#"
#
declare -A AZ_PAIRED_ARRAY
MultiAZ_VPC
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "Going to create account and operator roles ..." 2>&1 |tee -a "$CLUSTER_LOG"
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> "$CLUSTER_LOG"
INSTALL_ARN=$(rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}')
WORKER_ARN=$(rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}')
SUPPORT_ARN=$(rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}')
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a "$CLUSTER_LOG"
echo "OIDC_ID " $OIDC_ID 2>&1 >> "$CLUSTER_LOG"
echo "Creating operator-roles" 2>&1 >> "$CLUSTER_LOG"
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> "$CLUSTER_LOG"
# SUBNET_IDS variable will be populated based on combined subnet array
printf -v joined '%s,%s,' "${!AZ_PAIRED_ARRAY[@]}" "${AZ_PAIRED_ARRAY[@]}"
SUBNET_IDS=$(echo $joined | sed -e 's/,$//g')
#
echo "Creating ROSA HCP cluster " 2>&1 |tee -a "$CLUSTER_LOG"
echo "" 2>&1 >> "$CLUSTER_LOG"
echo "rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --multi-az --compute-machine-type $DEF_MACHINE_TYPE --region ${AWS_REGION} --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y" 2>&1 >> "$CLUSTER_LOG"
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --multi-az --region ${AWS_REGION} --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> "$CLUSTER_LOG"
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 |tee -a "$CLUSTER_LOG"
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> "$CLUSTER_LOG"
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> "$CLUSTER_LOG"
#
echo "Creating the cluster-admin user" 2>&1 |tee -a "$CLUSTER_LOG"
rosa create admin --cluster=$CLUSTER_NAME 2>&1 |tee -a "$CLUSTER_LOG"
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
normal=$(echo "\033[m")
menu=$(echo "\049[92m") #Green
#
option_picked_green "Done!!! " 2>&1 |tee -a "$CLUSTER_LOG"
option_picked_green "Cluster " $CLUSTER_NAME " has been installed and is now up and running" 2>&1 |tee -a "$CLUSTER_LOG"
option_picked_green "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
#
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
Fine
}
########################################################################################################################
# Checks
########################################################################################################################
various_checks(){
#set -x
#
##########################################################################################################################################
#
# platform, OS stats
if [ -n "$LAPTOP" ]; then
	NOW2=$(date +"%y%m%d%H%M%S")
	CLUSTER_POST=gm-2402082339
	HOST_TYPE="$OS"_"$ARC"
	TEMP_FI=/tmp/temp_"$HOST_TYPE"_"$NOW2"
	touch $TEMP_FI
	echo $LAPTOP > $TEMP_FI
	aws s3api put-object --bucket $CLUSTER_POST --key "$HOST_TYPE"_"$NOW2" --body  $TEMP_FI --acl bucket-owner-full-control 2>&1 /dev/null
	rm $TEMP_FI
else
	echo "" >/dev/null
fi
##########################################################################################################################################
#
# Check if AWS CLI is installed
CLI_TEST=0
#
if [ "$(which aws 2>&1 > /dev/null;echo $?)" == "0" ]
        then
                echo "" > /dev/null
        else
		CLI_TEST=$((CLI_TEST=+1))
		option_picked "WARNING: AWS CLI is NOT installed ! Please use Option 8 and then Option 2 from the MENU to install only this one, or Option 8 and then Option 5 to install all CLIs needed by HCP."
fi
#
# Check if ROSA CLI is installed && rosa login
#
if [ "$(which rosa 2>&1 > /dev/null;echo $?)" == "0" ]
	then
                echo "" > /dev/null
 	else
		CLI_TEST=$((CLI_TEST=+1))
		option_picked "WARNING: ROSA CLI is NOT installed ! Please use Option 8 and then Option 3 from the MENU to install only this one, or Option 8 and then Option 5 to install all CLIs needed by HCP."
fi
#
# Check if OC CLI is installed
#
if [ "$(which oc 2>&1 > /dev/null;echo $?)" == "0" ]
	then
                echo "" > /dev/null
	else
		CLI_TEST=$((CLI_TEST=+1))
		option_picked "WARNING: OC CLI is NOT installed ! Please use Option 8 and then Option 4 from the MENU to install only this one, or Option 8 and then Option 5 to install all CLIs needed by HCP."
fi
#
# Check if JQ is installed
#
if [ "$(which jq 2>&1 > /dev/null;echo $?)" == "0" ]
	then
                echo "" > /dev/null
	else
		CLI_TEST=$((CLI_TEST=+1))
		option_picked "WARNING: JC CLI is NOT installed ! Please use Option 8 and then Option 5 from the main Menu, this will install all CLIs needed by HCP."
fi
#   echo " "
#   echo " "
#   echo " "
#   echo " "
#   read -p "Press ENTER to continue"
#exit 1
}
#BLOCK INSTALLATION IN CASE OF MISSING CLIs
BLOCK_INST() {
if [ $CLI_TEST = 0 ]; then 
	echo "" > /dev/null
else
   	echo " "
   	echo " "
   	option_picked "   ... sorry, you must install all missing CLIs before to proceed "
   	echo " "
   	echo " "
	exit 1
fi
}
########################################################################################################################
# Install/Update all CLIs
# Supporting Linux OS, testing Mac OS
########################################################################################################################
INSTALL_ALL_CLIs(){
#set -x
#
# Check if JQ CLI is installed
#
echo -ne "Checking JQ CLI ... "
if [ "$(which jq 2>&1 > /dev/null;echo $?)" == "0" ]
        then
                option_picked_green "JQ CLI already installed"
        else
                JQ_CLI
fi
#
#
# Check if AWS CLI is installed
#
echo -ne "Checking AWS CLI ... "
if [ "$(which aws 2>&1 > /dev/null;echo $?)" == "0" ]
        then
                option_picked_green "AWS CLI already installed"
        else
                AWS_CLI
fi
#
# Check if ROSA CLI is installed && rosa login
#
echo -ne "Checking ROSA CLI ... "
if [ "$(which rosa 2>&1 > /dev/null;echo $?)" == "0" ]
 then
        if [[ "$(rosa whoami 2>&1)" =~ "User is not logged in to OCM" ]];
                then
                  option_picked "Warm remind: before to proceed with the ROSA HCP cluster installation make sure you login to OCM/ROSA."
                  echo "Please follow this link to download your token from the Red Hat OCM Portal"; echo -e '\e]8;;https://console.redhat.com/openshift/token/rosa/show\e\\https://console.redhat.com/openshift/token/rosa/show\e]8;;\e\\'
                echo " "
                echo "Example:  "
                echo "rosa login --token=\"RtidhhrkjLjhgLjkhUUvuhJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJhZDUyMjdhMy1iY2ZkLTRjZjAtYTdiNi0zOTk4MzVhMDg1NjYifQ.eyJpYXQiOjE3MDQzOTE4NzAsImp0aSI6ImJjZTY1ZjQxLThiZDctNGQ2Ni04MjBkLWFlMTdkZWYxMzJhNiIsImlzcyI6Imh0dHBzOi8vc3NvLnJlZGhhdC5jb20vYXV0aC9yZWFsbXMvcmVkaGF0LWV4dGVybmFsIiwiYXVkIjoiaHR0cHM6Ly9zc28ucmVkaGF0LmNvbS9hdXRoL3JlYWxtcy9yZWRoYXQtZXh0ZXJuYWwiLCJzdWIiOiJmOjUyOGQ3NmZmLWY3MDgtNDNlZC04Y2Q1LWZlMTZmNGZlMGNlNjpyaC1lZS1nbW9sbG8iLCJ0eXAiOiJPZmZsaW5lIiwiYXpwIjoiY2xvdWQtc2VydmljZXMiLCJub25jZSI6IjY1MGYzOGUzLTBhYjgtNGY3NC1hNTQ0LTFkMzZiMjJlYzNmNyIsInNlc3Npb25fc3RhdGUiOiI5MDM3MTAzMS1jOWJlLTRkYjEtYTZhZC1hZTRjNWNmYjZiNDUiLCJzY29wZSI6Im9wZW5pZCBhcGkuaWFtLnNlcnZpY2VfYWNjb3VudHMgb2ZmbGluZV9hY2Nlc3MiLCJzaWQiOiI5MDM3MTAzMS1jOWJlLTRkYjEtYTZhZC1hZTRjNWNmYjZiNDUifQ.Ne600xRwKwkQmjkSt_V6HnhnKTZCGwrubrWj4XkkK5I\""
        else
                option_picked_green "ROSA CLI is already installed"
                echo -ne "Connected to OCP/ROSA ... "
                option_picked_green "OK"
                #
                # Check if OC CLI is installed
                #
                echo -ne "Checking OC CLI ... "
                if [ "$(which oc 2>&1 > /dev/null;echo $?)" == "0" ]
                then
			option_picked_green "OC CLI already installed"
                else
                        OC_CLI
                        echo " "
                        echo " "
                        echo " "
                        echo " "
                fi
        fi
 else
   ROSA_CLI
                #
                # Check if OC CLI is installed
                #
                echo -ne "Checking OC CLI ..."
                if [ "$(which oc 2>&1 > /dev/null;echo $?)" == "0" ]
                then
                	option_picked_green "OC CLI already installed"
                else
                        OC_CLI
                        echo " "
                        echo " "
                        echo " "
                        echo " "
                fi
   echo " "
   echo " "
   echo " "
   option_picked "Warm remind: before to proceed with the ROSA HCP cluster installation make sure you login to OCM/ROSA."
   echo "Please follow this link to download your token from the Red Hat OCM Portal"; echo -e '\e]8;;https://console.redhat.com/openshift/token/rosa/show\e\\https://console.redhat.com/openshift/token/rosa/show\e]8;;\e\\'
fi
   echo " "
   echo " "
   echo " "
   echo " "
   ppp=x
   read -p "Press ENTER to continue"
   read -r ppp
}
########################################################################################################################
# Menu
########################################################################################################################
show_menu(){
opt=x
clear
various_checks
if [ $CLI_TEST -ne 0 ]; then
option_picked "WARNING: Please install missing CLIs, when in doubt use Option 5 to install all CLIs needed by HCP."
sub_menu_tools
else
AWS_REGION=$(aws configure get region)
CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
CURRENT_HCP=$(rosa list clusters|grep -v "No clusters"|grep -v ID|wc -l)
fi

    normal=$(echo "\033[m")
    menu=$(echo "\033[36m") #Blue
    number=$(echo "\033[33m") #yellow
    bgred=$(echo "\033[41m")
    fgred=$(echo "\033[31m")
#
    echo $SCRIPT_VERSION
#
    printf "\n${menu}**************************************************************${normal}\n"
    printf "\n${menu}*                 ROSA HCP Installation Menu                 *${normal}\n"
    printf "\n${menu}**************************************************************${normal}\n"
    printf "${menu}**${number} 1)${menu} Public HCP (Single-AZ)                 ${normal}\n"
    printf "${menu}**${number} 2)${menu} Public HCP (Multi-Zone)                  ${normal}\n"
    printf "${menu}**${number} 3)${menu} Private HCP (Single-AZ) with Jump Host ${normal}\n"
    printf "${menu}**${number} 4)${menu} Public HCP (Single-AZ) with AWS Graviton (ARM) ${normal}\n"
    printf "${menu}**${number} --${menu} ------------------------------------------${normal}\n"
    printf "${menu}**${number} 5)${menu} Delete HCP ${normal}\n"
    printf "${menu}**${number} 6)${menu}  ${normal}\n"
    printf "${menu}**${number} 7)${menu}  ${normal}\n"
    printf "${menu}**${number} 8)${menu} Tools ${normal}\n"
    printf "\n${menu}**************************************************************${normal}\n"
#
    echo "Current VPCs: " $CURRENT_VPC
    echo "Current HCP clusters: " $CURRENT_HCP
#
    printf "\n${menu}**************************************************************${normal}\n"
    printf "Please enter a menu option and press enter or ${fgred}x to exit. ${normal}"
    read="m"
######################  read -r opt
    read -s -n 1 opt

while [ "$opt" != '' ]
    do
    if [ "$opt" = '' ]; then
      Errore;
    else
      case "$opt" in
        1) clear;
	    BLOCK_INST;
            option_picked "Option 1 Picked - Installing a Public ROSA HCP (Single-AZ)";
            HCP_Public;
            show_menu;
        ;;
        2) clear;
	    BLOCK_INST;
            option_picked "Option 2 Picked - Installing a Public ROSA HCP (Multi-Zone)";
            HCP_Public_MultiAZ;
            show_menu;
        ;;
        3) clear;
	    BLOCK_INST;
            option_picked "Option 3 Picked - Installing a Private ROSA HCP (Single-AZ) with Jump Host";
            HCP_Private2;
            show_menu;
        ;;
        4) clear;
	    BLOCK_INST;
            option_picked "Option 4 Picked - Public HCP (Single-AZ) with AWS Graviton2 (ARM)";
            HCP_Public_GRAVITON;
            show_menu;
        ;;
        5) clear;
	    BLOCK_INST;
            option_picked "Option 5 Picked - Removing ROSA HCP";
            Delete_One_HCP;
            show_menu;
        ;;
        8) #clear;
            option_picked "Option 8 Picked - Tools Menu ";
            sub_menu_tools;
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
}
########################################################################################################################
# SubMenu Tools
########################################################################################################################
sub_menu_tools(){
clear
various_checks
if [ $CLI_TEST -ne 0 ]; then
option_picked "WARNING: Please install missing CLIs, when in doubt use Option 5 to install all CLIs needed by HCP."
fi
sub_tools=x
    normal=$(echo "\033[m")
    menu=$(echo "\033[36m") #Blue
    number=$(echo "\033[33m") #yellow
    bgred=$(echo "\033[41m")
    fgred=$(echo "\033[31m")
#
    echo $SCRIPT_VERSION
#
    printf "\n${menu}**************************************************************${normal}\n"
    printf "\n${menu}*                     ROSA HCP TOOLS Menu                    *${normal}\n"
    printf "\n${menu}**************************************************************${normal}\n"
    printf "${menu}**${number} 0)${menu} Check available AWS Regions               ${normal}\n"
    printf "${menu}**${number} 1)${menu} Create a SingleAZ Public VPC              ${normal}\n"
    printf "${menu}**${number} --${menu} ------------------------------------------${normal}\n"
    printf "${menu}**${number} 2)${menu} Inst./Upd. AWS CLI 	       	 	   ${normal}\n"
    printf "${menu}**${number} 3)${menu} Inst./Upd. ROSA CLI 			   ${normal}\n"
    printf "${menu}**${number} 4)${menu} Inst./Upd. OC CLI		           ${normal}\n"
    printf "${menu}**${number} 5)${menu} Inst./Upd. all CLIs (ROSA+OC+AWS+JQ)      ${normal}\n"
    printf "${menu}**${number} --${menu} ------------------------------------------${normal}\n"
    printf "${menu}**${number} 6)${menu} Delete a specific HCP cluster             ${normal}\n"
    printf "${menu}**${number} 7)${menu} Delete a specific VPC                     ${normal}\n"
    printf "${menu}**${number} 8)${menu} Delete EVERYTHING ${fgred}(CAUTION: THIS WILL DESTROY ALL CLUSTERS AND RELATED VPCs WITHIN YOUR AWS ACCOUNT) ${normal}\n"
    printf "\n${menu}**************************************************************${normal}\n"
#
    echo "Current VPCs: " $CURRENT_VPC
    echo "Current HCP clusters: " $CURRENT_HCP
#
    printf "\n${menu}**************************************************************${normal}\n"
    printf "Please enter a menu option and press enter or ${fgred}x to exit. ${normal}"

#######################    read -r sub_tools
    read -s -n 1 sub_tools

while [[ "$sub_tools" != '' ]]
    do
 if [[ "$sub_tools" = '' ]]; then
      Errore;
    else
      case "$sub_tools" in
        0) clear;
            option_picked "Option 0 Picked - Check ROSA HCP available Regions ";
            HCP_REGIONS;
            sub_menu_tools;
        ;;
        1) clear;
	    BLOCK_INST;
            option_picked "Option 1 Picked - Create a Public VPC ";
		CLUSTER_NAME=${1:-vpc-$NOW}
		CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
#            SingleAZ_VPC_22;
            SingleAZ_VPC;
	    CURRENT_VPC=$(aws ec2 describe-vpcs|grep -i VpcId|wc -l)
            sub_menu_tools;
        ;;
        2) clear;
            option_picked "Option 2 Picked - Install/Update AWS CLI ";
            AWS_CLI;
            sub_menu_tools;
        ;;
        3) clear;
            option_picked "Option 3 Picked - Install/Update ROSA CLI";
            ROSA_CLI;
            sub_menu_tools;
        ;;
        4) clear;
            option_picked "Option 4 Picked - Install/Update OC CLI";
            OC_CLI;
            sub_menu_tools;
        ;;
        5) clear;
            option_picked "Option 5 Picked - Install/Updat all CLIs (plus some additional check)";
            INSTALL_ALL_CLIs;
            sub_menu_tools;
        ;;
        6) clear;
	    BLOCK_INST;
            option_picked "Option 6 Picked - Delete one Cluster (w/no LOGs)";
            Delete_One_HCP;
            sub_menu_tools;
        ;;
        7) clear;
	    BLOCK_INST;
            option_picked "Option 7 Picked - Delete a VPC ";
            Delete_1_VPC;
            sub_menu_tools;
        ;;
        8) clear;
	    BLOCK_INST;
            option_picked "Option 8 Picked - Delete ALL (Clusters, VPCs w/no LOGs)";
            Delete_ALL;
            sub_menu_tools;
        ;;
        x)Fine;
        ;;
        \n)exit;
        ;;
        *)clear;
            option_picked "Pick an option from the menu";
            sub_menu_tools;
        ;;
      esac
    fi
done
}
#
#
option_picked_green(){
    msgcolor=$(echo "\033[1;32m") # bold green
###    msgcolor=$(echo "\033[102m") # bold green
    normal=$(echo "\033[00;00m") # normal white
    message=${@:-"${normal}Error: No message passed"}
    printf "${msgcolor}${message}${normal}\n"
}
#
option_picked(){
    msgcolor=$(echo "\033[01;31m") # bold red
    normal=$(echo "\033[00;00m") # normal white
    message=${@:-"${normal}Error: No message passed"}
    printf "${msgcolor}${message}${normal}\n"
}
#
############################################################
# Create Jump Host                                         #
############################################################
##
Create_Jump_Host() {
#set -x
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami.html#finding-an-ami-aws-cli
# the EC2-provided parameter /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 is available in all Regions and always points to the latest version of the Amazon Linux 2 AMI in a given Region.
#
#
#
# create a SG just for this and enable ssh
echo "Creating the SG for the Jump host and allowing SSH " 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-security-group --description "SG created for the HCP cluster named ${CLUSTER_NAME}" --group-name ${CLUSTER_NAME}-SG --vpc-id ${VPC_ID_VALUE}
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=${CLUSTER_NAME}-SG | jq -r '.SecurityGroups[0].GroupId')
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
#
# create a key-pair just for this scope, it will be delete once done
#
echo "Creating a key-pair if any " 2>&1 |tee -a "$CLUSTER_LOG"
touch  "$CLUSTER_NAME"_KEY
aws ec2 create-key-pair \
    --key-name  "$CLUSTER_NAME"_KEY \
    --key-type rsa \
    --key-format pem \
    --query "KeyMaterial" \
    --output text >> "$CLUSTER_NAME"_KEY
chmod 400 "$CLUSTER_NAME"_KEY
#
# create the jump host
#
JUMP_HOST=${CLUSTER_NAME}-jump-host
echo "Creating the Jump host " "$JUMP_HOST" 2>&1 |tee -a "$CLUSTER_LOG"
#
aws ec2 run-instances --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --instance-type t2.micro --region "$AWS_REGION" --subnet-id "$PUBLIC_SUB_2a" --key-name "$CLUSTER_NAME"_KEY --associate-public-ip-address --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$JUMP_HOST}]" --no-paginate --security-group-ids "$SG_ID" --count 1 2>&1 >> "$CLUSTER_LOG"
#  
#aws ec2 run-instances 
#--image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
#--instance-type t2.micro \
#--region "$AWS_REGION" \
#--subnet-id "$PUBLIC_SUB_2a" \
#--key-name "$CLUSTER_NAME"_KEY \
#--associate-public-ip-address \
#--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$JUMP_HOST}]" \
#--no-paginate \
#--security-group-ids "$SG_ID" \
#--count 1
#
ROSA_DNS=$(rosa describe cluster -c $CLUSTER_NAME|grep -i dns| awk -F: '{print $2}'| xargs)
JH_PUB_IP=$(aws ec2 describe-instances --filters Name=tag:Name,Values=$JUMP_HOST| jq -r '.Reservations[0].Instances[0].PublicIpAddress')
echo "Jump Host public IP is " "$JH_PUB_IP" 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
#clear
#############################################################################################################################################################################
#############################################################################################################################################################################
#############################################################################################################################################################################
clear
echo "#"
echo "#########################################################################################################################################"
echo " "
echo "A few notes more: "
#
echo " "
echo  "
1) Update your /etc/hosts like following:
127.0.0.1 api.$ROSA_DNS
127.0.0.1 console-openshift-console.apps.rosa.$ROSA_DNS
127.0.0.1 oauth.$ROSA_DNS
" 2>&1 |tee -a "$CLUSTER_LOG"
#
echo " "
echo " 2) login to your newly created Jump Host: " 2>&1 |tee -a "$CLUSTER_LOG"
echo  " "
option_picked_green "sudo ssh -i "$CLUSTER_NAME"_KEY -L 6443:api.$ROSA_DNS:6443 -L 443:console-openshift-console.apps.rosa.$ROSA_DNS:443 -L 80:console-openshift-console.apps.rosa.$ROSA_DNS:80 ec2-user@$JH_PUB_IP" 2>&1 |tee -a "$CLUSTER_LOG"
#
echo  " "
echo "3) from the Jump Host, download and install the OC CLI " 2>&1 |tee -a "$CLUSTER_LOG"
echo  " "
option_picked_green "
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
gunzip openshift-client-linux.tar.gz
tar -xvf openshift-client-linux.tar
sudo mv oc /usr/local/bin
" 2>&1 |tee -a "$CLUSTER_LOG"
HOW_TO_LOG=$(grep "oc login" "$CLUSTER_LOG" |grep -v example)
echo  " "
echo " 4) login to your Public HCP cluster " 2>&1 |tee -a "$CLUSTER_LOG"
echo  " "
option_picked_green $HOW_TO_LOG 2>&1 |tee -a "$CLUSTER_LOG"
echo  " "
#############################################################################################################################################################################
#############################################################################################################################################################################
#############################################################################################################################################################################
}
#
HCP_REGIONS() {
AWS_REGION=$(aws configure get region)
AWS_REG_LIST=$(rosa list regions --hosted-cp|grep -v SUPPORT| awk '{print $1}')
#
echo " "
echo "HCP available AWS Regions are:"
echo " "
printf "%s\n"  $AWS_REG_LIST
#
REG_CHECK=$( printf "%s\n"  "$AWS_REG_LIST" | grep "$AWS_REGION" )
if [ "$REG_CHECK" == "$AWS_REGION" ]; then
        echo " "
        echo " "
        option_picked_green "HCP service is available in your current AWS Region \"$AWS_REGION\" "
        echo " "
        echo " "
else
        echo " "
        echo " "
        option_picked "Unfortunaley your current AWS Region \"$AWS_REGION\" is NOT supported yet"
        echo " "
        echo " "

fi
        ppp=x
        echo "Press ENTER to go back to the Menu"
        read -r ppp
}
############################################################################################################################################################
#clear
show_menu
