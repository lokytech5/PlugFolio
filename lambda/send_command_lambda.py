import json
import boto3
from datetime import datetime

def default_serializer(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")

def lambda_handler(event, context):
    ssm = boto3.client('ssm')

    response = ssm.send_command(
        InstanceIds=event['InstanceIds'],
        DocumentName=event['DocumentName'],
        Parameters={
            'RepoUrl': [event['RepoUrl']],
            'DockerImageRepo': [event['DockerImageRepo']],
            'DockerImageTag': [event['DockerImageTag']],
            'Subdomain': [event['Subdomain']],
            'BucketName': [event['BucketName']]
        }
    )

    # Serialize and return
    return json.loads(json.dumps(response, default=default_serializer))
