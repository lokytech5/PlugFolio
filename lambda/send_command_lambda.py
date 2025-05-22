import json
import boto3

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    response = ssm.send_command(
        InstanceIds=event['InstanceIds'],
        DocumentName=event['DocumentName'],
        Parameters=event['Parameters']
    )
    return response
