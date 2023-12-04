# AWS ROSA Cluster with hosted control planes (HCP)
Automatically deploy a ROSA **HCP** cluster in a few minutes, using the CLI, that was the idea behind this shell script.<br />
A few simple but fundamental steps summarize the activities this script will do for you:
- The initial setup
  - Configure your AWS account and roles (eg. the account-wide IAM roles and policies, the cluster-specific Operator roles and policies, the OIDC identity provider, etc.)
  - Create the VPC, including Subnets, IGW, NGW, configuring Routes, etc.
- Create your ROSA **HCP** Cluster

Here is what you need:
- An AWS account (or an RHDP "blank environment")
- Your AWS Access Key and your AWS Secret Access Key
- ROSA CLI[^1] and AWS CLI already installed and updated

The entire process to create/delete a ROSA **HCP** cluster and all its resources will take approximately 15 minutes. <br /> Here is an on overview of the [default cluster specifications](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html#rosa-sts-overview-of-the-default-cluster-specifications_rosa-hcp-sts-creating-a-cluster-quickly).

[^1]: If you get an error like this: "_E: Failed to create cluster: Version 'X.Y.Z' is below minimum supported for Hosted Control Plane_", you'll probably have to update the ROSA CLI in order to be able to create the latest cluster version available.

# Resources
It is possible to choose between Single-AZ (2x workers) and Multi-AZ (3x workers), it is also possible to choose to implement a public or private ROSA **HCP** cluster. The number and type of subnets and other resources will vary depending on what you pick.

#### ROSA with HCP deployed on a public network:
Where public Subnets are expected, the script will consider having a minimal configuration like this:
- 1x NAT Gateway (NGW) in just one single AZ 
- 1x Internet Gateway (IGW) to allow the egress (NAT) traffic to the Internet<br />

![image](https://github.com/CSA-RH/aws-rosa-cluster-with-hosted-control-planes/assets/148223511/cbaeb255-c8a1-417f-8680-af11b5c2994e)

#### ROSA with HCP deployed on a private network
In the case of the private **HCP** cluster it is assumed that it will be reachable through a VPN or a Direct Connect service, therefore the script does not include the creation of any Public Subnets, IGW, NGWs in the VPC.
![image](https://github.com/CSA-RH/aws-rosa-cluster-with-hosted-control-planes/assets/148223511/400508f8-411d-46b2-9da1-4c472bbb92ef)


# Create your ROSA HCP cluster
From the AWS console, look for the “Red Hat OpenShift Service on AWS (ROSA)”, then : 
- enable the ROSA HCP service and complete your account connection so that AWS and Red Hat accounts are linked
- check Service Quotas, 
- ensure Elastic Load Balancing (ELB) service-linked role already exists.

Once your AWS and Red Hat account are linked you can start witht the HCP cluster installation.
1. Clone this repo
```
$ git clone https://github.com/CSA-RH/aws-rosa-cluster-with-hosted-control-planes

Cloning into 'aws-rosa-cluster-with-hosted-control-planes'...
remote: Enumerating objects: 118, done.<br />
remote: Counting objects: 100% (118/118), done.<br />
remote: Compressing objects: 100% (112/112), done.<br />
remote: Total 118 (delta 43), reused 11 (delta 5), pack-reused 0<br />
Receiving objects: 100% (118/118), 45.89 KiB | 1.64 MiB/s, done.<br />
Resolving deltas: 100% (43/43), done.<br />
```
2. Go to path:
```
$ cd aws-rosa-cluster-with-hosted-control-planes/
```

3. Add execution permissions
```
$ chmod +x rosa_hcp.sh 
```

4. Run the script and then make your choise
```
$ ./rosa_hcp.sh 

Welcome to the ROSA HCP installation menu
1) Single-AZ 
2) Single-AZ-Priv 
3) Multi-AZ 
4) Delete_HCP 
5) Quit

Please enter your choice: 1

AWS Access Key ID [****************OXCF]: 
AWS Secret Access Key [****************fCIn]: 
Default region name [us-east-2]: 
Default output format [json]:
```
> [!NOTE]
> When creating the cluster, the "**aws configure**" command is called first:
> - make sure you have both the "AWS Access Key" and the "AWS Secret Access Key" at hand to be able to start the process
> - the Region you specify here will be used as a target for the installation.<br />
> The AWS CLI will now remember your inputs, no further action is required until the ROSA **HPC** cluster installation is complete.

#### Installation Log File 
During the **HCP** cluster implementation phase a LOG file is created in the same folder as the shell script, so you can follow all the intermediate steps.
It is mandatory to keep this file in its original location to be able to automatically delete the cluster when done.

Here is an example:
```
$ tail -f gm-2310161718.log 

INFO: Validating AWS credentials...
INFO: AWS credentials are valid!
INFO: Verifying permissions for non-STS clusters
INFO: Validating SCP policies...
INFO: AWS SCP policies ok
INFO: Ensuring cluster administrator user 'osdCcsAdmin'...
INFO: Admin user 'osdCcsAdmin' created successfully!
INFO: Validating SCP policies for 'osdCcsAdmin'...
INFO: AWS SCP policies ok
INFO: Validating cluster creation...
INFO: Cluster creation valid
#
rosa init ... done! going to create the VPC ...
Creating the VPC
VPC_ID_VALUE  vpc-00c74df8b67f078c5
Creating the Private Subnet:  subnet-09aa813462bdc903c
#
VPC creation ... done! going to create account and operator roles, then your ROSA HCP Cluster ...
....
....
```

After a successful deployment,  a cluster-admin account will be added to your **HCP** cluster and its password will be logged in the LOG file.
```
INFO: Admin account has been added to cluster 'gm-2310161718'.
INFO: Please securely store this generated password. If you lose this password you can delete and recreate the cluster admin user.
INFO: To login, run the following command:
Example:
   oc login https://api.gm-2310161718.wxyz.p9.openshiftapps.com:443 --username cluster-admin --password p5BiM-tbPPa-p5BiM-tbPPa
```

# Delete your HCP cluster
Once you are done, feel free to destroy your ROSA **HCP** cluster by launching the same shell script and choosing option 4) this time. 
```
$ ./rosa_hcp.sh 


Welcome to the ROSA HCP installation menu
1) Single-AZ 
2) Single-AZ-Priv 
3) Multi-AZ 
4) Delete_HCP 
5) Quit

Please enter your choice: 4

INFO: Cluster 'gm-2311282318' will start uninstalling now
INFO: Your cluster 'gm-2311282318' will be deleted but the following objects may remain
INFO: Operator IAM Roles: - arn:aws:iam::790553242681:role/ManagedOpenShift-openshift-image-registry-installer-cloud-creden
...
...
```

It takes approximately 15 minutes to delete the HCP cluster, including its VPCs, IAM roles, OIDCs, etc.<br />
Please note that after the deletion process is complete the LOG file will be moved from its current location to **/tmp**.
