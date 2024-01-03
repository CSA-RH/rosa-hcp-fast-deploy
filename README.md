# AWS ROSA Cluster with hosted control planes (HCP)
The idea behind this shell script was to automatically create the necessary environment and deploy a ROSA with **HCP** cluster in a few minutes, using the CLI.<br />
The initial setup includes the creation and configuration of the
   - Virtual Private Cloud (VPC), including Subnets, IGW, NGW, configuring Routes, etc.
   - Account-wide IAM roles [^1] and policies
   - Cluster-specific Operator roles [^1] and policies
   - OIDC identity provider configuration

The entire process to create/delete a ROSA with **HCP** cluster and all its resources will take approximately 15 minutes. <br /> 

## Script prerequisites
- An AWS account (or an RHDP "AWS Blank Environment")
- Your AWS Access Key and your AWS Secret Access Key
- ROSA CLI [^2] and AWS CLI already installed and updated (the script will help automate this part too)

> [!IMPORTANT]
> Enable the ROSA service in the AWS Console and link the AWS and Red Hat accounts by following this procedure:
Sign in to your AWS account, from to the AWS Console look for the “Red Hat OpenShift Service on AWS (ROSA)” and click the “Get started” button (1), then locate and enable the “ROSA with HCP” service (2);
ensure Service Quotas meet the requirements and Elastic Load Balancing (ELB) service-linked role already exists (3); click the “Continue to Red Hat” button (4); complete the connection by clicking the “Connect accounts” button (5).

![image](https://github.com/CSA-RH/aws-rosa-cluster-with-hosted-control-planes/assets/148223511/7852a5bf-2b31-4673-8f58-1efd841a7b8d)

Once done your AWS and Red Hat account are linked and you can start witht the installation process.

[^1]: PREFIX=TestManagedHCP
[^2]: If you get an error like this: "_E: Failed to create cluster: Version 'X.Y.Z' is below minimum supported for Hosted Control Plane_", you'll probably have to update the ROSA CLI in order to be able to create the latest cluster version available.


# Create your ROSA with HCP cluster
1. Clone this repo
```
$ git clone [https://github.com/CSA-RH/fast-rosa-hcp-depoly](https://github.com/CSA-RH/fast-rosa-hcp-depoly)

Cloning into 'fast-rosa-hcp-depoly'...
remote: Enumerating objects: 118, done.<br />
remote: Counting objects: 100% (118/118), done.<br />
remote: Compressing objects: 100% (112/112), done.<br />
remote: Total 118 (delta 43), reused 11 (delta 5), pack-reused 0<br />
Receiving objects: 100% (118/118), 45.89 KiB | 1.64 MiB/s, done.<br />
Resolving deltas: 100% (43/43), done.<br />
```
2. Go to path:
```
$ cd fast-rosa-hcp-depoly/
```

3. Add execution permissions
```
$ chmod +x rosa_hcp.sh 
```

4. Run the script and then make your choise
```
$ ./rosa_hcp.sh 

*********************************************

*         ROSA HCP Installation Menu        *

*********************************************
** 1) HCP Public (Single-AZ) 
** 2) HCP Private (Single-AZ) 
** 3) HCP Public (Multi-AZ) 
** 4) Delete HCP 
** 5) AWS_CLI 
** 6) ROSA_CLI 
*********************************************
Please enter a menu option and enter or x to exit.
```
The first 3 options require AWS access keys to be entered or updated
```
Example:
Option 1 Picked - Installing ROSA with HCP Public (Single-AZ)
AWS Access Key ID [****************QX5V]: 
AWS Secret Access Key [****************eh4c]: 
Default region name [us-east-2]: 
Default output format [json]:
#
#
Start installing ROSA HCP cluster gm-2312111104 in a Single-AZ ...
#
#
Creating the VPC
Creating the Public Subnet:  subnet-074ab3b7b01a59a99
Creating the Private Subnet:  subnet-04fff1d5c1917d7e3
Creating the IGW:  igw-0545882580fcc129e
Creating the Public Route Table:  rtb-050ad245b2152e67f
Creating the NGW:  nat-08c847f619caed7c5
...
...

```
> [!NOTE]
> When creating the cluster, the **aws configure** command is called first:
> please make sure you have both the **AWS Access Key** and the **AWS Secret Access Key** at hand to be able to start the process
> Also the **aws configure** command will ask for the default AWS Region: the one specified there will be used as the target destination during the installation process.

The AWS CLI will now remember your inputs, no further action is required until the ROSA with **HCP** cluster installation is complete.

#### A few notes around resources, deployment model, etc.
ROSA with HCP clusters can be deployed in different versions (e.g. Public, Private, Single-AZ, Multi-AZ), the number and type of resources created by this script will vary depending on what you choose.
Here is an on overview of the [default cluster specifications](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html#rosa-sts-overview-of-the-default-cluster-specifications_rosa-hcp-sts-creating-a-cluster-quickly).

Where public Subnets are expected, the script will create a minimal configuration with 1x NAT Gateway (NGW) in one single AZ, 1x Internet Gateway (IGW) to allow the egress (NAT) traffic to the Internet.
In the case of a private ROSA with **HCP** cluster it is assumed that it will be reachable through a VPN or a Direct Connect service, therefore the script does not include the creation of any Public Subnet.

Further information: <br />
Single-AZ = 2 worker nodes will be created within the same subnet<br />
Multi-AZ = 3 worker nodes will be created, one for each AZ <br />

#### Installation Log File 
During the implementation phase a LOG file is created in the same folder as the shell script, so you can follow all the intermediate steps.
It is mandatory to keep this file in its original location to be able to automatically delete the cluster when done.

Here is an example:
```
$ tail -f gm-2310161718.log 

Start installing ROSA HCP cluster gm-2312111104 in a Single-AZ ...
...
Going to create account and operator roles ...
INFO: Creating hosted CP account roles using 'arn:aws:iam::099744512031:user/gmollo@redhat.com-cj2hc-admin'
INFO: Created role 'TestManagedHCP-HCP-ROSA-Installer-Role' with ARN 'arn:aws:iam::099744512031:role/TestManagedHCP-HCP-ROSA-Installer-Role'
INFO: Created role 'TestManagedHCP-HCP-ROSA-Support-Role' with ARN 'arn:aws:iam::099744512031:role/TestManagedHCP-HCP-ROSA-Support-Role'
INFO: Created role 'TestManagedHCP-HCP-ROSA-Worker-Role' with ARN 'arn:aws:iam::099744512031:role/TestManagedHCP-HCP-ROSA-Worker-Role'
Creating the OICD config
...
...
```
> [!NOTE]
> After a successful deployment a **cluster-admin** account is added to your cluster whose password will be recorded in the LOG file, feel free to change this to fit your security needs.

```
INFO: Admin account has been added to cluster 'gm-2310161718'.
INFO: Please securely store this generated password. If you lose this password you can delete and recreate the cluster admin user.
INFO: To login, run the following command:
Example:
   oc login https://api.gm-2310161718.wxyz.p9.openshiftapps.com:443 --username cluster-admin --password p5BiM-tbPPa-p5BiM-tbPPa
```

# Delete your cluster
Once you are done, feel free to destroy your ROSA **HCP** cluster by launching the same shell script and choosing option 4) this time. 
```
$ ./rosa_hcp.sh 

Welcome to the ROSA HCP installation - Main Menu

1) HCP-Public (Single-AZ)
2) HCP-Private (Single-AZ)
3) HCP-Public (Multi-AZ)
4) Delete HCP
5) Install/Update AWS_CLI
6) Install/Update ROSA_CLI
0) Exit

Please enter your choice: 4

#
# Start deleting ROSA HCP cluster , VPC, roles, etc. 
# Further details can be found in /home/gmollo/tools/cluster/svil/aws-rosa-cluster-with-hosted-control-planes/.log LOG file
#
Cluster deletion in progress 
INFO: To watch your cluster uninstallation logs, run 'rosa logs uninstall -c gm-2312110919 --watch'
operator-roles deleted !
oidc-provider deleted !
Start deleting VPC vpc-0841c3b77ebad7baf 
waiting for the NAT-GW to die 
...
```
It takes approximately 15 minutes to delete your cluster, including its VPCs, IAM roles, OIDCs, etc.<br />
Please note that after the deletion process is complete the LOG file will be moved from its current location to **/tmp**.

# Wrap up
This script will make use of specific commands, options, and variables to successfully install the cluster for you in a few minutes but **feel free to make changes to suit your needs** as you may want to implement a specific cluster version, change the target $AWS_REGION, change the $PREFIX option; etc.

