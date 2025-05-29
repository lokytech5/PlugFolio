import json
import boto3
from datetime import datetime

def default_serializer(obj):
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")

def extract_env_value(env_list, key):
    """Helper to extract a value by key from ExportedEnvironmentVariables"""
    for item in env_list:
        if item.get("Name") == key:
            return item.get("Value")
    return None

def lambda_handler(event, context):
    ssm = boto3.client('ssm')

    instance_ids = event.get('InstanceIds', [])
    document_name = event.get('DocumentName')

    # Extract values from exported_env list
    exported_env = event.get('exported_env', [])
    repo_url = extract_env_value(exported_env, "REPO_URL")
    image_tag = extract_env_value(exported_env, "IMAGE_TAG")
    subdomain = extract_env_value(exported_env, "SUBDOMAIN")

    # Other flat fields
    docker_image_repo = event.get("docker_image_repo")
    last_known_good_tag = event.get("last_known_good_tag")

    # Build SSM Parameters dict
    parameters = {
        "RepoUrl":         [repo_url or ""],
        "DockerImageRepo": [docker_image_repo or ""],
        "DockerImageTag":  [image_tag or ""],
        "Subdomain":       [subdomain or ""],
        "LastKnownGoodTag": [last_known_good_tag or ""]
    }

    # Safety check
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
