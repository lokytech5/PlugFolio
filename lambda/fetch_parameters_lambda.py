import json
import boto3
import yaml
import os
import subprocess
import shutil

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    
    # Fetch parameters from SSM
    repo_url = ssm.get_parameter(Name='/plugfolio/GitRepoUrl')['Parameter']['Value']
    docker_image_repo = ssm.get_parameter(Name='/plugfolio/DockerImageRepo')['Parameter']['Value']
    root_domain = ssm.get_parameter(Name='/plugfolio/RootDomain')['Parameter']['Value']
    last_known_good_tag = ssm.get_parameter(Name='/plugfolio/LastKnownGoodTag', WithDecryption=False).get('Parameter', {}).get('Value', 'initial')

    # Derive subdomain (e.g., username from repo URL)
    username = repo_url.split('/')[-2]  # e.g., "lokytech5" from "https://github.com/lokytech5/cloud-staticweb.git"
    subdomain = f"{username}.{root_domain}"

    # Clone the repository to a temporary directory
    temp_dir = "/tmp/repo"
    if os.path.exists(temp_dir):
        shutil.rmtree(temp_dir)
    os.makedirs(temp_dir)
    
    try:
        # Clone the repo
        subprocess.run(["git", "clone", repo_url, temp_dir], check=True, capture_output=True, text=True)

        # Read plugfolio.yml
        plugfolio_yml_path = os.path.join(temp_dir, "plugfolio.yml")
        if not os.path.exists(plugfolio_yml_path):
            raise FileNotFoundError(f"plugfolio.yml not found in {repo_url}")

        with open(plugfolio_yml_path, "r") as f:
            config = yaml.safe_load(f)
        
        # Extract internal_port from plugfolio.yml
        internal_port = config.get("app", {}).get("internal_port")
        if not internal_port:
            raise ValueError("internal_port not found in plugfolio.yml")

    except Exception as e:
        print(f"Error fetching or parsing plugfolio.yml: {str(e)}")
        # Fallback to a default port if plugfolio.yml can't be read
        internal_port = "3000"  # Default fallback
    finally:
        # Clean up the temporary directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

    return {
        'repo_url': repo_url,
        'docker_image_repo': docker_image_repo,
        'docker_image_tag': 'latest',  # Will be updated by CodeBuild
        'subdomain': subdomain,
        'last_known_good_tag': last_known_good_tag,
        'internal_port': str(internal_port)  # Ensure it's a string for SSM
    }