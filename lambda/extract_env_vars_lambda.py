import json
from typing import List, Dict, Any

def lambda_handler(event, context):
    exported_env = event.get("ExportedEnvironmentVariables", [])
    keys_to_extract = event.get("KeysToExtract", [])

    def extract_values(env_list: List[Dict[str, Any]], keys: List[str]) -> Dict[str, str]:
        result = {}
        for key in keys:
            value = next((item.get("Value") for item in env_list if item.get("Name") == key), "")
            result[key] = value
        return result

    if not exported_env or not keys_to_extract:
        return {
            "status": "error",
            "message": "Missing ExportedEnvironmentVariables or KeysToExtract"
        }

    flat_env_vars = extract_values(exported_env, keys_to_extract)

    return {
        "status": "success",
        "extracted": flat_env_vars
    }
