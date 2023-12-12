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
set -u
#RETVAL=$?
#
############################################################
# HCP Public Cluster                                       #
############################################################
HCP-Public()
{
NOW=`date +"%y%m%d%H%M"`
CLUSTER_NAME=gm-$NOW
INSTALL_DIR=$(pwd)
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=`rosa whoami|grep "AWS Account ID:"|awk '{print $4}'`
PREFIX=TestManagedHCP
#
aws configure 
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
echo "#"
#
SingleAZ-VPC
#
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
INSTALL_ARN=`rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}'`
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a $CLUSTER_LOG
echo "OIDC_ID " $OIDC_ID 2>&1 2>&1 >> $CLUSTER_LOG
echo "Creating operator-roles" 2>&1 >> $CLUSTER_LOG
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG 
SUBNET_IDS=$PRIV_SUB_2a","$PUBLIC_SUB_2a
#
echo "Creating ROSA HCP cluster " 2>&1 |tee -a $CLUSTER_LOG
rosa create cluster --cluster-name=$CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> $CLUSTER_LOG
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
############################################################
# HCP Private Cluster                                      #
############################################################
#
HCP-Private()
{
NOW=`date +"%y%m%d%H%M"`
CLUSTER_NAME=gm-$NOW
INSTALL_DIR=$(pwd)
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
touch $CLUSTER_LOG
BILLING_ID=`rosa whoami|grep "AWS Account ID:"|awk '{print $4}'`
PREFIX=TestManagedHCP
#
aws configure
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Single-AZ (Private) ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
#
SingleAZ-VPC-Priv
#
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
INSTALL_ARN=`rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}'`
OIDC_ID=$(rosa create oidc-config --mode auto --managed --yes -o json | jq -r '.id')
echo "Creating the OIDC config" $OIDC_ID 2>&1 |tee -a $CLUSTER_LOG
echo "OIDC_ID " $OIDC_ID 2>&1 2>&1 >> $CLUSTER_LOG
echo "Creating operator-roles" 2>&1 >> $CLUSTER_LOG
rosa create operator-roles --hosted-cp --prefix $PREFIX --oidc-config-id $OIDC_ID --installer-role-arn $INSTALL_ARN -m auto -y 2>&1 >> $CLUSTER_LOG
SUBNET_IDS=$PRIV_SUB_2a
#
echo "Creating ROSA HCP cluster " 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 >> $CLUSTER_LOG
rosa create cluster --private --cluster-name=$CLUSTER_NAME --sts --hosted-cp --role-arn $INSTALL_ARN --support-role-arn $SUPPORT_ARN --worker-iam-role $WORKER_ARN --operator-roles-prefix $PREFIX --oidc-config-id $OIDC_ID --billing-account $BILLING_ID --subnet-ids=$SUBNET_IDS -m auto -y 2>&1 >> $CLUSTER_LOG
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
echo "#"
echo "#"
echo "Start installing ROSA HCP cluster $CLUSTER_NAME in a Multi-AZ ..." 2>&1 |tee -a $CLUSTER_LOG
AWS_REGION=`cat ~/.aws/config|grep region|awk '{print $3}'`
echo "#"
#
MultiAZ-VPC
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "Going to create account and operator roles ..." 2>&1 |tee -a $CLUSTER_LOG
rosa create account-roles --hosted-cp --force-policy-creation --prefix $PREFIX -m auto -y 2>&1 >> $CLUSTER_LOG
INSTALL_ARN=`rosa list account-roles|grep Install|grep $PREFIX|awk '{print $3}'`
WORKER_ARN=`rosa list account-roles|grep -i worker|grep $PREFIX|awk '{print $3}'`
SUPPORT_ARN=`rosa list account-roles|grep -i support|grep $PREFIX|awk '{print $3}'`
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
VPC_ID=`cat $CLUSTER_LOG |grep VPC_ID_VALUE|awk '{print $2}'`
echo "Start deleting VPC ${VPC_ID} " 2>&1 |tee -a $CLUSTER_LOG
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
rosa delete account-roles --mode auto --prefix $PREFIX --yes 2>&1 >> $CLUSTER_LOG
echo "account-roles deleted !" 2>&1 |tee -a $CLUSTER_LOG
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "done! " 2>&1 |tee -a $CLUSTER_LOG
echo "Cluster " $CLUSTER_NAME " has been deleted !" 2>&1 |tee -a $CLUSTER_LOG
echo "The old LOG file ${CLUSTER_LOG} in is now moved to /tmp folder" 2>&1 |tee -a $CLUSTER_LOG
echo " " 2>&1 |tee -a $CLUSTER_LOG
mv $CLUSTER_LOG /tmp
Countdown
Fine
}
#
mainmenu() {
    clear
    echo -ne "
Welcome to the ROSA HCP installation - Main Menu

1) HCP-Public (Single-AZ)
2) HCP-Private (Single-AZ)
3) HCP-Public (Multi-AZ)
4) Delete HCP
5) Install/Update AWS_CLI
6) Install/Update ROSA_CLI
0) Exit

Please enter your choice: "
    read -r ans
    case $ans in
    1)
        HCP-Public
        mainmenu
        ;;
    2)
        HCP-Private
        mainmenu
        ;;
    3)
        HCP-Public-MultiAZ
        mainmenu
        ;;
    4)
        Delete_HCP
        mainmenu
        ;;
    5)
        Install/Update AWS_CLI
        AWS_CLI
        mainmenu
        ;;
    6)
        Install/Update ROSA_CLI
        ROSA_CLI
        mainmenu
        ;;
    0)
        Fine
        ;;
    *)
        Errore
        mainmenu
        ;;
    esac
}

Fine() {
    echo "Thank you for using this script, I would very much appreciate if you could leave your feedback. In this case please drop an email to gmollo@redhat.com"
    exit 0
}

Errore() {
    echo "Wrong option."
    clear
}

Countdown() {
 hour=0
 min=0
 sec=30
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
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a $CLUSTER_LOG
#
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 |tee -a $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Public Subnet: " $PUBLIC_SUB_2a 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public
#
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
echo "Creating the IGW: " $IGW 2>&1 |tee -a $CLUSTER_LOG
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW 2>&1 >> $CLUSTER_LOG
#
PUBLIC_RT_ID=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb 2>&1 >> $CLUSTER_LOG
#
EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 |tee -a $CLUSTER_LOG
echo "Waiting for NGW to warm up " 2>&1 |tee -a $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
#
PRIVATE_RT_ID1=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
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
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a $CLUSTER_LOG
#
# 
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet: " $PRIV_SUB_2a 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
PRIVATE_RT_ID1=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
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
VPC_ID_VALUE=`aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query Vpc.VpcId --output text`
echo "Creating the VPC " $VPC_ID_VALUE 2>&1 |tee -a $CLUSTER_LOG
# 
echo "VPC_ID_VALUE " $VPC_ID_VALUE 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $VPC_ID_VALUE --tags Key=Name,Value=$CLUSTER_NAME 2>&1 >> $CLUSTER_LOG
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID_VALUE --enable-dns-hostnames
#
PUBLIC_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.0.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Public Subnet 2a: " $PUBLIC_SUB_2a 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-public 2>&1 >> $CLUSTER_LOG
#
PUBLIC_SUB_2b=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.16.0/20 --availability-zone ${AWS_REGION}b --query Subnet.SubnetId --output text`
echo "Creating the Public Subnet 2b: " $PUBLIC_SUB_2b 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2b --tags Key=Name,Value=$CLUSTER_NAME-public 2>&1 >> $CLUSTER_LOG
#
PUBLIC_SUB_2c=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.32.0/20 --availability-zone ${AWS_REGION}c --query Subnet.SubnetId --output text`
echo "Creating the Public Subnet 2c: " $PUBLIC_SUB_2c 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_SUB_2c --tags Key=Name,Value=$CLUSTER_NAME-public 2>&1 >> $CLUSTER_LOG
#
PRIV_SUB_2a=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.128.0/20 --availability-zone ${AWS_REGION}a --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet 2a: " $PRIV_SUB_2a 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2a --tags Key=Name,Value=$CLUSTER_NAME-private
#
PRIV_SUB_2b=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.144.0/20 --availability-zone ${AWS_REGION}b --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet 2b: " $PRIV_SUB_2b 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2b --tags Key=Name,Value=$CLUSTER_NAME-private
#
PRIV_SUB_2c=`aws ec2 create-subnet --vpc-id $VPC_ID_VALUE --cidr-block 10.0.160.0/20 --availability-zone ${AWS_REGION}c --query Subnet.SubnetId --output text`
echo "Creating the Private Subnet 2c: " $PRIV_SUB_2c 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-tags --resources  $PRIV_SUB_2c --tags Key=Name,Value=$CLUSTER_NAME-private
#
IGW=`aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text`
echo "Creating the IGW: " $IGW 2>&1 |tee -a $CLUSTER_LOG
aws ec2 attach-internet-gateway --vpc-id $VPC_ID_VALUE --internet-gateway-id $IGW
aws ec2 create-tags --resources $IGW --tags Key=Name,Value=$CLUSTER_NAME-IGW
#
PUBLIC_RT_ID=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Public Route Table: " $PUBLIC_RT_ID 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-route --route-table-id $PUBLIC_RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2a --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2b --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PUBLIC_SUB_2c --route-table-id $PUBLIC_RT_ID 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PUBLIC_RT_ID --tags Key=Name,Value=$CLUSTER_NAME-public-rtb
#
EIP_ADDRESS=`aws ec2 allocate-address --domain vpc --query AllocationId --output text`
echo "EIP_ADDRESS " $EIP_ADDRESS 2>&1 >> $CLUSTER_LOG
NAT_GATEWAY_ID=`aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUB_2a --allocation-id $EIP_ADDRESS --query NatGateway.NatGatewayId --output text`
echo "Creating the NGW: " $NAT_GATEWAY_ID 2>&1 |tee -a $CLUSTER_LOG
echo "Waiting for NGW to warm up " 2>&1 |tee -a $CLUSTER_LOG
sleep 120
aws ec2 create-tags --resources $EIP_ADDRESS  --resources $NAT_GATEWAY_ID --tags Key=Name,Value=$CLUSTER_NAME-NAT-GW
#
PRIVATE_RT_ID1=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Private Route Table: " $PRIVATE_RT_ID1 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-route --route-table-id $PRIVATE_RT_ID1 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2a --route-table-id $PRIVATE_RT_ID1 2>&1 >> $CLUSTER_LOG 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID1 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2a-rtb 2>&1 >> $CLUSTER_LOG
#
PRIVATE_RT_ID2=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Private Route Table: " $PRIVATE_RT_ID2 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-route --route-table-id $PRIVATE_RT_ID2 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID 2>&1 >> $CLUSTER_LOG
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2b --route-table-id $PRIVATE_RT_ID2 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID2 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2b-rtb
#
PRIVATE_RT_ID3=`aws ec2 create-route-table --no-cli-pager --vpc-id $VPC_ID_VALUE --query RouteTable.RouteTableId --output text`
echo "Creating the Private Route Table: " $PRIVATE_RT_ID3 2>&1 |tee -a $CLUSTER_LOG
aws ec2 create-route --route-table-id $PRIVATE_RT_ID3 --destination-cidr-block 0.0.0.0/0 --gateway-id $NAT_GATEWAY_ID
aws ec2 associate-route-table --subnet-id $PRIV_SUB_2c --route-table-id $PRIVATE_RT_ID3 2>&1 >> $CLUSTER_LOG
aws ec2 create-tags --resources $PRIVATE_RT_ID3 $EIP_ADDRESS --tags Key=Name,Value=$CLUSTER_NAME-private2c-rtb
#
echo "#" 2>&1 |tee -a $CLUSTER_LOG
echo "VPC creation ... done! " 2>&1 |tee -a $CLUSTER_LOG
echo "#" 2>&1 |tee -a $CLUSTER_LOG
}

AWS_CLI() {
# Specify the installation directory
INSTALL_DIR="/usr/local/bin"

# Check if AWS CLI is installed
if command -v aws &> /dev/null
then
    # AWS CLI is installed, check for updates
    echo "AWS CLI is already installed. Checking for updates..."
    aws --version

    # Install the latest version using the AWS CLI update command
    echo "Updating AWS CLI..."
    aws --version | awk '{print $1}' | xargs -I {} aws configure set {} cli_auto_prompt=on
    aws --version | awk '{print $1}' | xargs -I {} aws configure set {} cli_auto_update=on
    aws --version | awk '{print $1}' | xargs -I {} aws configure set {} cli_auto_update_check_interval=1
    aws configure list | grep cli_auto_update_check_interval

    # Trigger the update
    aws --version

    echo "AWS CLI update completed."
else
    # AWS CLI is not installed, download and install
    echo "AWS CLI is not installed. Downloading and installing..."

###    # Specify the AWS CLI version you want to install
###    AWS_CLI_VERSION="latest"

    # Download and install AWS CLI
###    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-$AWS_CLI_VERSION.zip" -o "awscliv2.zip" # errato
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
###    unzip awscliv2.zip
    unzip -u awscliv2.zip
###    sudo ./aws/install -i $INSTALL_DIR
    sudo ./aws/install

    # Clean up
    rm -rf aws awscliv2.zip

    # Verify the installation
    echo "Verifying AWS CLI installation..."
    aws --version

    echo "AWS CLI installation completed."
fi
Countdown
}

ROSA_CLI() {
# Specify the installation directory
INSTALL_DIR="/usr/local/bin"

# Check if ROSA CLI is installed
if command -v rosa &> /dev/null
then
    # ROSA CLI is installed, check for updates
    echo "ROSA CLI is already installed. Checking for updates..."
#    rosa version
#
    # Download and install ROSA CLI
    curl https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz --output rosa-linux.tar.gz
    tar xvf rosa-linux.tar.gz
    sudo mv rosa /usr/local/bin/rosa

    # Clean up
    rm -rf rosa-linux.tar.gz

    # Trigger the update
    rosa version

    echo "ROSA CLI update completed."
else
  # ROSA CLI is not installed, download and install
    echo "ROSA CLI is not installed. Downloading and installing..."

    # Download and install ROSA CLI
    curl https://mirror.openshift.com/pub/openshift-v4/clients/rosa/latest/rosa-linux.tar.gz --output rosa-linux.tar.gz
    tar xvf rosa-linux.tar.gz
    sudo mv rosa /usr/local/bin/rosa

    # Clean up
    rm -rf rosa-linux.tar.gz

    # Verify the installation
    echo "Verifying ROSA CLI installation..."
    rosa version

    echo "ROSA CLI installation completed."
fi
Countdown
}

mainmenu
