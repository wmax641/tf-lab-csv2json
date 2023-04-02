#!/usr/bin/env python3

import json
import boto3
import os
import re
from botocore.vendored import requests

_PRESIGNED_URL_EXPIRY = 3600
_KEY_RE_PATTERN = re.compile("^[A-Za-z0-9._-]+$")
_HINTS = {  "http_method":"POST", 
            "docs": [
                "https://boto3.amazonaws.com/v1/documentation/api/latest/guide/s3-presigned-urls.html#generating-a-presigned-url-to-upload-a-file",
                "https://docs.aws.amazon.com/AmazonS3/latest/userguide/S3OutpostsPresignedUrlUploadObject.html"
            ]
}

def get_upload_link(key, bucket_name, protected_keys_list):
    statusCode = 200

    if len(key) == 0: 
        statusCode = 400
        ret = { "requested_key":"", 
                "error":1, 
                "error_msg":"Invalid or empty 'key' parameter"}

    elif not bool(_KEY_RE_PATTERN.match(key)):
        statusCode = 403
        ret = { "requested_key":key,
                "error":1,
                "error_msg":'Forbidden key requested. Invalid chars.'}
    
    elif key in protected_keys_list:
        statusCode = 403
        ret = { "requested_key":key, 
                "error":1, 
                "error_msg": "Forbidden key requested. Use another key for upload"}

    else:
        s3 = boto3.client('s3')
        presigned_params = s3.generate_presigned_post(bucket_name, 
                                                      key,
                                                      ExpiresIn=_PRESIGNED_URL_EXPIRY)
        statusCode = 200
        ret = { "requested_key":key, 
                "error":0, 
                "s3_presigned_url_params":presigned_params, 
                "hints":_HINTS}

    return(statusCode, ret)

def lambda_handler(event, context):
    bucket_name = os.environ['BUCKET_NAME']
    protected_keys_list = os.environ["PROTECTED_FILES"].split(",")
    statusCode = 200

    # ensure key parameter exists
    if event["queryStringParameters"] is None or "key" not in event["queryStringParameters"]:
        statusCode = 400
        body = {"requested_key":"",
               "error":1,
               "error_msg":"Invalid or empty 'key' parameter"}
    # get upload link
    else: 
        try:
            key = event["queryStringParameters"]["key"]
            statusCode, body = get_upload_link(key, bucket_name, protected_keys_list)
        except Exception as e:
            statusCode = 500
            body = {"requested_key" : event["queryStringParameters"]["key"],
                    "error" : 1, 
                    "error_msg": "Unhandled server side error"}
    # Debug mode
    if event["queryStringParameters"] is not None and "debug" in event["queryStringParameters"]:
        body["event"] = event

    return {
        'statusCode': statusCode,
        'headers':{"Content-Type": "application/json"},
        'body': json.dumps(body, indent=3)
    }

if __name__ == "__main__":
    import sys

    if len(sys.argv) != 3:
        print("usage: python3 getUploadLink.py <bucket_name> <object_key>")
        sys.exit(1)

    protected_keys_list = ["datafile0.csv", "datafile1.csv", "datafile2.csv"
                           "datafile0.md5", "datafile1.md5", "datafile2.md5"]

    statusCode, ret = get_upload_link(sys.argv[2], sys.argv[1], protected_keys_list)
    print("HTTP - {}".format(statusCode))
    print(ret)
