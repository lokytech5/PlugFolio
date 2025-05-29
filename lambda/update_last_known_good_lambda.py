import json
import boto3

def lambda_handler(event, context):
    ssm = boto3.client('ssm')

    result = event.get('health_result', {})

    if result.get('status') == 'success':
        ssm.put_parameter(
            Name='/plugfolio/LastKnownGoodTag',
            Value=result['docker_image_tag'],
            Type='String',
            Overwrite=True
        )
        
    return result
