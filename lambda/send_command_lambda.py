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
    parameters_input = event.get("Parameters", {})

    # Read values from the Parameters object passed in
    repo_url = parameters_input.get("RepoUrl", [""])[0]
    docker_image_repo = parameters_input.get("DockerImageRepo", [""])[0]
    docker_image_tag = parameters_input.get("DockerImageTag", [""])[0]
    subdomain = parameters_input.get("Subdomain", [""])[0]
    last_known_good_tag = parameters_input.get("LastKnownGoodTag", [""])[0]
    bucket_name = parameters_input.get("BucketName", [""])[0]
    internal_port = parameters_input.get("InternalPort", [""])[0]  # Add InternalPort

    parameters = {
        "RepoUrl": [repo_url],
        "DockerImageRepo": [docker_image_repo],
        "DockerImageTag": [docker_image_tag],
        "Subdomain": [subdomain],
        "LastKnownGoodTag": [last_known_good_tag],
        "BucketName": [bucket_name],
        "InternalPort": [internal_port]  # Include InternalPort
    }

    if not instance_ids or not document_name:
        raise ValueError("Missing required 'InstanceIds' or 'DocumentName'")

    print("Sending command with parameters:", json.dumps(parameters, indent=2))

    response = ssm.send_command(
        InstanceIds=instance_ids,
        DocumentName=document_name,
        Parameters=parameters
    )

    return {
        "ssm_command": json.loads(json.dumps(response, default=default_serializer))
    }