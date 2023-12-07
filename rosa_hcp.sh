#!/usr/bin/env bash
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
# It will look for the $CLUSTER_LOG file in order to be able to identify some resources (i.e. VPC_Id, Subnets, ...).
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
#
#set -xe
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
BILLING_ID=`rosa whoami|grep "AWS Account ID:"|awk '{print $4}'`
#
PREFIX=TestManagedHCP
#
aws configure 
echo " Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
echo "#"
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
#rosa verify permissions 2>&1 >> $CLUSTER_LOG
#rosa verify quota --region=$AWS_REGION
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#
#
echo "Creating the VPC"  2>&1 |tee -a $CLUSTER_LOG
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
#
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
#
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
echo "Creating the IGW: " $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW 2>&1 >> $CLUSTER_LOG
#
PUBLIC_RT_ID=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> $CLUSTER_LOG
#aws ec2 describe-route-tables --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb 2>&1 >> $CLUSTER_LOG
#
EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
echo "Waiting for NGW to warm up (2min)" 2>&1 |tee -a $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
#
PRIVATE_RT_ID1=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! " 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
#
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
echo "Creating account-roles" 2>&1 >> $CLUSTER_LOG
#
INSTALL_ARN=`rosa list account-roles|grep Install|grep HCP|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep HCP|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep HCP|awk '{print $3}'`
echo "Creating the OICD config" 2>&1 >> $CLUSTER_LOG
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "OIDC_ID " $OIDC_ID 2>&1 >> $CLUSTER_LOG
#
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG 
echo "Creating operator-roles" 2>&1 >> $CLUSTER_LOG
SUBNET_IDS=$PRIV_SUB_2a","$PUBLIC_SUB_2a
#
echo "Creating ROSA HCP cluster" 2>&1 >> $CLUSTER_LOG
echo "" 2>&1 >> $CLUSTER_LOG
rosa create cluster --cluster-name=$CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 |tee -a $CLUSTER_LOG
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 >> $CLUSTER_LOG
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "Creating the cluster-admin user" 2>&1 >> $CLUSTER_LOG
rosa create admin --cluster=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Done!!! " 2>&1 |tee -a $CLUSTER_LOG
echo " Cluster " $CLUSTER_NAME " Has been installed and is up and running" 2>&1 |tee -a $CLUSTER_LOG
echo " Please check the $CLUSTER_LOG LOG file for additional information " 2>&1 |tee -a $CLUSTER_LOG
sleep 1
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
}
#
############################################################
# Single AZ Private                                        #
############################################################
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
BILLING_ID=`rosa whoami|grep "AWS Account ID:"|awk '{print $4}'`
#
PREFIX=TestManagedHCP
#
aws configure
echo " Installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ (Private) ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
echo "#"
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#
#
#
echo "Creating the VPC"  2>&1 |tee -a $CLUSTER_LOG
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
#
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
#PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
#echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 >> $CLUSTER_LOG
#aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
#
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
#IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
#echo "Creating the IGW: " $IGW 2>&1 >> $CLUSTER_LOG
#aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW 2>&1 >> $CLUSTER_LOG
#aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW 2>&1 >> $CLUSTER_LOG
#
#PUBLIC_RT_ID=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
#echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
#aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> $CLUSTER_LOG
##aws ec2 describe-route-tables --route-table-id $PUBLIC_RT_ID
#aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
#aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb 2>&1 >> $CLUSTER_LOG
#
#EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
#NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
#echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
#echo "Waiting for NGW to warm up (2min)" 2>&1 |tee -a $CLUSTER_LOG
#sleep 120
#aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
#
PRIVATE_RT_ID1=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
#aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! " 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
#
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
echo "Creating account-roles" 2>&1 >> $CLUSTER_LOG

#
INSTALL_ARN=`rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}'`
echo "Creating the OICD config" 2>&1 >> $CLUSTER_LOG
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "OIDC_ID " $OIDC_ID 2>&1 >> $CLUSTER_LOG
#
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG
echo "Creating operator-roles" 2>&1 >> $CLUSTER_LOG
SUBNET_IDS=$PRIV_SUB_2a
#
echo "Creating ROSA HCP cluster" 2>&1 >> $CLUSTER_LOG
rosa create cluster --private --cluster-name=$CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 |tee -a $CLUSTER_LOG
#
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 >> $CLUSTER_LOG
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "Creating the cluster-admin user" 2>&1 >> $CLUSTER_LOG
rosa create admin --cluster=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Done!!! " 2>&1 |tee -a $CLUSTER_LOG
echo " Cluster " $CLUSTER_NAME " Has been installed and is up and running" 2>&1 |tee -a $CLUSTER_LOG
echo " Please check the $CLUSTER_LOG LOG file for additional information " 2>&1 |tee -a $CLUSTER_LOG
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
BILLING_ID=`rosa whoami|grep "AWS Account ID:"|awk '{print $4}'`
#
PREFIX=TestManagedHCP
#
aws configure
echo " Installing ROSA HCP cluster $CLUSTER_NAME in a Multi-AZ ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
echo "#"
aws sts get-caller-identity 2>&1 >> $CLUSTER_LOG
aws iam get-role --role-name "AWSServiceRoleForElasticLoadBalancing" 2>&1 >> $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
#
echo "Creating the VPC"  2>&1 >> $CLUSTER_LOG
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
#
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Public Subnet 2a: " $PUBLIC_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public 2>&1 >> $CLUSTER_LOG
#
PUBLIC_SUB_2b=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.16.0/20 --availability-zone ${AWS_REGION}b --query Subnet.SubnetId --output text`
echo "Creating the Public Subnet 2b: " $PUBLIC_SUB_2b 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2b --tags Key=Name,Value=$CLUSTER_NAME-public 2>&1 >> $CLUSTER_LOG
#
PUBLIC_SUB_2c=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.32.0/20 --availability-zone ${AWS_REGION}c --query Subnet.SubnetId --output text`
echo "Creating the Public Subnet 2c: " $PUBLIC_SUB_2c 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2c --tags Key=Name,Value=$CLUSTER_NAME-public 2>&1 >> $CLUSTER_LOG
#
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet 2a: " $PRIV_SUB_2a 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
PRIV_SUB_2b=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.144.0/20 --availability-zone ${AWS_REGION}b --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet 2b: " $PRIV_SUB_2b 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2b --tags Key=Name,Value=$CLUSTER_NAME-private
#
PRIV_SUB_2c=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.160.0/20 --availability-zone ${AWS_REGION}c --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet 2c: " $PRIV_SUB_2c 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2c --tags Key=Name,Value=$CLUSTER_NAME-private
#
SUBNET_IDS=$PRIV_SUB_2a","$PRIV_SUB_2b","$PRIV_SUB_2c","$PUBLIC_SUB_2a","$PUBLIC_SUB_2b","$PUBLIC_SUB_2c
#
IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
echo "Creating the IGW: " $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
#
PUBLIC_RT_ID=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW
#aws ec2 describe-route-tables --route-table-id $PUBLIC_RT_ID
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2b --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2c --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
#
EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
echo "EIP_ADDRESS " $EIP_ADDRESS 2>&1 >> $CLUSTER_LOG
NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
#
echo "Waiting for NGW to warm up \(2min\)" 2>&1 >> $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
#
PRIVATE_RT_ID1=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2a-rtb 2>&1 >> $CLUSTER_LOG
#
PRIVATE_RT_ID2=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Private Route Table: " $PRIVATE_RT_ID2 2>&1 >> $CLUSTER_LOG
aws ec2 create-route --route-table-id $PRIVATE_RT_ID2 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2b --route-table-id $PRIVATE_RT_ID2 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID2 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2b-rtb
#
PRIVATE_RT_ID3=`aws ec2 create-route-table --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Private Route Table: " $PRIVATE_RT_ID3 2>&1 >> $CLUSTER_LOG
aws ec2 create-route --route-table-id $PRIVATE_RT_ID3 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2c --route-table-id $PRIVATE_RT_ID3 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID3 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2c-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! " 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
#
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
echo "Creating account-roles" 2>&1 >> $CLUSTER_LOG
#
INSTALL_ARN=`rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}'`
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "OIDC_ID " $OIDC_ID 2>&1 >> $CLUSTER_LOG
#
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG
echo "Creating operator-roles" 2>&1 >> $CLUSTER_LOG
#
echo "Creating ROSA HCP cluster" 2>&1 >> $CLUSTER_LOG
echo "" 2>&1 >> $CLUSTER_LOG
rosa create cluster -c $CLUSTER_NAME --sts --hosted-cp --multi-az --region ${AWS_REGION} --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> $CLUSTER_LOG
#
echo "Appending rosa installation logs to ${CLUSTER_LOG} " 2>&1 >> $CLUSTER_LOG
rosa logs install -c $CLUSTER_NAME --watch 2>&1 >> $CLUSTER_LOG
#
rosa describe cluster -c $CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "Creating the cluster-admin user" 2>&1 >> $CLUSTER_LOG
rosa create admin --cluster=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Done!!! " 2>&1 |tee -a $CLUSTER_LOG
echo " Cluster " $CLUSTER_NAME " Has been installed and is up and running" 2>&1 |tee -a $CLUSTER_LOG
echo " Please check the $CLUSTER_LOG LOG file for aditional information " 2>&1 |tee -a $CLUSTER_LOG
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
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "# Start deleting ROSA HCP cluster $CLUSTER_NAME, VPC, roles, etc. " 2>&1 |tee -a $CLUSTER_LOG
echo "# Please note: you might get a warning while deleting the previously created VPC as you can not delete default resources \(eg. default SG, RT, etc.\)" 2>&1 |tee -a $CLUSTER_LOG
echo "# Further details can be found in $CLUSTER_LOG LOG file" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Cluster deleted !" 2>&1 |tee -a $CLUSTER_LOG
echo "operator-roles deleted !" 2>&1 |tee -a $CLUSTER_LOG
echo "oidc-provider deleted !" 2>&1 |tee -a $CLUSTER_LOG
#
VPC_ID=`cat $CLUSTER_LOG |grep VPC_ID_VALUE|awk '{print $2}'`
#
   while read -r instance_id ; do aws ec2 delete-nat-gateway --nat-gateway-id $instance_id; done < <(aws ec2 describe-nat-gateways | jq -r '.NatGateways[].NatGatewayId') 2>&1 >> $CLUSTER_LOG
# NOTE: waiting for the NAT-GW to die - se non crepa non andiamo da nessuna parte
echo "waiting for the NAT-GW to die " 2>&1 |tee -a $CLUSTER_LOG
sleep 100
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
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "done! " 2>&1 |tee -a $CLUSTER_LOG
echo " Cluster " $CLUSTER_NAME " has been deleted !" 2>&1 |tee -a $CLUSTER_LOG
echo " The old LOG file ($CLUSTER_LOG) in is now moved to /tmp folder" 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
mv $CLUSTER_LOG /tmp
}
#
mainmenu() {
    echo -ne "
Welcome to the ROSA HCP installation (Main Menu)

1) Single-AZ
2) Single-AZ-Priv
3) Multi-AZ
4) Delete HCP
0) Exit

Please enter your choice: "
    read -r ans
    case $ans in
    1)
        SingleAZ
        mainmenu
        ;;
    2)
        Single-AZ-Priv
        mainmenu
        ;;
    3)
        MultiAZ
        mainmenu
        ;;
    4)
        Delete_HCP
        mainmenu
        ;;
    0)
        fine
        ;;
    *)
        errore
        mainmenu
        ;;
    esac
}

fine() {
    echo "Thank you for using this script, if you would like to leave your feedback (very welcome) please drop an email to gmollo@redhat.com"
    exit 0
}

errore() {
    echo "Wrong option."
    sleep 1
    clear
    mainmenu
}
mainmenu
