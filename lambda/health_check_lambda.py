import json
import requests

def lambda_handler(event, context):
    # Log the event for debugging
    print("Event received:", json.dumps(event, indent=2))

    # Try to get Subdomain from created_subdomain (set by CreateSubdomain state)
    subdomain = event.get("created_subdomain", {}).get("subdomain", "")
    
    # Fallback to ssm_command.Command.Parameters.Subdomain (set by DeployApp state)
    if not subdomain:
        subdomain = event.get("ssm_command", {}).get("Command", {}).get("Parameters", {}).get("Subdomain", [""])[0]

    # Validate subdomain
    if not subdomain:
        return {
            "status": "failure",
            "message": "Subdomain not found in event data"
        }

    # Extract other parameters for return value (optional, based on Rollback needs)
    repo_url = event.get("fetched_params", {}).get("repo_url", "")
    docker_image_repo = event.get("fetched_params", {}).get("docker_image_repo", "")
    docker_image_tag = event.get("flat_vars", {}).get("extracted", {}).get("IMAGE_TAG", "")
    last_known_good_tag = event.get("fetched_params", {}).get("last_known_good_tag", "")

    # Construct the health check URL
    health_url = f"http://{subdomain}/health"
    print(f"Health check URL: {health_url}")

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
                "message": f"Health check failed with status code {response.status_code}",
                "subdomain": subdomain,
                "repo_url": repo_url,
                "docker_image_repo": docker_image_repo,
                "docker_image_tag": docker_image_tag,
                "last_known_good_tag": last_known_good_tag
            }
    except Exception as e:
        return {
            "status": "failure",
            "message": f"Health check failed: {str(e)}",
            "subdomain": subdomain,
            "repo_url": repo_url,
            "docker_image_repo": docker_image_repo,
            "docker_image_tag": docker_image_tag,
            "last_known_good_tag": last_known_good_tag
        }