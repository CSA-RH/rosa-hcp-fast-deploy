#!/bin/bash
######################################################################################################################
#
# Please note: this is very basic way to automate the HCP cluster setup via the CLI once your AWS blank environment
# (eg. RHPDS) has been created. The script will create the:
#  - the AWS env/roles needed to implemnet a ROSA HCP cluster, so AWS Access Key and AWS Secret Access Key are needed;
#  - the VPC, you can choose between Single-AZ or Multi-AZ;
#  - ROSA HCP cluster with minimal config (2x workers/Single-AZ; 3x workers/Multi-AZ).
#
# Once you are ready to delete it, the script will perform the reverse deleting what was previously created.
# It will look for the $CLUSTER_LOG file in order to be able to identify some resources (i.e. VPC Id, Subnets, ...).
#
# Feel free to modify it in order to suits your needs.
#
########################################################################################################################
#
#set -xe
RETVAL=$?
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
#
PREFIX=ManagedOpenShift
AWS_REGION=us-east-2
#
############################################################
# Single AZ                                                #
############################################################
SingleAZ()
{
NOW=`date +"%y%m%d%H%M"`
CLUSTER_NAME=gm-$NOW
INSTALL_DIR=$(pwd)
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
#
PREFIX=ManagedOpenShift
AWS_REGION=us-east-2
#
aws configure 
echo "#"
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
rosa init 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "rosa init ... done! going to create the VPC ..." 2>&1 |tee -a $CLUSTER_LOG
#
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
echo "Creating the VPC"  2>&1 >> $CLUSTER_LOG
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone us-east-2a --query Subnet.SubnetId --output text`
#echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone us-east-2a --query Subnet.SubnetId --output text`
#echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#echo "stacazzodesubnet " $PRIV_SUB_2a","$PUBLIC_SUB_2a 2>&1 >> $CLUSTER_LOG
IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
PUBLIC_RT_ID=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
#aws ec2 describe-route-tables --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
echo "Waiting for NAT GW to warm up (2min)" 2>&1 |tee -a $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
PRIVATE_RT_ID1=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! going to create account and operator roles, then your HCP Cluster ..." 2>&1 |tee -a $CLUSTER_LOG
#
rosa create account-roles --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
#
INSTALL_ARN=`rosa list account-roles|grep Install|grep HCP|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep HCP|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep HCP|awk '{print $3}'`
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "OIDC_ID " $OIDC_ID 2>&1 >> $CLUSTER_LOG
#
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG 
SUBNET_IDS=$PRIV_SUB_2a","$PUBLIC_SUB_2a
rosa create cluster --cluster-name=$CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 |tee -a $CLUSTER_LOG
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
rosa create admin --cluster=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "... done! " 2>&1 |tee -a $CLUSTER_LOG
echo " Please check the $CLUSTER_LOG LOG file for useful information " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
}
#
############################################################
# Multi AZ                                                 #
############################################################
MultiAZ()
{
NOW=`date +"%y%m%d%H%M"`
CLUSTER_NAME=gm-$NOW
INSTALL_DIR=$(pwd)
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
#
PREFIX=ManagedOpenShift
AWS_REGION=us-east-2
#
aws configure
echo "#"
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
rosa init 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "rosa init ... done! going to create the VPC ..." 2>&1 |tee -a $CLUSTER_LOG
#
echo "Creating the VPC"  2>&1 >> $CLUSTER_LOG
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone us-east-2a --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
PUBLIC_SUB_2b=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.16.0/20 --availability-zone us-east-2b --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources $PUBLIC_SUB_2b --tags Key=Name,Value=$CLUSTER_NAME-public
PUBLIC_SUB_2c=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.32.0/20 --availability-zone us-east-2c --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources $PUBLIC_SUB_2c --tags Key=Name,Value=$CLUSTER_NAME-public
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone us-east-2a --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
PRIV_SUB_2b=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.144.0/20 --availability-zone us-east-2b --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources  $PRIV_SUB_2b --tags Key=Name,Value=$CLUSTER_NAME-private
PRIV_SUB_2c=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.160.0/20 --availability-zone us-east-2c --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources  $PRIV_SUB_2c --tags Key=Name,Value=$CLUSTER_NAME-private
SUBNET_IDS=$PRIV_SUB_2a","$PRIV_SUB_2b","$PRIV_SUB_2c","$PUBLIC_SUB_2a","$PUBLIC_SUB_2b","$PUBLIC_SUB_2c
IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
PUBLIC_RT_ID=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
#aws ec2 describe-route-tables --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2b --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2c --route-table-id $PUBLIC_RT_ID
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
echo "EIP_ADDRESS " $EIP_ADDRESS 2>&1 >> $CLUSTER_LOG
NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
echo "Waiting for NAT GW to warm up (2min)" 2>&1 >> $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
PRIVATE_RT_ID1=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2a-rtb
PRIVATE_RT_ID2=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PRIVATE_RT_ID2 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2b --route-table-id $PRIVATE_RT_ID2
aws ec2 create-tags --resources $PRIVATE_RT_ID2 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2b-rtb
PRIVATE_RT_ID3=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PRIVATE_RT_ID3 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2c --route-table-id $PRIVATE_RT_ID3
aws ec2 create-tags --resources $PRIVATE_RT_ID3 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2c-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! going to create account and operator roles, then your HCP Cluster ..." 2>&1 |tee -a $CLUSTER_LOG
#
rosa create account-roles --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
INSTALL_ARN=`rosa list account-roles|grep Install|grep HCP|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep HCP|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep HCP|awk '{print $3}'`
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "OIDC_ID " $OIDC_ID 2>&1 >> $CLUSTER_LOG
#
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --multi-az --region us-east-2 --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> $CLUSTER_LOG
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
rosa create admin --cluster=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "... done! " 2>&1 |tee -a $CLUSTER_LOG
echo " Cluster " $CLUSTER_NAME " Has been installed and is up and running" 2>&1 |tee -a $CLUSTER_LOG
echo " Please check the $CLUSTER_LOG LOG file for useful information " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
}
#
############################################################
# Delete HCP                                               #
############################################################
Delete_HCP()
{
INSTALL_DIR=$(pwd)
CLUSTER_NAME=`ls $INSTALL_DIR|grep *.log| awk -F. '{print $1}'`
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
#
#
PREFIX=ManagedOpenShift
AWS_REGION=us-east-2
OIDC_ID=`rosa list oidc-provider -o json|grep arn| awk -F/ '{print $3}'|cut -c 1-32`
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
rosa delete cluster -c $CLUSTER_NAME --yes 2>&1 >> $CLUSTER_LOG
rosa logs uninstall -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
rosa delete operator-roles --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
rosa delete oidc-provider --oidc-config-id $OIDC_ID --mode auto --yes 2>&1 >> $CLUSTER_LOG
#
vpc_id=`cat $CLUSTER_LOG |grep VPC_ID_VALUE|awk '{print $2}'`
#
   while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways | jq -r '.NatGateways[].NatGatewayId') 2>&1 >> $CLUSTER_LOG
# NOTE: waiting for the NAT-GW to die - se non crepa non andiamo da nessuna parte
sleep 100
#
    while read -r sg ; do aws ec2 delete-security-group --group-id $sg ; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$vpc_id | jq -r '.SecurityGroups[].GroupId') 2>&1 >> $CLUSTER_LOG
    while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$vpc_id| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> $CLUSTER_LOG
    while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$vpc_id | jq -r '.Subnets[].SubnetId') 2>&1 >> $CLUSTER_LOG
   while read -r rt_id ; do aws ec2 delete-route-table --route-table-id $rt_id ;done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$vpc_id |jq -r '.RouteTables[].RouteTableId') 2>&1 >> $CLUSTER_LOG
   while read -r ig_id ; do aws ec2 detach-internet-gateway --internet-gateway-id $ig_id --vpc-id $vpc_id; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$vpc_id | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> $CLUSTER_LOG
   while read -r ig_id ; do aws ec2 delete-internet-gateway --internet-gateway-id $ig_id; done < <(aws ec2 describe-internet-gateways | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> $CLUSTER_LOG
   while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> $CLUSTER_LOG
#
aws ec2 delete-vpc --vpc-id=$vpc_id
#
rosa delete account-roles --mode auto --prefix $PREFIX --yes 2>&1 |tee -a $CLUSTER_LOG
rosa init --delete --yes 2>&1 |tee -a $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "... done! " 2>&1 |tee -a $CLUSTER_LOG
echo " Cluster " $CLUSTER_NAME " has been deleted !" 2>&1 |tee -a $CLUSTER_LOG
echo " You can find the old $CLUSTER_LOG LOG file in /tmp folder" 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
mv $CLUSTER_LOG /tmp
}
#
#
PS3='Please enter your choice: '
options=("Single-AZ 1" "Multi-AZ 2" "Delete_HCP 3" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Single-AZ 1")
          SingleAZ
		break
            ;;
        "Multi-AZ 2")
            MultiAZ
		break
            ;;
        "Delete_HCP 3")
            Delete_HCP
		break
            ;;
        "Quit")
            break
            ;;
        *) echo "invalid option $REPLY";;
    esac
done
#
