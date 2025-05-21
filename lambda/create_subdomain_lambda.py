import json
import boto3

def lambda_handler(event, context):
    route53 = boto3.client('route53')
    hosted_zone_id = "${aws_route53_zone.main.zone_id}"
    subdomain = event['subdomain']
    ec2_public_ip = "${aws_instance.app_instance.public_ip}"
    
    # Create Route 53 A record
    response = route53.change_resource_record_sets(
        HostedZoneId=hosted_zone_id,
        ChangeBatch={
            'Changes': [
                {
                    'Action': 'UPSERT',
                    'ResourceRecordSet': {
                        'Name': subdomain,
                        'Type': 'A',
                        'TTL': 300,
                        'ResourceRecords': [
                            {
                                'Value': ec2_public_ip
                            }
                        ]
                    }
                }
            ]
        }
    )
    
    return {
        'subdomain': subdomain,
        'repo_url': event['repo_url'],
        'docker_image_repo': event['docker_image_repo'],
        'docker_image_tag': event['docker_image_tag'],
        'last_known_good_tag': event['last_known_good_tag']
    }