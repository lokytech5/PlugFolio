import json
import requests

def lambda_handler(event, context):
    subdomain = event["Command"]["Parameters"]["Subdomain"][0]
    health_url = f"http://{subdomain}/health"
    
    try:
        response = requests.get(health_url, timeout=5)
        if response.status_code == 200:
            return {
                'status': 'success',
                'subdomain': subdomain,
                # Optional: add the rest if needed
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
