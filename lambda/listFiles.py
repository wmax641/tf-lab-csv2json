import json
import boto3
import os

_PRESIGNED_URL_EXPIRY = 900
_MAX_OBJ = 200

def list_files_json(bucket_name, key_prefix):
    s3 = boto3.client('s3')
   
    try:
        r = s3.list_objects(Bucket=bucket_name, Prefix=key_prefix, MaxKeys=_MAX_OBJ)
    except Exception as e:
        # Upon any exception, exit and just return empty file list
        ret = json.dumps({"files":[]})
    
    objects = r["Contents"]
    filelist = []
    
    for o in objects:
        if o["Key"].endswith("/"):
            continue

        url = s3.generate_presigned_url(ClientMethod= 'get_object', 
                                        Params = {'Bucket':bucket_name, 'Key':o['Key']}, 
                                        ExpiresIn =_PRESIGNED_URL_EXPIRY)
        filelist.append({"name" : o["Key"].split("/")[-1], 
                         "url"  : url, 
                         "s3_presigned_url_expiry":_PRESIGNED_URL_EXPIRY, 
                         "http_method":"GET"})
    
    return ({"files":filelist})


def lambda_handler(event, context):
    bucket_name = os.environ['BUCKET_NAME']
    print(event)

    ret = list_files_json(bucket_name=bucket_name, key_prefix="")

    return {
        "statusCode" : 200,
        'headers':{"Content-Type": "application/json"},
        "body" : json.dumps(ret, indent=3)
    }


# For local testing
if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("usage: python3 listFiles.py <bucket name>")
        sys.exit(1)

    prefix = ""
    ret = list_files_json(bucket_name = sys.argv[1],key_prefix=prefix)
    print("Objects for key {}*\n".format(prefix))
    print(ret)
