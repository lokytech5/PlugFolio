import json
import boto3

def lambda_handler(event, context):
    ssm = boto3.client('ssm')

    # Supports event.health_result or full input
    result = event.get('health_result', event)

    if result.get('status') == 'success':
        docker_image_tag = result.get('docker_image_tag')
        if docker_image_tag:
            print(f"Storing last known good tag: {docker_image_tag}")
            ssm.put_parameter(
                Name='/plugfolio/LastKnownGoodTag',
                Value=docker_image_tag,
                Type='String',
                Overwrite=True
            )
        else:
            print("Warning: No docker_image_tag found in result")

    else:
        print(f"Health check failed or unknown status: {result}")

    return result
