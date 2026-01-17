import os
import boto3
import json

def lambda_handler(event, context):
    # Get the environment and file path from environment variables
    environment = os.getenv('ENVIRONMENT', 'dev').lower()  # Default to 'dev' if not set
    file_path = os.getenv('FILE_PATH', '/mnt/efs/nats.config')
    directory = os.path.dirname(file_path)  # extract dir path
    cluster_ips = os.getenv('CLUSTER_IPS', '').split(',')  # Split the comma-separated IPs
    services = os.getenv('SERVICES', '').split(',')

    secrets_manager = boto3.client('secretsmanager')
    secrets = {}

    # Check permissions and ownership
    try:
        directory_stats = os.stat(directory)
        permissions = oct(directory_stats.st_mode)[-3:]  # e.g., 777
        owner_uid = directory_stats.st_uid  # User ID
        owner_gid = directory_stats.st_gid  # Group ID

        print(f"Directory permissions: {permissions}")
        print(f"Owner UID: {owner_uid}, GID: {owner_gid}")
    except Exception as e:
        return {
            "statusCode": 500,
            "body": f"Failed to check directory permissions: {str(e)}"
        }

    # Fetch the secret values for each service
    for service in services:
        secret_name = f"{service}"  # Assuming this is the naming convention for the secrets
        try:
            secret_value = secrets_manager.get_secret_value(SecretId=secret_name)
            secret_data = json.loads(secret_value['SecretString'])  # Parse JSON data
            print(f"Secret data for {service}: {secret_data}")  # Log the secret data

            # Extract the nkey from the correct key in the secret (e.g., USER_SERVICE_8_NKEY)
            nkey = secret_data.get(f"{service}", None)
            if nkey:
                print(f"Found nkey for {service}: {nkey}")  # Log the nkey value
                secrets[service] = nkey  # Store the nkey only
            else:
                print(f"No nkey found for {service}")
        except secrets_manager.exceptions.ResourceNotFoundException:
            print(f"Secret for {service} not found in Secrets Manager.")
        except Exception as e:
            print(f"Error fetching secret for {service}: {str(e)}")

    # Check if we should include the cluster section
    if environment != "dev" and cluster_ips:
        cluster_config = f""" 
        cluster {{
          name: "JSC"
          listen: "0.0.0.0:4245"
          routes = {cluster_ips}
        }}
        """
    else:
        cluster_config = ""

    # Define the rest of the NATS config content
    authorization_users = "\n".join([f"{{ nkey: \"{secrets.get(service, '')}\" }}," for service in services])

    nats_config_content = f"""
    port: 4222
    http:8222
    max_payload: 8388608

    websocket {{
      port: 443
      no_tls: true
    }}
    
    {cluster_config}

    authorization {{
      users = [
        {authorization_users}
      ]
    }}
    """

    # Write the content to the file in EFS
    try:
        with open(file_path, "w") as config_file:
            config_file.write(nats_config_content)
        return {
            "statusCode": 200,
            "body": f"nats.config file created successfully at {file_path}"
        }
    except PermissionError:
        return {
            "statusCode": 403,
            "body": "Permission denied: Lambda does not have write access to the directory."
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": f"Failed to create nats.config: {str(e)}"
        }
