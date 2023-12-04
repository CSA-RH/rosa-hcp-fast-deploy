#!/bin/bash
######################################################################################################################
#
# This is a single shell script that will create all the resources needed to deploy a public HCP cluster via the CLI. In more depth the script will take care of:
#
# - Set up your AWS account and roles (eg. the account-wide IAM roles and policies, cluster-specific Operator roles and policies, and OpenID Connect (OIDC) identity provider).
# - Create the VPC;
# - Create your ROSA HCP Cluster with a minimal configuration (2 workers/Single-AZ; 3 workers/Multi-AZ).
#
# Including its related VPC, it takes approximately 15 minutes to create/destroy an HCP cluster.
#
#
# Once you are ready to delete it, the script will perform the reverse deleting what was previously created.
# It will look for the $CLUSTER_LOG file in order to be able to identify some resources (i.e. VPC Id, Subnets, ...).
#
# Feel free to modify it in order to suits your needs.
#
########################################################################################################################
#
set -x
RETVAL=$?
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
#
PREFIX=TestManagedHCP
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
PREFIX=TestManagedHCP
#
aws configure 
echo " Installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
echo "#"
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
#rosa init 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#echo "rosa init ... done! going to create the VPC ..." 2>&1 |tee -a $CLUSTER_LOG
#
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
echo "Creating the VPC"  2>&1 >> $CLUSTER_LOG
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone $AWS_REGIONa --query Subnet.SubnetId --output text`
#echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone $AWS_REGIONa --query Subnet.SubnetId --output text`
#echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#echo "stacazzodesubnet " $PRIV_SUB_2a","$PUBLIC_SUB_2a 2>&1 >> $CLUSTER_LOG
IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
PUBLIC_RT_ID=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
#aws ec2 describe-route-tables --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
echo "Waiting for NAT GW to warm up (2min)" 2>&1 |tee -a $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
PRIVATE_RT_ID1=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! going to create account and operator roles, then your HCP Cluster ..." 2>&1 |tee -a $CLUSTER_LOG
#
#rosa create account-roles --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
#
INSTALL_ARN=`rosa list account-roles|grep Install|grep HCP|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep HCP|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep HCP|awk '{print $3}'`
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "OIDC_ID " $OIDC_ID 2>&1 >> $CLUSTER_LOG
#
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG 
SUBNET_IDS=$PRIV_SUB_2a","$PUBLIC_SUB_2a
#
rosa create cluster --cluster-name=$CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 |tee -a $CLUSTER_LOG
#
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
#
rosa create admin --cluster=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
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
# Single AZ Private                                        #
############################################################
Single-AZ-Priv()
{
NOW=`date +"%y%m%d%H%M"`
CLUSTER_NAME=gm-$NOW
INSTALL_DIR=$(pwd)
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
#
PREFIX=TestManagedHCP
#
aws configure 
echo " Installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ (Private) ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
echo "#"
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
#rosa init 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#echo "rosa init ... done! going to create the VPC ..." 2>&1 |tee -a $CLUSTER_LOG
#
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
echo "Creating the VPC"  2>&1 >> $CLUSTER_LOG
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone $AWS_REGIONa --query Subnet.SubnetId --output text`
#echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#echo "stacazzodesubnet " $PRIV_SUB_2a","$PUBLIC_SUB_2a 2>&1 >> $CLUSTER_LOG
#IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
#aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
#aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
#PUBLIC_RT_ID=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
#aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
#aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
#aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
#EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
#NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
#echo "Waiting for NAT GW to warm up (2min)" 2>&1 |tee -a $CLUSTER_LOG
#sleep 120
#aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
PRIVATE_RT_ID1=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
#aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! going to create account and operator roles, then your HCP Cluster ..." 2>&1 |tee -a $CLUSTER_LOG
#
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
#
INSTALL_ARN=`rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}'`
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "OIDC_ID " $OIDC_ID 2>&1 >> $CLUSTER_LOG
#
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG 
SUBNET_IDS=$PRIV_SUB_2a","$PUBLIC_SUB_2a
#
rosa create cluster --private --cluster-name=$CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --subnet-ids=$PRIV_SUB_2a -m auto -y 2>&1 |tee -a $CLUSTER_LOG
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
PREFIX=TestManagedHCP
#
aws configure
echo " Installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ (Private) ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
echo "#"
###aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
###aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
###rosa init 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#echo "rosa init ... done! going to create the VPC ..." 2>&1 |tee -a $CLUSTER_LOG
#
echo "Creating the VPC"  2>&1 >> $CLUSTER_LOG
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
PUBLIC_SUB_2b=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.16.0/20 --availability-zone ${AWS_REGION}b --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources $PUBLIC_SUB_2b --tags Key=Name,Value=$CLUSTER_NAME-public
PUBLIC_SUB_2c=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.32.0/20 --availability-zone ${AWS_REGION}c --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources $PUBLIC_SUB_2c --tags Key=Name,Value=$CLUSTER_NAME-public
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
PRIV_SUB_2b=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.144.0/20 --availability-zone ${AWS_REGION}b --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources  $PRIV_SUB_2b --tags Key=Name,Value=$CLUSTER_NAME-private
PRIV_SUB_2c=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.160.0/20 --availability-zone ${AWS_REGION}c --query Subnet.SubnetId --output text`
aws ec2 create-tags --resources  $PRIV_SUB_2c --tags Key=Name,Value=$CLUSTER_NAME-private
SUBNET_IDS=$PRIV_SUB_2a","$PRIV_SUB_2b","$PRIV_SUB_2c","$PUBLIC_SUB_2a","$PUBLIC_SUB_2b","$PUBLIC_SUB_2c
IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
PUBLIC_RT_ID=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
#aws ec2 describe-route-tables --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2b --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2c --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
echo "EIP_ADDRESS " $EIP_ADDRESS 2>&1 >> $CLUSTER_LOG
NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
#
echo "Waiting for NAT GW to warm up \(2min\)" 2>&1 >> $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
PRIVATE_RT_ID1=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2a-rtb
PRIVATE_RT_ID2=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PRIVATE_RT_ID2 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2b --route-table-id $PRIVATE_RT_ID2 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID2 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2b-rtb
PRIVATE_RT_ID3=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
aws ec2 create-route --route-table-id $PRIVATE_RT_ID3 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2c --route-table-id $PRIVATE_RT_ID3 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID3 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2c-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! going to create account and operator roles, then your HCP Cluster ..." 2>&1 |tee -a $CLUSTER_LOG
#
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
INSTALL_ARN=`rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}'`
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "OIDC_ID " $OIDC_ID 2>&1 >> $CLUSTER_LOG
#
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG
#
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --multi-az --region $AWS_REGION --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> $CLUSTER_LOG
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
PREFIX=TestManagedHCP
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
OIDC_ID=`rosa list oidc-provider -o json|grep arn| awk -F/ '{print $3}'|cut -c 1-32`
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "# Start deleting ROSA HCP cluster $CLUSTER_NAME, VPC, roles, etc. " 2>&1 |tee -a $CLUSTER_LOG
echo "# Please note: you might get a warning while deleting the previously created VPC as you can not delete default resources \(eg. default SG, RT, etc.\)" 2>&1 |tee -a $CLUSTER_LOG
echo "# Further details can be found in $CLUSTER_LOG LOG file" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
rosa delete cluster -c $CLUSTER_NAME --yes 2>&1 >> $CLUSTER_LOG
rosa logs uninstall -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
rosa delete operator-roles --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
rosa delete oidc-provider --oidc-config-id $OIDC_ID --mode auto --yes 2>&1 >> $CLUSTER_LOG
#
VPC_ID=`cat $CLUSTER_LOG |grep VPC_ID_VALUE|awk '{print $2}'`
#
   while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways | jq -r '.NatGateways[].NatGatewayId') 2>&1 >> $CLUSTER_LOG
# NOTE: waiting for the NAT-GW to die - se non crepa non andiamo da nessuna parte
echo "waiting for the NAT-GW to die " 2>&1 |tee -a $CLUSTER_LOG
sleep 100
#
    while read -r sg ; do aws ec2 delete-security-group --group-id $sg ; done < <(aws ec2 describe-security-groups --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.SecurityGroups[].GroupId') 2>&1 >> $CLUSTER_LOG
    while read -r acl ; do  aws ec2 delete-network-acl --network-acl-id $acl; done < <(aws ec2 describe-network-acls --filters 'Name=vpc-id,Values='$VPC_ID| jq -r '.NetworkAcls[].NetworkAclId') 2>&1 >> $CLUSTER_LOG
    while read -r subnet_id ; do aws ec2 delete-subnet --subnet-id "$subnet_id"; done < <(aws ec2 describe-subnets --filters 'Name=vpc-id,Values='$VPC_ID | jq -r '.Subnets[].SubnetId') 2>&1 >> $CLUSTER_LOG
   while read -r rt_id ; do aws ec2 delete-route-table --route-table-id $rt_id ;done < <(aws ec2 describe-route-tables --filters 'Name=vpc-id,Values='$VPC_ID |jq -r '.RouteTables[].RouteTableId') 2>&1 >> $CLUSTER_LOG
   while read -r ig_id ; do aws ec2 detach-internet-gateway --internet-gateway-id $ig_id --vpc-id $VPC_ID; done < <(aws ec2 describe-internet-gateways --filters 'Name=attachment.vpc-id,Values='$VPC_ID | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> $CLUSTER_LOG
   while read -r ig_id ; do aws ec2 delete-internet-gateway --internet-gateway-id $ig_id; done < <(aws ec2 describe-internet-gateways | jq -r ".InternetGateways[].InternetGatewayId") 2>&1 >> $CLUSTER_LOG
   while read -r address_id ; do aws ec2 release-address --allocation-id $address_id; done < <(aws ec2 describe-addresses | jq -r '.Addresses[].AllocationId') 2>&1 >> $CLUSTER_LOG
#
aws ec2 delete-vpc --vpc-id=$VPC_ID 2>&1 >> $CLUSTER_LOG
#
rosa delete account-roles --mode auto --prefix $PREFIX --yes 2>&1 |tee -a $CLUSTER_LOG
#rosa init --delete --yes 2>&1 |tee -a $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "done! " 2>&1 |tee -a $CLUSTER_LOG
echo " Cluster " $CLUSTER_NAME " has been deleted !" 2>&1 |tee -a $CLUSTER_LOG
echo " Now you can find the old $CLUSTER_LOG LOG file in /tmp folder" 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
mv $CLUSTER_LOG /tmp
}
#
#
echo "Welcome to the ROSA HCP installation menu"
PS3='Please enter your choice: '
options=("Single-AZ " "Single-AZ-Priv " "Multi-AZ " "Delete_HCP " "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Single-AZ ")
          SingleAZ
		break
            ;;
        "Single-AZ-Priv ")
          Single-AZ-Priv
		break
            ;;
        "Multi-AZ ")
            MultiAZ
		break
            ;;
        "Delete_HCP ")
            Delete_HCP
		break
            ;;
        "Quit")
            break
            ;;
        *) echo "invalid option $REPLY"
	    ;;
    esac
done
