#!/usr/bin/env python3

import json
import boto3
import os

_PRESIGNED_URL_EXPIRY = 3600
_MAX_OBJ = 20

def list_files_json(bucket_name, key_prefix):
    s3 = boto3.client('s3')
   
    r = s3.list_objects_v2(Bucket=bucket_name, Prefix=key_prefix, MaxKeys=_MAX_OBJ)
    
    objects = r["Contents"]
    filelist = []
   
    # skip objects that are "directories" and objects that begin with the wrong prefix
    for o in objects:
        if o["Key"].endswith("/"):
            continue
        # in the case the prefix is "", skip if key not in root key path
        elif key_prefix == "" and len(o["Key"].split("/")) > 1:
            continue
        # in the case the prefix is not empty, skip if key doesn't start with prefix
        elif key_prefix != "" and not o["Key"].startswith(key_prefix):
            continue

        url = s3.generate_presigned_url(ClientMethod= 'get_object', 
                                        Params = {'Bucket':bucket_name, 'Key':o['Key']}, 
                                        ExpiresIn =_PRESIGNED_URL_EXPIRY)
        filelist.append({"name" : o["Key"].split("/")[-1], "url"  : url})
    
    return (filelist)

def lambda_handler(event, context):

    bucket_name = os.environ['BUCKET_NAME']

    # check request path to determine which bucket to lookup
    if event['requestContext']["resourcePath"] == "/example":
        key_prefix = "example/"
    else:
        key_prefix = ""

    status_code = 200

    try:
        filelist = list_files_json(bucket_name=bucket_name, key_prefix=key_prefix)
        body = {"files":filelist, "error":0}
    except Exception as e:
        status_code = 500
        body = {"files":[], "error":1,"error_msg":"Error - {}".format(str(e))}

    # Debug mode
    if event["queryStringParameters"] is not None and "debug" in event["queryStringParameters"]:
        if event["queryStringParameters"]["debug"] == "1":
            body["event"] = event

    return {
        "statusCode" : status_code,
        'headers':{"Content-Type": "application/json"},
        "body" : json.dumps(body, indent=3)
    }


# For local testing
if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("usage: python3 list.py <bucket name>")
        sys.exit(1)

    prefix = "data/"
    ret = list_files_json(bucket_name = sys.argv[1],key_prefix=prefix)
    print("Objects for key {}*\n".format(prefix))
    print(ret)
