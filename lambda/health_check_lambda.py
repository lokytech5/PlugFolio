import json
import requests

def lambda_handler(event, context):
    parameters = event.get("Command", {}).get("Parameters", {})

    subdomain = parameters.get("Subdomain", [""])[0]
    repo_url = parameters.get("RepoUrl", [""])[0]
    docker_image_repo = parameters.get("DockerImageRepo", [""])[0]
    docker_image_tag = parameters.get("DockerImageTag", [""])[0]
    last_known_good_tag = parameters.get("LastKnownGoodTag", [""])[0]

    health_url = f"http://{subdomain}/health"

    try:
        response = requests.get(health_url, timeout=5)
        if response.status_code == 200:
            return {
                "status": "success",
                "subdomain": subdomain,
                "repo_url": repo_url,
                "docker_image_repo": docker_image_repo,
                "docker_image_tag": docker_image_tag,
                "last_known_good_tag": last_known_good_tag
            }
        else:
            return {
                "status": "failure",
                "message": f"Health check failed with status code {response.status_code}"
            }
    except Exception as e:
        return {
            "status": "failure",
            "message": str(e)
        }
