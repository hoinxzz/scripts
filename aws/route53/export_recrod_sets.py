import boto3
import argparse
from prettytable import PrettyTable
import csv

def list_hosted_zones(profile_name):
    session = boto3.Session(profile_name=profile_name)
    client = session.client('route53')
    response = client.list_hosted_zones()
    return response['HostedZones']

def list_record_sets(profile_name, hosted_zone_id):
    session = boto3.Session(profile_name=profile_name)
    client = session.client('route53')
    response = client.list_resource_record_sets(HostedZoneId=hosted_zone_id)
    return response['ResourceRecordSets']

def main(profile_name):
    hosted_zones = list_hosted_zones(profile_name)
    all_records = []
    
    for zone in hosted_zones:
        zone_id = zone['Id'].split('/')[-1]
        print(f"Hosted Zone: {zone['Name']} (ID: {zone_id})")
        record_sets = list_record_sets(profile_name, zone_id)
        
        table = PrettyTable()
        table.field_names = ["Record Name", "Record Type", "Record Value"]
        
        for record in record_sets:
           # 특정 레코드 타입만 출력이 필요할 땐 주석 해제
           # if record['Type'] in ['CNAME', 'A']:
                if 'ResourceRecords' in record:
                    for resource_record in record['ResourceRecords']:
                        record_value = resource_record['Value']
                        table.add_row([record['Name'], record['Type'], record_value])
                        all_records.append([zone['Name'], record['Name'], record['Type'], record_value])
                elif 'AliasTarget' in record:
                    record_value = record['AliasTarget']['DNSName']
                    table.add_row([record['Name'], record['Type'], record_value])
                    all_records.append([zone['Name'], record['Name'], record['Type'], record_value])
        
        print(table)
    
    export_to_csv = input("Do you want to export the results to a CSV file? (yes/no): ").strip().lower()
    if export_to_csv == 'yes':
        csv_filename = f'aws_r53_record_sets_{profile_name}.csv'
        with open(csv_filename, mode='w', newline='') as file:
            writer = csv.writer(file)
            writer.writerow(["Hosted Zone", "Record Name", "Record Type", "Record Value"])
            writer.writerows(all_records)
        print(f"Data has been written to {csv_filename}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Process AWS CLI profile name.')
    parser.add_argument('profile_name', type=str, help='AWS CLI profile name')
    args = parser.parse_args()
    main(args.profile_name)
