# Note #1 - Technology Preview:
At the time we are writing, the Red Hat OpenShift Service on AWS (ROSA) with Hosted Control Planes (HCP) is a **Technology Preview** feature only. Technology Preview features are not supported by Red Hat manufacturing service level agreements (SLAs) and may not be functionally complete. Red Hat does not recommend using them in production. These features provide early access to upcoming product features, allowing customers to test the functionality and provide feedback during the development process. For more information about the scope of Red Hat Technology Preview feature support, see Scope of Technology [Preview Feature Support](https://access.redhat.com/support/offerings/techpreview)

# Note #2:
Please note that when this repository was created there was no private link option.

# HCP - ROSA with hosted control planes
This is a single shell script that will create all the resources needed to deploy a public HCP cluster via the CLI.
In more depth the script will take care of:
- Set up your AWS account and roles (eg. the account-wide IAM roles and policies, cluster-specific Operator roles and policies, and OpenID Connect (OIDC) identity provider).
- Create the VPC;
- Create your ROSA HCP Cluster with a minimal configuration (2 workers/Single-AZ; 3 workers/Multi-AZ).
here is an on overview of the [default cluster specifications](https://docs.openshift.com/rosa/rosa_hcp/rosa-hcp-sts-creating-a-cluster-quickly.html#rosa-sts-overview-of-the-default-cluster-specifications_rosa-hcp-sts-creating-a-cluster-quickly).

# About the prerequisites
- ROSA CLI, AWS CLI
- AWS account or an RHPDS "blank environment" 
- The AWS Access Key and AWS Secret Access Key - "aws configure" command will take them in a sort of "cache" after the first run

# Resources
You can choose between Single-AZ or Multi-AZ deployment and we must have one public subnet with a NAT gateway so, in both cases and mainly for economic reasons, this shell script will consider having only 1x NAT gateway in just 1x AZ plus just one single Internet Gateway.

Here is an example of the VPC with a Single Availability Zone (AZ):
![image](https://github.com/CSA-RH/HCP/assets/40911235/5b917abd-f8a9-4b2c-a256-254413cce29b)

This is an example of a Regional deployment which of course includes 3x Availability Zones (AZs):
![image](https://github.com/CSA-RH/HCP/assets/40911235/9811709c-4a38-4640-9f30-589f92fd8b6a)

# Create your HCP cluster
1. Clone this repo
```
$ git clone [https://github.com/CSA-RH/HCP](https://github.com/CSA-RH/HCP)
```
Cloning into 'HCP'...
remote: Enumerating objects: 13, done.
remote: Counting objects: 100% (13/13), done.
remote: Compressing objects: 100% (12/12), done.
remote: Total 13 (delta 2), reused 0 (delta 0), pack-reused 0
Receiving objects: 100% (13/13), 18.44 KiB | 165.00 KiB/s, done.
Resolving deltas: 100% (2/2), done.

2. Go to path:
```
$ cd HCP/
```

3. Add execution permissions
```
$ chmod +x rosa_hcp.sh 
```

4. Run the script and then make your choise:
```
$ ./rosa_hcp.sh 

1) Single-AZ 1
2) Multi-AZ 2
3) Delete_HCP 3
4) Quit

Please enter your choice:
```

For options 1) and 2) make sure you have both the "AWS Access Key" and the "AWS Secret Access Key" to start the process. 

# About the LOG file
During the HCP implementation phase a LOG file will be created so you can follow the main activities performed by this shell script. 
The file will reside in the same directory as the shell script.

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
#
rosa init, done!
Creating the VPC
....
....
2023-10-16 15:29:29 +0000 UTC hostedclusters gm-2310161718 The hosted control plane is available
INFO: Cluster 'gm-2310161718' is now ready
```

A Cluster-Admin account will be added to your **HCP** Cluster after a successful implementation, its password will be recorded in the LOG file.
```
INFO: Admin account has been added to cluster 'gm-2310161718'.
INFO: Please securely store this generated password. If you lose this password you can delete and recreate the cluster admin user.
INFO: To login, run the following command:
Example:
   oc login https://api.gm-2310161718.wxyz.p9.openshiftapps.com:443 --username cluster-admin --password p5BIM-tbPPa-Y3RQB-ULS4b
```

# Delete your HCP cluster
Once you are done, feel free to destroy your ROSA **HCP** cluster by launching the same script and choosing option 3)
Deleting the cluster will also delete the LOG file at the end of the process. 
