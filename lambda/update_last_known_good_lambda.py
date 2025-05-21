import json
import boto3

def lambda_hander(event, context):
    ssm = boto3.client('ssm')
    
    if event['status'] == 'success':
        ssm.put_parameter(
            Name='/plugfolio/LastKnownGoodTag',
            Value=event['docker_image_tag'],
            Type='String',
            Overwrite=True
        )
        
    return event