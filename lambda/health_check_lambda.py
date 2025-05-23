import json
import requests

def lambda_handler(event, context):
    subdomain = event['subdomain']
    health_url = f"http://{subdomain}/health"
    
    try:
        response = requests.get(health_url, timeout=5)
        if response.status_code == 200:
            return {
                'status': 'success',
                'repo_url': event['repo_url'],
                'docker_image_repo': event['docker_image_repo'],
                'docker_image_tag': event['docker_image_tag'],
                'last_known_good_tag': event['last_known_good_tag'],
                'subdomain': subdomain
            }
        else:
            return {
                'status': 'failure',
                'message': f"Health check failed with status code {response.status_code}"
            }
    except Exception as e:
        return {
            'status': 'failure',
            'message': str(e)
        }