import os
import csv
import uuid
import boto3
import datetime
import logging

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
sns = boto3.client('sns')
securityhub = boto3.client('securityhub')

# Environment variables
S3_BUCKET = os.environ.get('S3_BUCKET')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')
PRESIGNED_EXPIRATION = int(os.environ.get('PRESIGNED_EXPIRATION', '86400'))  # Default 24 hours


def flatten_resource(resource):
    """Simplify Security Hub resource to a string."""
    rtype = resource.get('Type', '')
    rid = resource.get('Id', '') or resource.get('IdRef', '')
    return f"{rtype}:{rid}"


def findings_to_rows(findings):
    """Convert Security Hub findings into CSV rows."""
    rows = []
    for f in findings:
        fid = f.get('Id')
        title = f.get('Title', '')
        desc = f.get('Description', '')
        severity = f.get('Severity', {}).get('Label', '')
        first_observed = f.get('FirstObservedAt', '')
        last_observed = f.get('LastObservedAt', '')
        product = f.get('ProductArn', '')
        generator = f.get('GeneratorId', '')
        resources = f.get('Resources', [])
        res_str = ';'.join([flatten_resource(r) for r in resources]) if resources else ''
        rows.append({
            'Id': fid,
            'Title': title,
            'Description': desc,
            'Severity': severity,
            'FirstObservedAt': first_observed,
            'LastObservedAt': last_observed,
            'ProductArn': product,
            'GeneratorId': generator,
            'Resources': res_str
        })
    return rows


def lambda_handler(event, context):
    """Main Lambda entry point."""
    try:
        logger.info("=== Starting Security Hub export ===")
        logger.info(f"Environment: S3_BUCKET={S3_BUCKET}, SNS_TOPIC_ARN={SNS_TOPIC_ARN}, PRESIGNED_EXPIRATION={PRESIGNED_EXPIRATION}")

        if not S3_BUCKET or not SNS_TOPIC_ARN:
            logger.error("Missing environment variables: S3_BUCKET or SNS_TOPIC_ARN")
            return {"error": "Missing environment variables"}

        # Get Security Hub findings
        paginator = securityhub.get_paginator('get_findings')
        page_iterator = paginator.paginate()
        all_findings = []

        for page in page_iterator:
            findings = page.get('Findings', [])
            logger.info(f"Fetched {len(findings)} findings from one page")
            all_findings.extend(findings)

        logger.info(f"Total findings collected: {len(all_findings)}")

        if not all_findings:
            logger.info("No findings retrieved from Security Hub")
            message = f"Security Hub returned no findings at {datetime.datetime.utcnow().isoformat()}"
            sns.publish(TopicArn=SNS_TOPIC_ARN, Message=message, Subject="Security Hub: No Findings")
            return {"message": "no findings"}

        # Convert findings to CSV
        rows = findings_to_rows(all_findings)
        fieldnames = ['Id', 'Title', 'Description', 'Severity', 'FirstObservedAt',
                      'LastObservedAt', 'ProductArn', 'GeneratorId', 'Resources']

        filename = f"securityhub-findings-{datetime.datetime.utcnow().strftime('%Y-%m-%dT%H%M%SZ')}-{uuid.uuid4().hex}.csv"
        tmp_path = f"/tmp/{filename}"

        logger.info(f"Writing {len(rows)} rows to temporary file: {tmp_path}")

        with open(tmp_path, mode='w', newline='', encoding='utf-8') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            for r in rows:
                for k in r:
                    if isinstance(r[k], str):
                        r[k] = r[k].replace('\n', ' ').replace('\r', ' ')
                writer.writerow(r)

        # Upload to S3
        s3_key = f"securityhub-exports/{filename}"
        logger.info(f"Uploading CSV to s3://{S3_BUCKET}/{s3_key}")
        with open(tmp_path, 'rb') as data:
            s3.put_object(Bucket=S3_BUCKET, Key=s3_key, Body=data)

        logger.info("File successfully uploaded to S3")

        # Generate presigned URL
        logger.info("Generating presigned URL for file")
        presigned_url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': S3_BUCKET, 'Key': s3_key},
            ExpiresIn=PRESIGNED_EXPIRATION
        )

        logger.info(f"Presigned URL generated: {presigned_url}")

        # Send SNS notification
        subject = "Security Hub Findings CSV Export"
        message = (
            f"Security Hub findings exported successfully at {datetime.datetime.utcnow().isoformat()} UTC.\n\n"
            f"Download link (expires in {PRESIGNED_EXPIRATION} seconds):\n{presigned_url}\n\n"
            f"S3 location: s3://{S3_BUCKET}/{s3_key}"
        )

        logger.info("Publishing SNS notification...")
        sns.publish(TopicArn=SNS_TOPIC_ARN, Message=message, Subject=subject)

        logger.info("=== Export completed successfully ===")

        return {
            "status": "success",
            "s3_key": s3_key,
            "presigned_url": presigned_url
        }

    except Exception as e:
        logger.error(f"Error occurred: {str(e)}", exc_info=True)
        return {"error": str(e)}
