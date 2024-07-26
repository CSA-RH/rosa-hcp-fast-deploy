# AWS ROSA with hosted control planes cluster (ROSA HCP) fast deploy
The idea behind this shell script was to automatically create the necessary environment and deploy a ROSA **HCP** cluster in a few minutes, using the CLI. The initial setup includes the installation and configuration of the
   - Virtual Private Cloud (VPC), including Subnets, IGW, NGW, Routes, etc.
   - Account and Operator roles and policies
   - OIDC identity provider configuration

This is not intended to replace the [Red Hat official documentation](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html), but rather to practice installing your own test environments in such a short time: the entire process to install/delete a ROSA **HCP** cluster and all its resources will take approximately 15 minutes. <br /> 


#### Script prerequisites
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
<img width="381" alt="image" src="https://github.com/user-attachments/assets/06e4e3b8-3617-4ce0-ac64-779d9e0136b9">

The first 4 options require entering or updating your AWS access keys
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
Once you are done, feel free to destroy your ROSA **HCP** cluster by launching the same shell script and choosing option 5) this time. 
```
$ ./rosa_hcp.sh 

```
<img width="409" alt="image" src="https://github.com/user-attachments/assets/ee357ee8-5485-4051-872d-4be34da0af29">

```
Option 5 Picked - Removing ROSA with HCP
#
# Start deleting ROSA HCP cluster gm-1234567890, VPC, roles, etc. 
# Further details can be found in /home/gmollo/tools/cluster/svil/fast-rosa-hcp-depoly/gm-2401061517.log LOG file
#
Cluster deletion in progress 
INFO: To watch your cluster uninstallation logs, run 'rosa logs uninstall -c gm-2401061517 --watch'
...
```
It takes approximately 15 minutes to delete your cluster, including its VPCs, IAM roles, OIDCs, etc.<br />

#### Log File 
During the implementation phase a LOG file is created in the same folder as the shell script, so you can follow all the intermediate steps.
After a successful deployment a **cluster-admin** account is added to your cluster whose password will be recorded in the LOG file, feel free to change this to fit your security needs. See 'rosa create idp --help' for more information. 

> [!NOTE]
> It is mandatory to keep this file in its original location so that the script can automatically delete the cluster when necessary.
> Once the cluster deletion process is complete, the LOG file will be moved from its current location to the **/tmp** folder.

# Notes around resources, deployment, etc.
ROSA with **HCP** clusters can be deployed in several flavors (e.g. Public, PrivateLink, Single-AZ, Multi-Zone), the number and type of resources created by this script will vary depending on what you choose. Here is an on overview of the [default cluster specifications](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html#rosa-sts-overview-of-the-default-cluster-specifications_rosa-hcp-sts-creating-a-cluster-quickly)

AWS Resource created includes:
  - 1 [VPC](https://docs.openshift.com/rosa/rosa_install_access_delete_clusters/rosa_getting_started_iam/rosa-aws-prereqs.html#rosa-vpc_prerequisites) with cidr-block 10.0.0.0/16 will be created in the same Region that you intend to install your cluster. In these examples
  - 1 or more Public subnets
    - Single-AZ --> cidr-block 10.0.0.0/20
    - Multi-Zone  --> cidr-blocks 10.0.0.0/20; 10.0.16.0/20; 10.0.32.0/20
  - 1 or more Private subnets
    - Single-AZ --> cidr-block  10.0.128.0/20 <br />
  - Subnetes TAGS are like following:
    - Public subnet: Key=kubernetes.io/role/elb,Value=1
    - Private subnet: Key=kubernetes.io/role/internal-elb,Value=1<br />

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

<img width="649" alt="image" src="https://github.com/user-attachments/assets/a04e1eea-8d79-4c3e-940e-7c7b14e22eea">


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
