INSTALL_DIR=$(pwd)
AWS_REGION=$(cat ~/.aws/config|grep region|awk '{print $3}')
NOW=$(date +"%y%m%d%H%M")
CLUSTER_NAME=$(ls "$INSTALL_DIR" |grep *.log| awk -F. '{print $1}')
CLUSTER_LOG=$INSTALL_DIR/$CLUSTER_NAME.log
PREFIX=${2:-$CLUSTER_NAME}
#
JUMP_HOST="$CLUSTER_NAME"-jump-host
JUMP_HOST_ID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=$JUMP_HOST Name=instance-state-name,Values=running --query "Reservations[*].Instances[*].InstanceId" --output text)
if [[ $JUMP_HOST_ID ]]
then
      	aws ec2 terminate-instances --instance-ids "$JUMP_HOST_ID" 2>&1 |tee -a "$CLUSTER_LOG"
	JUMP_HOST_KEY=$(aws ec2 describe-instances --filters Name=tag:Name,Values=$JUMP_HOST --query "Reservations[*].Instances[*].KeyName" --output text)
	echo "Deleting the key-pair named " "$JUMP_HOST_KEY" 2>&1 |tee -a "$CLUSTER_LOG"
	aws ec2 delete-key-pair --key-name "$JUMP_HOST_KEY" 2>&1 |tee -a "$CLUSTER_LOG"
else
      echo "bleaaaaaa"
fi

