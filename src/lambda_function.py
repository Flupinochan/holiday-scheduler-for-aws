import datetime
import json
import os

from google.auth import load_credentials_from_file
from googleapiclient.discovery import build

SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]

CREDENTIAL_FILE = os.path.join(
    os.path.dirname(__file__),
    "external_account.json",
)


def get_calendar_service():
    if not os.path.exists(CREDENTIAL_FILE):
        raise RuntimeError(f"credential file not found: {CREDENTIAL_FILE}")

    credentials, _ = load_credentials_from_file(
        CREDENTIAL_FILE,
        scopes=SCOPES,
    )

    service = build(
        "calendar",
        "v3",
        credentials=credentials,
        cache_discovery=False,
    )

    return service


def get_japanese_holidays():
    service = get_calendar_service()

    now = datetime.datetime.utcnow().isoformat() + "Z"

    result = (
        service.events()
        .list(
            calendarId="ja.japanese#holiday@group.v.calendar.google.com",
            timeMin=now,
            maxResults=20,
            singleEvents=True,
            orderBy="startTime",
        )
        .execute()
    )

    holidays = []

    for event in result.get("items", []):
        holidays.append(
            {
                "name": event["summary"],
                "date": event["start"]["date"],
            },
        )

    return holidays


def lambda_handler(event, context):
    try:
        holidays = get_japanese_holidays()

        return {
            "statusCode": 200,
            "body": json.dumps(
                holidays,
                ensure_ascii=False,
            ),
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "body": str(e),
        }
