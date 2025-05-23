import json
import boto3
import os

ssm = boto3.client('ssm')
stepfunctions = boto3.client('stepfunctions')

# Function to store the repo URL in Parameter Store
def store_repo_url(repo_url):
    ssm.put_parameter(
        Name='/plugfolio/GitRepoUrl',
        Value=repo_url,
        Type='String',
        Overwrite=True
    )

# Function to trigger a Step Function execution
def trigger_step_function(repo_url):
    return stepfunctions.start_execution(
        stateMachineArn=os.environ['STATE_MACHINE_ARN'],
        input=json.dumps({'repository_url': repo_url})
    )

# Main Lambda entry point
def lambda_handler(event, context):
    body = json.loads(event['body'])
    repo_url = body['repository']['clone_url']
    
    store_repo_url(repo_url)
    response = trigger_step_function(repo_url)
    
    return {
        'statusCode': 200,
        'body': json.dumps({'executionArn': response['executionArn']})
    }
