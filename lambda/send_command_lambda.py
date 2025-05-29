import json
import boto3
from datetime import datetime

def default_serializer(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")

def lambda_handler(event, context):
    ssm = boto3.client('ssm')

    instance_ids = event.get('InstanceIds', [])
    document_name = event.get('DocumentName')
    parameters = event.get('Parameters', {})

    if not instance_ids or not document_name:
        raise ValueError("Missing required 'InstanceIds' or 'DocumentName'")

    # Log what's being sent (optional for debug)
    print("Sending command with parameters:", json.dumps(parameters, indent=2))

    response = ssm.send_command(
        InstanceIds=instance_ids,
        DocumentName=document_name,
        Parameters=parameters
    )

    return {
        "ssm_command": json.loads(json.dumps(response, default=default_serializer))
    }
