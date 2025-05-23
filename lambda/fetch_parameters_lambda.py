import json
import boto3

def lambda_handler(event, context):
    ssm = boto3.client('ssm')
    
    # Fetch parameters
    repo_url = ssm.get_parameter(Name='/plugfolio/GitRepoUrl')['Parameter']['Value']
    docker_image_repo = ssm.get_parameter(Name='/plugfolio/DockerImageRepo')['Parameter']['Value']
    root_domain = ssm.get_parameter(Name='/plugfolio/RootDomain')['Parameter']['Value']

    # Derive subdomain (e.g., username from repo URL)
    username = repo_url.split('/')[-2]  # e.g., "dave" from "https://github.com/dave/my-app.git"
    subdomain = f"{username}.{root_domain}"

    return {
            'repo_url': repo_url,
            'docker_image_repo': docker_image_repo,
            'docker_image_tag': 'latest',  # Will be updated by CodeBuild
            'subdomain': subdomain,
            'last_known_good_tag': ssm.get_parameter(Name='/plugfolio/LastKnownGoodTag', WithDecryption=False).get('Parameter', {}).get('Value', 'initial')
    }