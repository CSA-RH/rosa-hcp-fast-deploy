aws ec2 run-instances \
    --image-id ami-06d4b7182ac3480fa \
    --count 1 \
    --instance-type t2.micro \
    --key-name bastion-host \
    --security-group-ids sg-07570e17ab8331f13 \
    --subnet-id $Public_Subnet \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bastion-host}]'
