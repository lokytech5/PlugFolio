import json
import boto3

def lambda_handler(event, context):
    ssm = boto3.client('ssm')

    response = ssm.send_command(
        InstanceIds=event['InstanceIds'],
        DocumentName=event['DocumentName'],
        Parameters={
            'RepoUrl': [event['RepoUrl']],
            'DockerImageRepo': [event['DockerImageRepo']],
            'DockerImageTag': [event['DockerImageTag']],
            'Subdomain': [event['Subdomain']],
            'BucketName': [event['BucketName']]
        }
    )

    return response
