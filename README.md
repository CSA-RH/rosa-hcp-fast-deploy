# Note #1 - Technology Preview:
At the time we are writing, the ROSA HCPRed Hat OpenShift Service on AWS (ROSA) with Hosted Control Planes (HCP) is a Technology Preview feature only. 
Technology Preview features are not supported by Red Hat manufacturing service level agreements (SLAs) and may not be functionally complete. Red Hat does not recommend using them in production. These features provide early access to upcoming product features, allowing customers to test the functionality and provide feedback during the development process. For more information about the scope of Red Hat Technology Preview feature support, see Scope of Technology Preview Feature Support --> https://access.redhat.com/support/offerings/techpreview/

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
- RHPDS "blank environment" or AWS account; 
- The AWS Access Key and AWS Secret Access Key - "aws configure" command will take them in a sort of "cache" after the first run

# Resources
You can choose between Single-AZ or Multi-AZ deployment and we must have one public subnet with a NAT gateway so, in both cases and mainly for economic reasons, this shell script will consider having only 1x NAT gateway in just 1x AZ plus just one single Internet Gateway.

This is an example of the VPC with a Single Availability Zone (AZ):
![image](https://github.com/CSA-RH/HCP/assets/40911235/5b917abd-f8a9-4b2c-a256-254413cce29b)

This is an example of a Regional deployment which of course includes 3x Availability Zones (AZs):
![image](https://github.com/CSA-RH/HCP/assets/40911235/9811709c-4a38-4640-9f30-589f92fd8b6a)

# Usage:
1. Clone this repo
$ git clone [https://github.com/CSA-RH/HCP](https://github.com/CSA-RH/HCP)
Cloning into 'HCP'...
remote: Enumerating objects: 13, done.
remote: Counting objects: 100% (13/13), done.
remote: Compressing objects: 100% (12/12), done.
remote: Total 13 (delta 2), reused 0 (delta 0), pack-reused 0
Receiving objects: 100% (13/13), 18.44 KiB | 165.00 KiB/s, done.
Resolving deltas: 100% (2/2), done.

2. Go to path:
$ cd HCP/

3. Add execution permission
$ chmod +x rosa_hcp.sh 

4. Run the script and then make your choise:
$ ./rosa_hcp.sh 
1) Single-AZ 1
2) Multi-AZ 2
3) Delete_HCP 3
4) Quit

**Please enter your choice:**

For options 1) and 2) make sure you have both the "AWS Access Key" and the "AWS Secret Access Key" to start the process. 
During the HCP implementation phase a LOG file will be created so that you can follow the main tasks done by this script.

Here is an example:
$ ls -al
total 64
-rw-r--r--. 1 gmollo gmollo  1391 16 ott 17.18 **gm-2310161718.log**
-rw-r--r--. 1 gmollo gmollo 35149 16 ott 16.56 LICENSE
-rw-r--r--. 1 gmollo gmollo  2616 16 ott 16.56 README.md
-rwxr-xr-x. 1 gmollo gmollo 16857 16 ott 16.56 rosa_hcp.sh

$ tail -f gm-2310161718.log 
            "Region": "us-east-2"
        }
    }
}
INFO: Validating AWS credentials...
INFO: AWS credentials are valid!
INFO: Verifying permissions for non-STS clusters
INFO: Validating SCP policies...
INFO: AWS SCP policies ok
INFO: Ensuring cluster administrator user 'osdCcsAdmin'...
INFO: Validating SCP policies for 'osdCcsAdmin'...
INFO: AWS SCP policies ok
INFO: Validating cluster creation...
INFO: Cluster creation valid
#
rosa init ... done! going to create the VPC ...
Creating the VPC
....
....

Once you are done, feel free to destroy your ROSA HCP cluster by launching the same script and choosing option 3)

Thats all folks.
Enjoy
