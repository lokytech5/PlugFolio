import json
import boto3
import os

ssm = boto3.client('ssm')
stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    body = json.loads(event['body'])

    repo_url = body['repository']['clone_url']
    docker_image_repo = os.environ.get('DOCKER_IMAGE_REPO')  # Optional fallback
    docker_image_tag = body.get('docker_image_tag', 'latest')
    subdomain = body.get('subdomain', 'app.example.com')
    last_known_good_tag = 'initial'

    # Optionally store the repo URL in SSM
    ssm.put_parameter(
        Name='/plugfolio/GitRepoUrl',
        Value=repo_url,
        Type='String',
        Overwrite=True
    )

    # Construct full input payload
    execution_input = {
        'repo_url': repo_url,
        'docker_image_repo': docker_image_repo,
        'docker_image_tag': docker_image_tag,
        'subdomain': subdomain,
        'last_known_good_tag': last_known_good_tag
    }

    # Trigger Step Function
    response = stepfunctions.start_execution(
        stateMachineArn=os.environ['STATE_MACHINE_ARN'],
        input=json.dumps(execution_input)
    )

    return {
        'statusCode': 200,
        'body': json.dumps({'executionArn': response['executionArn']})
    }
