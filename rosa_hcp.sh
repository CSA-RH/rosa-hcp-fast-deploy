#!/usr/bin/env bash
######################################################################################################################
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
#   This is a single shell script that will create all the resources needed to deploy a ROSA HCP cluster via the CLI. The script will take care of:
#
#   - Set up your AWS account and roles (eg. the account-wide IAM roles and policies, cluster-specific Operator roles and policies, and OpenID Connect (OIDC) identity provider).
#   - Create the VPC;
#   - Create your ROSA HCP Cluster with a minimal configuration (eg. 2 workers/Single-AZ; 3 workers/Multi-AZ).
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
SCRIPT_VERSION=v1.0.7
#
#
########################################################################################################################
#set -x
INSTALL_DIR=$(pwd)
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
NOW=$(date +"%y%m%d%H%M")
CLUSTER_NAME=${1:-gm-$NOW}
PREFIX=${2:-$CLUSTER_NAME}
OS=$(uname -s)
ARC=$(uname -m)
############################################################
# Delete HCP (the LOG file is in place)                    #
############################################################
Delete_HCP()
{
#set -x
CLUSTER_COUNT=$(rosa list clusters|wc -l)
if [ "$CLUSTER_COUNT" -gt 2 ]; then
        option_picked "Found more than one clusterm with this Account, which is fine: please pick one HCP cluster from the following list"
	Delete_One_HCP
   	sub_menu_tools
else
  INSTALL_DIR=$(pwd)
  CLUSTER_NAME=$(ls "$INSTALL_DIR" |grep *.log| awk -F. '{print $1}')
  CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
  AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
  OIDC_ID=$(rosa list oidc-provider -o json|grep arn| awk -F/ '{print $3}'|cut -c 1-32)
  VPC_ID=$(cat "$CLUSTER_LOG" |grep VPC_ID_VALUE|awk '{print $2}')
#
  echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
  echo "# Start deleting ROSA HCP cluster $CLUSTER_NAME, VPC, roles, etc. " 2>&1 |tee -a "$CLUSTER_LOG"
  echo "# Further details can be found in $CLUSTER_LOG LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
  echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
#
  rosa delete cluster -c "$CLUSTER_NAME" --yes &>> "$CLUSTER_LOG"
	if [ $? -eq 0 ]; then
	  # start removing the NGW since it takes a lot of time
	  while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id "$instance_id"; done < <(aws ec2 describe-nat-gateways --filter 'Name=vpc-id,Values='"$VPC_ID"| jq -r '.NatGateways[].NatGatewayId') 2>&1 >> "$CLUSTER_LOG"
          echo "Cluster deletion in progress " 2>&1 |tee -a "$CLUSTER_LOG"
          rosa logs uninstall -c "$CLUSTER_NAME" --watch &>> "$CLUSTER_LOG"
          rosa delete operator-roles --prefix "$PREFIX" -m auto -y 2>&1 >> "$CLUSTER_LOG"
          echo "operator-roles deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
          rosa delete oidc-provider --oidc-config-id "$OIDC_ID" -m auto -y 2>&1 >> "$CLUSTER_LOG"
          echo "oidc-provider deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
	  Delete_VPC
	  rosa delete account-roles --mode auto --prefix "$PREFIX" --yes &>> "$CLUSTER_LOG"
	  echo "account-roles deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
	#
	#
	  echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
	  echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
	  echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
	  echo "done! " 2>&1 |tee -a "$CLUSTER_LOG"
	  option_picked_green "Cluster " "$CLUSTER_NAME" " was deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
	  option_picked_green "The old LOG file ${CLUSTER_LOG} in is now moved to /tmp folder" 2>&1 |tee -a "$CLUSTER_LOG"
	  echo " " 2>&1 |tee -a "$CLUSTER_LOG"
	  mv "$CLUSTER_LOG" /tmp
	  Countdown
	else
    	  option_picked "Unfortunately there are no clusters with name => " "$CLUSTER_NAME"
    	  echo "The VPC " $VPC_ID "will be deleted then"
# 	  NOTE: waiting for the NAT-GW to die - se non crepa non andiamo da nessuna parte
	  echo "waiting for the NAT-GW to die " 2>&1 |tee -a "$CLUSTER_LOG"
          while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways --filter 'Name=vpc-id,Values='$VPC_ID| jq -r '.NatGateways[].NatGatewayId') 2>&1 >> "$CLUSTER_LOG"
	  sleep_120
	  Delete_VPC
	fi
fi
#
#
}
#
#############################################################################################
# Select and delete an HCP c. and the VPC it belongs to, for example when there are NO logs #
#############################################################################################
Delete_One_HCP() {
#set -x
CLUSTER_LIST=$(rosa list clusters|grep -i "hosted cp"|awk '{print $2}')
echo ""
echo ""
if [ -n "$CLUSTER_LIST" ]; then
   echo "Current HCP cluster List:"
   echo "$CLUSTER_LIST"
   echo ""
   echo ""
   echo -n  "Please pick one or hit ENTER to quit: "
   read -r CLUSTER_NAME
	for a in $CLUSTER_LIST
    	do
		if [ "$CLUSTER_NAME" == $a ]; then
		option_picked_green "Let's get started with " "$CLUSTER_NAME" " cluster"
		echo ""
		echo ""
		CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
		#############################################################################################################################################################
                #############################################################################################################################################################
                #############################################################################################################################################################
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "# Start deleting ROSA HCP cluster $CLUSTER_NAME, VPC, roles, etc. " 2>&1 |tee -a "$CLUSTER_LOG"
echo "# Further details can be found in $CLUSTER_LOG LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
#
		#
		# Collecting a few details
		#
		rosa describe cluster -c $CLUSTER_NAME > $CLUSTER_NAME.txt
		OIDC_ID=$(cat $CLUSTER_NAME.txt |grep OIDC| awk -F/ '{print $4}'|cut -c 1-32)
		DEPLOYMENT=$(cat $CLUSTER_NAME.txt |grep "Data Plane"|awk -F: '{print $2}')
		DESIRED_NODES=$(cat $CLUSTER_NAME.txt |grep -i "Compute (desired)"|awk -F: '{print $2}')
		CURRENT_NODES=$(cat $CLUSTER_NAME.txt |grep -i "Compute (current)"|awk -F: '{print $2}')
		SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk -F, '{print $2}')
		#
		# Find $VPC_ID and start deleting NGW
		#
		VPC_ID=$(aws ec2 describe-subnets --subnet-ids $SUBN|grep -i vpc|awk -F\" '{print $4}')
# # # # # # # # echo "VPC_ID_VALUE " $VPC_ID 2>&1 >> "$CLUSTER_LOG"
		echo "Cluster " $CLUSTER_NAME "is a" $DEPLOYMENT "deployment with"$CURRENT_NODES"of "$DESIRED_NODES "nodes within the AWS VPC" $VPC_ID 2>&1 |tee -a "$CLUSTER_LOG"
		# start removing the NGW since it takes a lot of time
		echo "Removing the NGW since it takes a lot of time to get deleted"
        	while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways --filter 'Name=vpc-id,Values='$VPC_ID| jq -r '.NatGateways[].NatGatewayId') 2>&1 >> "$CLUSTER_LOG"
		#
		# Find $PREFIX
		#
		#PREFIX=$(cat $CLUSTER_NAME.txt |grep openshift-cluster-csi|awk -F- '{print $2}'|awk -F/ '{print $2}')
		PREFIX=$CLUSTER_NAME
		echo "Operator roles prefix: " $PREFIX
		#
		#Get started
		#
		echo "Running \"rosa delete cluster\"" 2>&1 |tee -a "$CLUSTER_LOG"
		rosa delete cluster -c $CLUSTER_NAME --yes &>> "$CLUSTER_LOG"
		echo "Running \"rosa logs unistall\"" 2>&1 |tee -a "$CLUSTER_LOG"
		rosa logs uninstall -c $CLUSTER_NAME --watch &>> "$CLUSTER_LOG"
		echo "Deleting operator-roles" 2>&1 |tee -a "$CLUSTER_LOG"
		rosa delete operator-roles --prefix $PREFIX -m auto -y 2>&1 >> "$CLUSTER_LOG"
		echo "Deleting OIDC " $OIDC_ID 2>&1 |tee -a "$CLUSTER_LOG"
		rosa delete oidc-provider --oidc-config-id $OIDC_ID -m auto -y 2>&1 >> "$CLUSTER_LOG"
		#
		echo "Deleting account-roles " 2>&1 |tee -a "$CLUSTER_LOG"
		rosa delete account-roles --mode auto --prefix $PREFIX -m auto -y  &>> "$CLUSTER_LOG"
		#
		#################################################################################################################################
		# Delete the VPC it belongs to
		#
		SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk -F, '{print $2}')
		VPC_ID=$(aws ec2 describe-subnets --subnet-ids $SUBN|grep -i vpc|awk -F\" '{print $4}')
    		echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a "$CLUSTER_LOG"
		#
		#
   		while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> "$CLUSTER_LOG"
   		while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> "$CLUSTER_LOG"
   		while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> "$CLUSTER_LOG"
   		while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> "$CLUSTER_LOG"
   		while read -r ig_id ; do aws ec2 detach-internet-gateway --internet-gateway-id $ig_id --vpc-id $VPC_ID; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> "$CLUSTER_LOG"
   		while read -r ig_id ; do aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $ig_id; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> "$CLUSTER_LOG"
   		while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> "$CLUSTER_LOG"
		#
		aws ec2 delete-vpc --vpc-id=$VPC_ID &>> $CLUSTER_LOG
		option_picked_green "VPC ${VPC_ID} deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
		echo " "
		option_picked_green "HCP Cluster $CLUSTER_NAME deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
		mv *.log /tmp
	else
		option_picked "This option doesn't match with $a or simply no HCP Cluster was chosen from the above list, returning to the Tools menu !"
        fi
	done
else
echo " "
echo " "
option_picked "Unfortunately there are no HCP clusters in this accout"
fi
#################################################################################################################################
#
#
echo "" 
echo ""
echo "Press ENTER key to go back to the Menu"
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
set -x
# how many clusters do we have ?
#
#set -x
CLUSTER_LIST=$(rosa list clusters|grep -i "hosted cp"|awk '{print $2}')
for a in $CLUSTER_LIST
do
  CLUSTER_NAME=$a
  CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
#
# Collecting a few details
#
  rosa describe cluster -c $a >$a.txt
  OIDC_ID=$(cat $CLUSTER_NAME.txt |grep OIDC| awk -F/ '{print $4}'|cut -c 1-32)
  DEPLOYMENT=$(cat $CLUSTER_NAME.txt |grep "Data Plane"|awk -F: '{print $2}')
  DESIRED_NODES=$(cat $CLUSTER_NAME.txt |grep -i "Compute (desired)"|awk -F: '{print $2}')
  CURRENT_NODES=$(cat $CLUSTER_NAME.txt |grep -i "Compute (current)"|awk -F: '{print $2}')
# Find VPC_ID
#  SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk -F, '{print $2}')
  SUBN=$(cat $CLUSTER_NAME.txt |grep -i "Subnets"|awk -F, '{print $1}'|awk -F: '{print $2}')
  VPC_ID=$(aws ec2 describe-subnets --subnet-ids $SUBN|grep -i vpc|awk -F\" '{print $4}')
  echo "Cluster " $a "is a " $DEPLOYMENT "deployment with "$CURRENT_NODES"of "$DESIRED_NODES "nodes in VPC "$VPC_ID
# start removing the NGW since it takes a lot of time
  while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways --filter 'Name=vpc-id,Values='$VPC_ID| jq -r '.NatGateways[].NatGatewayId') 2>&1 >> "$CLUSTER_LOG"
#
# Find $PREFIX
#
### PREFIX=$(rosa list account-roles| grep $a|grep Install|awk '{print $1}'| sed 's/.\{24\}$//')
  #PREFIX=$(cat $a.txt |grep openshift-cluster-csi|awk -F- '{print $2}'|awk -F/ '{print $2}')
  PREFIX="$CLUSTER_NAME"
  echo "Operator roles prefix: " "$PREFIX"
#
#Get started 
   option_picked "Going to delete the HCP cluster named " "$CLUSTER_NAME" " and the VPC " "$VPC_ID" 2>&1 |tee -a "$CLUSTER_LOG"
#
  echo "Deleting HCP Cluster" 2>&1 |tee -a "$CLUSTER_LOG"
  rosa delete cluster -c $CLUSTER_NAME --yes &>> "$CLUSTER_LOG"
  echo "You can watch logs with \"$ tail -f $CLUSTER_LOG\"" 2>&1 |tee -a "$CLUSTER_LOG"
rosa logs uninstall -c $CLUSTER_NAME --watch &>> "$CLUSTER_LOG"
echo "Deleting operator-roles with PREFIX= " "$PREFIX" 2>&1 |tee -a "$CLUSTER_LOG"
rosa delete operator-roles --prefix $PREFIX -m auto -y 2>&1 >> "$CLUSTER_LOG"
echo "Deleting OIDC " $OIDC_ID 2>&1 |tee -a "$CLUSTER_LOG"
rosa delete oidc-provider --oidc-config-id $OIDC_ID -m auto -y 2>&1 >> "$CLUSTER_LOG"
#
echo "Deleting account-roles with PREFIX= " "$PREFIX" 2>&1 |tee -a "$CLUSTER_LOG"
rosa delete account-roles --mode auto --prefix $PREFIX --yes &>> "$CLUSTER_LOG"
#

#########################
SUBN=$(cat $a.txt |grep -i "Subnets"|awk -F, '{print $2}')
VPC_ID=$(aws ec2 describe-subnets --subnet-ids $SUBN|grep -i vpc|awk -F\" '{print $4}')
    echo "########### " 2>&1 |tee -a "$CLUSTER_LOG"
    echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a "$CLUSTER_LOG"
#
#
   while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> "$CLUSTER_LOG"
   while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> "$CLUSTER_LOG"
   while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> "$CLUSTER_LOG"
   while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> "$CLUSTER_LOG"
   while read -r ig_id ; do aws ec2 detach-internet-gateway --internet-gateway-id $ig_id --vpc-id $VPC_ID; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> "$CLUSTER_LOG"
   while read -r ig_id ; do aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $ig_id; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> "$CLUSTER_LOG"
   while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> "$CLUSTER_LOG"
#
aws ec2 delete-vpc --vpc-id=$VPC_ID &>> $CLUSTER_LOG
option_picked_green "VPC ${VPC_ID} deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
mv *.log *.txt /tmp
#########################
#
done
}
#######################################################################################################################################
#######################################################################################################################################
Delete_VPC()
{
    echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a "$CLUSTER_LOG"
#
#
    while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> "$CLUSTER_LOG"
    while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> "$CLUSTER_LOG"
    while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> "$CLUSTER_LOG"
   while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> "$CLUSTER_LOG"; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> "$CLUSTER_LOG"
   while read -r ig_id ; do aws ec2 detach-internet-gateway --internet-gateway-id $ig_id --vpc-id $VPC_ID; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> "$CLUSTER_LOG"
   while read -r ig_id ; do aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $ig_id; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> "$CLUSTER_LOG"
   while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> "$CLUSTER_LOG"
#
aws ec2 delete-vpc --vpc-id=$VPC_ID &>> $CLUSTER_LOG
echo "VPC ${VPC_ID} deleted !" 2>&1 |tee -a "$CLUSTER_LOG"
}
#######################################################################################################################################
#######################################################################################################################################
#######################################################################################################################################
#######################################################################################################################################
#######################################################################################################################################
Delete_1_VPC() {
#
#set -x
CLUSTER_NAME=delete-vpc
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
#
VPC_LIST=$(aws ec2 describe-vpcs |grep -i vpcid|awk  '{print $2}'|awk -F\"  '{print $2}')
if [ -n "$VPC_LIST" ]; then
   echo "Current VPCs:"
   echo $VPC_LIST
   echo ""
   echo ""
   echo -n  "Please pick one or hit ENTER to quit: "
   read -r VPC_ID
   for a in $VPC_LIST
    do
	if [ "$VPC_ID" == $a ]; then
		echo  "Going to delete --> " "$VPC_ID"
		#############################################################################################################################################################
                #############################################################################################################################################################
                #############################################################################################################################################################
        	echo ""
        	echo "#############################################################################"
        	echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a $CLUSTER_LOG
# NOTE: waiting for the NAT-GW to die - se non crepa non andiamo da nessuna parte
        	echo "waiting for the NAT-GW to die " 2>&1 |tee -a $CLUSTER_LOG
        	while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways --filter 'Name=vpc-id,Values='$VPC_ID| jq -r '.NatGateways[].NatGatewayId') 2>&1 >> $CLUSTER_LOG
		#sleep_120
#
        	while read -r sg ; do aws ec2 delete-security-group --no-cli-pager --group-id $sg 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> $CLUSTER_LOG
        	while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> $CLUSTER_LOG
        	while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> $CLUSTER_LOG
        	while read -r rt_id ; do aws ec2 delete-route-table --no-cli-pager --route-table-id $rt_id 2>&1 >> $CLUSTER_LOG; done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> $CLUSTER_LOG
        	while read -r ig_id ; do aws ec2 detach-internet-gateway --internet-gateway-id $ig_id --vpc-id $VPC_ID; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> $CLUSTER_LOG
        	while read -r ig_id ; do aws ec2 delete-internet-gateway --no-cli-pager --internet-gateway-id $ig_id; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> $CLUSTER_LOG
        	while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> $CLUSTER_LOG
#
#
        	aws ec2 delete-vpc --no-cli-pager --vpc-id=$VPC_ID &>> $CLUSTER_LOG
        	echo ""
        	echo ""
        	echo "#############################################################################"
        	echo ""
        	echo ""
        	option_picked_green "VPC ${VPC_ID} deleted !" 2>&1 |tee -a $CLUSTER_LOG
		mv *.log *.txt /tmp
                #############################################################################################################################################################
                #############################################################################################################################################################
                #############################################################################################################################################################
	else
   		option_picked "That doesn't match or no VPC was chosen, returning to the Tools Menu !"
        fi
	done
else
echo " "
echo " "
option_picked "Unfortunately there are No VPCs within this AWS accout"
fi
#
#
#
echo ""
echo ""
echo "Press ENTER key to go back to the Menu"
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
SingleAZ-VPC() {
echo "#"
aws sts get-caller-identity 2>&1 >> "$CLUSTER_LOG"
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> "$CLUSTER_LOG"
#rosa verify permissions 2>&1 >> "$CLUSTER_LOG"
#rosa verify quota --region=$AWS_REGION
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
#
VPC_ID_VALUE=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)

echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a "$CLUSTER_LOG"
#
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PUBLIC_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)
echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
#
PRIV_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)
echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
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
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "VPC creation ... done! " 2>&1 |tee -a "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
}
#
############################################################
# Single AZ (Private)                                      #
############################################################
#
SingleAZ-VPC-Priv() {
echo "#" 
aws sts get-caller-identity 2>&1 >> "$CLUSTER_LOG"
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
#
VPC_ID_VALUE=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text)

echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a "$CLUSTER_LOG"
#
# 
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> "$CLUSTER_LOG"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PRIV_SUB_2a=$(aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text)

echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 |tee -a "$CLUSTER_LOG"
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
PRIVATE_RT_ID1=$(aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text)

echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 |tee -a "$CLUSTER_LOG"
#aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> "$CLUSTER_LOG"
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> "$CLUSTER_LOG"
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
echo "VPC creation ... done! " 2>&1 |tee -a "$CLUSTER_LOG"
echo "#" 2>&1 |tee -a "$CLUSTER_LOG"
}
#
############################################################
# Multi AZ                                                 #
############################################################
#
MultiAZ-VPC() {
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
#ROSA_Winzoz=https://awscli.amazonaws.com/AWSCLIV2.msi
#
VAR3="AWS_${OS}_${ARC}"
[[ $OS == "Darwin" ]] && VAR3="AWS_${OS}"
echo "-------------------------------------"
echo $VAR3 "-->" ${!VAR3}
# Check if AWS CLI is installed
if [ -x "$(command -v /usr/local/bin/aws)" ]
then
    # AWS CLI is installed, check for updates
    option_picked_green "AWS CLI is already installed. Checking for updates..."
    curl ${!VAR3} -o "awscliv2.zip"
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
    curl ${!VAR3} -o "awscliv2.zip"
    unzip -u awscliv2.zip
    sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
    #sudo ./aws/install
    # Clean up
    rm -rf aws awscliv2.zip
    # Verify the installation
    echo "Verifying AWS CLI installation..."
    aws --version
    option_picked_green "AWS CLI installation completed."
fi
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
ROSA_MAC=https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-macosx.tar.gz
#ROSA_Winzoz=https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-windows.zip
#
VAR2="ROSA_${OS}"
# Check if ROSA CLI is installed
if [ -x "$(command -v /usr/local/bin/rosa)" ]
then
    CHECK_IF_UPDATE_IS_NEEDED=${rosa version|grep "There is a newer release version"| awk -F\ '{print $1 ", going to install version --> " $2}'}
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
                ROSA_ACTUAL_V=$(rosa version|awk -F. 'NR==1{print $1"."$2"."$3 }')
                echo "ROSA actual version is --> " $ROSA_ACTUAL_V
                NEXT_V=$(rosa version|grep "There is a newer release version"| awk -F\ 'NR==1{print $1 ", going to install version --> " $2}')
                echo $NEXT_V
        	# Download and install ROSA CLI
                curl ${!VAR2} --output rosa-linux.tar.gz
                tar xvf rosa-linux.tar.gz
                sudo mv rosa /usr/local/bin/rosa
        	# Clean up
                rm -rf rosa-linux.tar.gz
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
   curl ${!VAR2} --output rosa-linux.tar.gz
   tar xvf rosa-linux.tar.gz
   sudo mv rosa /usr/local/bin/rosa
   # Clean up
   rm -rf rosa-linux.tar.gz
   # Verify the installation
   rosa version
   option_picked_green "ROSA CLI update completed."
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
	curl ${!VAR1} --output openshift-client.tar.gz
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
#set -xe
JQ_Linux_x86_64=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
JQ_Linux_aarch64=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-arm64
JQ_Darwin_x86_64=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-amd64
JQ_Darwin_arm64=https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-arm64
#
VAR4="JQ_${OS}_${ARC}"
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
	curl -L -o jq-1.7.1 ${!VAR4} && chmod +x jq-1.7.1
        sudo mv jq-1.7.1 /usr/bin/jq
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
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ ..." 2>&1 |tee -a "$CLUSTER_LOG"
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
echo "#"
#
SingleAZ-VPC
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
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> "$CLUSTER_LOG"
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
############################################################
# HCP PrivateLink Cluster                                  #
############################################################
# 
function HCP-Private()
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
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ (Private) ..." 2>&1 |tee -a "$CLUSTER_LOG"
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
#
SingleAZ-VPC-Priv
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
echo "Creating ROSA HCP cluster " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 >> "$CLUSTER_LOG"
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --private-link --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> "$CLUSTER_LOG"
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
echo "Done!!! " 2>&1 |tee -a "$CLUSTER_LOG"
echo "Cluster " $CLUSTER_NAME " has been installed and is now up and running" 2>&1 |tee -a "$CLUSTER_LOG"
printf "${menu} Cluster " $CLUSTER_NAME " has been installed and is now up and runningi${normal}\n" 2>&1 |tee -a "$CLUSTER_LOG"
echo "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
echo " " 2>&1 |tee -a "$CLUSTER_LOG"
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
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Multi-AZ ..." 2>&1 |tee -a "$CLUSTER_LOG"
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
echo "#"
#
declare -A AZ_PAIRED_ARRAY
MultiAZ-VPC
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
echo "rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --multi-az --region ${AWS_REGION} --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y" 2>&1 >> "$CLUSTER_LOG"
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
echo "Done!!! " 2>&1 |tee -a "$CLUSTER_LOG"
echo "Cluster " $CLUSTER_NAME " has been installed and is now up and running" 2>&1 |tee -a "$CLUSTER_LOG"
printf "${menu} Cluster " $CLUSTER_NAME " has been installed and is now up and runningi${normal}\n" 2>&1 |tee -a "$CLUSTER_LOG"
echo "Please allow a few minutes before to login, for additional information check the $CLUSTER_LOG file" 2>&1 |tee -a "$CLUSTER_LOG"
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
# Check if AWS CLI is installed
#
if [ "$(which aws 2>&1 > /dev/null;echo $?)" == "0" ]
        then
                test_count=1
        else
		option_picked "WARNING: AWS CLI is NOT installed ! Please use Option 8 and then Option 5 from the MENU to install only this one, or Option 8 to install all CLIs needed by HCP."
fi
#
# Check if ROSA CLI is installed && rosa login
#
if [ "$(which rosa 2>&1 > /dev/null;echo $?)" == "0" ]
	then
                test_count=2
 	else
		option_picked "WARNING: ROSA CLI is NOT installed ! Please use Option 8 and then Option 6 from the MENU to install only this one, or Option 8 to install all CLIs needed by HCP."
fi
#
# Check if OC CLI is installed
#
if [ "$(which oc 2>&1 > /dev/null;echo $?)" == "0" ]
	then
                test_count=3
	else
		option_picked "WARNING: OC CLI is NOT installed ! Please use Option 8 and then Option 7 from the MENU to install only this one, or Option 8 to install all CLIs needed by HCP."
fi
#
# Check if JQ is installed
#
if [ "$(which jq 2>&1 > /dev/null;echo $?)" == "0" ]
	then
                test_count=4
	else
		option_picked "WARNING: JC CLI is NOT installed ! Please use Option 8 from the main Menu, this will install all CLIs needed by HCP."
		option_picked "WARNING: JC CLI is NOT installed ! Please use Option 8 and then Option 8 from the MENU to install it."
fi
#   echo " "
#   echo " "
#   echo " "
#   echo " "
#   read -p "Press enter to continue"
}
########################################################################################################################
# Install/Update all CLIs
# Supporting Linux OS, testing Mac OS
########################################################################################################################
various_checks2(){
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
   read -p "Press enter to continue"
}
########################################################################################################################
# Menu
########################################################################################################################
show_menu(){
clear
various_checks
    normal=$(echo "\033[m")
    menu=$(echo "\033[36m") #Blue
    number=$(echo "\033[33m") #yellow
    bgred=$(echo "\033[41m")
    fgred=$(echo "\033[31m")
#
    echo $SCRIPT_VERSION
#
    printf "\n${menu}************************************************************${normal}\n"
    printf "\n${menu}*               ROSA HCP Installation Menu                 *${normal}\n"
    printf "\n${menu}************************************************************${normal}\n"
    printf "${menu}**${number} 1)${menu} HCP Public in Single-AZ                 ${normal}\n"
    printf "${menu}**${number} 2)${menu} HCP Public in Multi-AZ                  ${normal}\n"
    printf "${menu}**${number} 3)${menu} HCP PrivateLink in Single-AZ            ${normal}\n"
    printf "${menu}**${number} 4)${menu} Delete HCP ${normal}\n"
    printf "${menu}**${number} 5)${menu}  ${normal}\n"
    printf "${menu}**${number} 6)${menu}  ${normal}\n"
    printf "${menu}**${number} 7)${menu}  ${normal}\n"
    printf "${menu}**${number} 8)${menu} Tools ${normal}\n"
    printf "\n${menu}************************************************************${normal}\n"
    printf "Please enter a menu option and enter or ${fgred}x to exit. ${normal}"
    read="m"
    read -r opt

while [ "$opt" != '' ]
    do
    if [ "$opt" = '' ]; then
      Errore;
    else
      case "$opt" in
        1) clear;
            option_picked "Option 1 Picked - Installing ROSA with HCP Public (Single-AZ)";
            HCP-Public;
            show_menu;
        ;;
        2) clear;
            option_picked "Option 2 Picked - Installing ROSA with HCP Public (Multi-AZ)";
            HCP-Public-MultiAZ;
            show_menu;
        ;;
        3) clear;
            option_picked "Option 3 Picked - Installing ROSA with HCP PrivateLink (Single-AZ)";
            HCP-Private;
            show_menu;
        ;;
        4) clear;
            option_picked "Option 4 Picked - Removing ROSA with HCP";
            Delete_HCP;
            show_menu;
        ;;
        8) clear;
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
    normal=$(echo "\033[m")
    menu=$(echo "\033[36m") #Blue
    number=$(echo "\033[33m") #yellow
    bgred=$(echo "\033[41m")
    fgred=$(echo "\033[31m")
#
    echo $SCRIPT_VERSION
#
    printf "\n${menu}************************************************************${normal}\n"
    printf "\n${menu}*               ROSA HCP TOOLS Menu                        *${normal}\n"
    printf "\n${menu}************************************************************${normal}\n"
    printf "${menu}**${number} 1)${menu} Delete a specific HCP Cluster (w/no LOGs) ${normal}\n"
    printf "${menu}**${number} 2)${menu} Delete a specific VPC                     ${normal}\n"
    printf "${menu}**${number} 3)${menu} Delete EVERYTHING (clean up the whole env)${normal}\n"
    printf "${menu}**${number} 4)${menu}                                         ${normal}\n"
    printf "${menu}**${number} 5)${menu} Inst./Upd. AWS CLI 	       	 	 ${normal}\n"
    printf "${menu}**${number} 6)${menu} Inst./Upd. ROSA CLI 			 ${normal}\n"
    printf "${menu}**${number} 7)${menu} Inst./Upd. OC CLI			 ${normal}\n"
    printf "${menu}**${number} 8)${menu} Inst./Upd. all CLIs (ROSA+OC+AWS+JQ)    ${normal}\n"
    printf "\n${menu}************************************************************${normal}\n"
    printf "Please enter a menu option and enter or ${fgred}x to exit. ${normal}"
    read -r sub_tools
while [[ "$sub_tools" != '' ]]
    do
 if [[ "$sub_tools" = '' ]]; then
      Errore;
    else
      case "$sub_tools" in
        1) clear;
            option_picked "Option 1 Picked - Delete one Cluster (w/no LOGs)";
            Delete_One_HCP;
            sub_menu_tools;
        ;;
        2) clear;
            option_picked "Option 2 Picked - Delete a VPC ";
            Delete_1_VPC;
            sub_menu_tools;
        ;;
        3) clear;
            option_picked "Option 3 Picked - Delete ALL (Clusters, VPCs w/no LOGs)";
            Delete_ALL;
        ;;
        5) clear;
            option_picked "Option 5 Picked - Install/Update AWS CLI ";
            AWS_CLI;
            sub_menu_tools;
        ;;
        6) clear;
            option_picked "Option 6 Picked - Install/Update ROSA CLI";
            ROSA_CLI;
            sub_menu_tools;
        ;;
        7) clear;
            option_picked "Option 7 Picked - Install/Update OC CLI";
            OC_CLI;
            sub_menu_tools;
        ;;
        8) clear;
            option_picked "Option 8 Picked - Install/Updat all CLIs (plus some additional check)";
            various_checks2;
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
############################################################################################################################################################
#clear
show_menu
