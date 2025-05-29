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

    # Read values directly from flattened Step Function state
    repo_url = event.get("repo_url")
    docker_image_repo = event.get("docker_image_repo")
    docker_image_tag = event.get("docker_image_tag")
    subdomain = event.get("subdomain")
    last_known_good_tag = event.get("last_known_good_tag")

    parameters = {
        "RepoUrl":           [repo_url or ""],
        "DockerImageRepo":   [docker_image_repo or ""],
        "DockerImageTag":    [docker_image_tag or ""],
        "Subdomain":         [subdomain or ""],
        "LastKnownGoodTag":  [last_known_good_tag or ""]
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
