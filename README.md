# AWS ROSA with hosted control planes cluster (HCP) fast deploy
A long time ago in a galaxy far, far away from ... our Terraform provider, I decided to create a mechanism to automate the deployment of one or more **AWS ROSA with hosted control planes (HCP)** cluster including its associated VPC.

This shell script is not intended to replace the [Red Hat official documentation](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html), but rather to practice installing your own test environments in such a short time: the entire process to install/delete a ROSA **HCP** cluster and all its resources will take approximately 15 minutes. <br /> 

Depending on your needs, you can easily create/delete a:

- ROSA Public Cluster, Single AZ
- ROSA Public Cluster, Multi Zone
- ROSA Private Cluster, Single AZ, with bastion host
- ROSA Public Cluster, Single AZ, with AWS Graviton (ARM CPU)
- TERRAFORM ROSA Public Cluster, Multi Zone

We have also added some "tools" to help you manage your CLI installation and AWS environment.

The initial setup includes the installation and configuration of the
   - Virtual Private Cloud (VPC), including Subnets, IGW, NGW, Routes, etc.
   - Account and Operator roles and policies
   - OIDC identity provider configuration



# Script prerequisites
- An AWS account with enough quota value to meet the minimum requirements for ROSA (100)
- Your AWS Access Key and your AWS Secret Access Key
- ROSA CLI and AWS CLI already installed and updated (the script will help automate this part too)

> [!IMPORTANT]
> Enable the ROSA service in the AWS Console and link the AWS and Red Hat accounts by following this procedure:
Sign in to your AWS account, from to the AWS Console look for the “Red Hat OpenShift Service on AWS (ROSA)” and click the “Get started” button (1), then locate and enable the “ROSA with HCP” service (2);
ensure Service Quotas meet the requirements and Elastic Load Balancing (ELB) service-linked role already exists (3); click the “Continue to Red Hat” button (4); complete the connection by clicking the “Connect accounts” button (5).

![image](https://github.com/CSA-RH/aws-rosa-cluster-with-hosted-control-planes/assets/148223511/7852a5bf-2b31-4673-8f58-1efd841a7b8d)

Once done your AWS and Red Hat account are linked and you can start witht the installation process.

# Create your ROSA with HCP cluster
1. Clone this repo
```
$ git clone https://github.com/CSA-RH/rosa-hcp-fast-deploy

```
2. Go to path:
```
$ cd rosa-hcp-fast-deploy/
```

3. Add execution permissions
```
$ chmod +x rosa_hcp.sh 
```

4. Run the script and then make your choise
```
$ ./rosa_hcp.sh 
```
<img width="477" alt="image" src="https://github.com/user-attachments/assets/3e5386fc-bb3a-4a93-9baf-eaadedc0444e">

The first 4 options require entering or updating your AWS access keys.<br /> 
In the following example you can see the installation of a Public ROSA HCP cluster, which corresponds to option "**1)   Installing ROSA with HCP Public (Single-AZ)**"

```
Example:
Option 1 Picked - Installing ROSA with HCP Public (Single-AZ)
AWS Access Key ID [****************QX5V]: 
AWS Secret Access Key [****************eh4c]: 
Default region name [us-east-2]: 
Default output format [json]:
#
#
Start installing ROSA HCP cluster gm-1234567890 in a Single-AZ ...
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
> please make sure you have both the **AWS Access Key** and the **AWS Secret Access Key** at hand to be able to start the process.

The AWS CLI will now remember your inputs, no further action is required until the ROSA **HCP** cluster installation is complete.

# Delete your cluster
Once done, feel free to destroy your ROSA HCP cluster by starting the same shell script, then choose option "**8)  TOOLS Menu**", then select option "**6)  Delete a specific HCP cluster**". 
Simply copy and paste the cluster name from the list and then hit **ENTER**.

<img width="747" alt="image" src="https://github.com/user-attachments/assets/dd8fbfcc-3208-4ddb-8a7f-349a9d5f9972">

```
Option 6 Picked - Delete a specific HCP cluster

Current HCP cluster list:
gm-2405191610
gm-2406250906
gm-2408291403


Please pick one or hit ENTER to quit: gm-2408291403

Let's get started with gm-2408291403 cluster

#
# Start deleting ROSA HCP cluster gm-2408291403, VPC, roles, etc. 
# Further details can be found in $CLUSTE_RLOG LOG file
#
Deleting the Jump Host (ID)  i-0568164055203945b
Deleting the key-pair named  gm-2408291403_KEY
Cluster  gm-2408291421 is a SingleAZ deployment with2of 2 nodes within the AWS VPC vpc-0f719fd7e4ae99c40
Removing the NGW since it takes a lot of time to get deleted
Operator roles prefix:  gm-2408291403
Running "rosa delete cluster"
Running "rosa logs unistall"
...
```
It takes approximately 15 minutes to delete your cluster, including its VPCs, IAM roles, OIDCs, etc.<br />

# Terraform
It is possible to create/destroy a ROSA HCP by using a Terraform cluster template that is configured with the default cluster options. <br />
The default ROSA version for Terraform cluster is 4.17.9, of course you can change it to a more up-to-date version in the **variables.tf** file.<br />
More information is available here: [Creating a default ROSA cluster using Terraform](https://docs.openshift.com/rosa/rosa_hcp/terraform/rosa-hcp-creating-a-cluster-quickly-terraform.html).<br />
The script will help you install the necessary CLI if it is not yet available on your laptop.<br />

> [!NOTE]
> All ROSA HCP clusters created with Terraform must be destroyed using Terraform. 
> Please use option "**5) Terraform Menu**" in such cases.

<img width="464" alt="image" src="https://github.com/user-attachments/assets/eb564e24-d155-4f95-8194-bfc181991cb1">

#### Log File 
During the implementation phase a LOG file is created in the same folder as the shell script, so you can follow all the intermediate steps.
After a successful deployment a **cluster-admin** account is added to your cluster whose password will be recorded in the LOG file, feel free to change this to fit your security needs. See 'rosa create idp --help' for more information. 


# Notes around resources, deployment, etc.
ROSA with **HCP** clusters can be deployed in several flavors (e.g. Public, PrivateLink, Single-AZ, Multi-Zone), the number and type of resources created by this script will vary depending on what you choose. Here is an on overview of the [default cluster specifications](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html#rosa-sts-overview-of-the-default-cluster-specifications_rosa-hcp-sts-creating-a-cluster-quickly)

In the case of Option 3 (HCP PrivateLink in Single-AZ with Jump Host), a public subnet is included to allow egress via IGW+NGW and enable creation of a jump host to allow access to the cluster's private network via SSH. Also [an additional SG](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-aws-private-creating-cluster.html#rosa-hcp-aws-private-security-groups_rosa-hcp-aws-private-creating-cluster) will be created and attached to the PrivateLink endpoint to grant the necessary access to any entities outside of the VPC (eg. VPC peering, TGW). If you are using a firewall to control egress traffic, you must configure your firewall to grant access to the domain and port combinations [here](https://docs.openshift.com/rosa/rosa_install_access_delete_clusters/rosa_getting_started_iam/rosa-aws-prereqs.html#osd-aws-privatelink-firewall-prerequisites_prerequisites)
> [!NOTE]
> While ROSA HCP's control planes are always highly available, customer's worker node machinepools are scoped to single-AZs (subnets) only, they do not distribute automatically across AZs. If you want to have workers in
> three different AZs, the script will create three machinepools for you.
  - 1 NAT GW per AZ
  - 1 Internet GW in just one AZ, to allow the egress (NAT) traffic to the Internet
  - Enable DNS hostnames
  - Enable DNS resolution
- AWS Region: the aws configure command will ask for the default $AWS_Region which will be used as the target destination during the installation process
- Default HCP installer role is '$CLUSTER_NAME' prefix
if you choose to deploy your ROSA HCP cluster in North Virginia (us-east-1), then the script will create a minimum of 6 worker nodes. <br />
- Worker nodes:
  - the default instance type based on AWS x86 is "m5.xlarge", while the default Arm-based Graviton worker node instance type is "m6g.xlarge". There are different [instance types](https://docs.openshift.com/rosa/rosa_architecture/rosa_policy_service_definition/rosa-hcp-instance-types.html), you can change one of the following variables according to your choice.
     - DEF_MACHINE_TYPE="m5.xlarge"
     - DEF_GRAVITON_MACHINE_TYPE="m6g.xlarge" <br />
  - Single-AZ: 2x worker nodes will be created within the same subnet<br />
  - Multi-Zone: a minimum of 3x worker nodes will be created within the selected $AWS_REGION, **one per AZ**. This number may increase based on the number of AZs actually available within a specific Region. For example: if you choose to deploy your ROSA HCP cluster in North Virginia (us-east-1), then the script will create a minimum of 6 worker nodes. <br />
  
# Additional tools
From the main menù, click option #8 to access the " ROSA HCP TOOLS Menu ". <br />
Here you will find some specific actions you can take to manage your environment:

<img width="760" alt="image" src="https://github.com/user-attachments/assets/c049137d-5b6d-48b0-a429-76b2c408b872">

# Statistics (optional)
By using this script you accept and allow the collection of some OS data only for statistical purposes, precisely the result that comes out of this command: uname -srvm.

```
Example:
# uname -srvm
Linux 6.6.13-200.fc39.x86_64 #1 SMP PREEMPT_DYNAMIC Sat Jan 20 18:03:28 UTC 2024 x86_64
```
As you can see in the example above, this information is related to the operating system type and version, cpu (e.g. x86, ARM) on which the script is running. The script itself has no way of collecting other types of data other than those mentioned above. In any case, **the collection of this data is not mandatory**: if you do not want to contribute simply leave "line 55" commented out as it is by default:
```
# Optional statistics (eg. os type, version, platform)
# LAPTOP=$(uname -srvm)
```

# Wrap up
This script will make use of specific commands, options, and variables to successfully install your cluster(s) for you in a few minutes but **feel free to make changes to suit your needs**.
