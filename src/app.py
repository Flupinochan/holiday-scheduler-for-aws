"""EventBridgeから毎日呼び出されて、祝日を除いた平日のみ実行する"""

import datetime
from pathlib import Path
from typing import Any

from google.auth import load_credentials_from_file
from googleapiclient.discovery import build

SCOPES = ["https://www.googleapis.com/auth/calendar.readonly"]
CREDENTIAL_FILE = f"{Path(__file__).parent / 'clientLibraryConfig-aws-provider.json'}"
if not Path(CREDENTIAL_FILE).exists():
    log_message = f"credential file not found: {CREDENTIAL_FILE}"
    raise RuntimeError(log_message)


def get_calendar_service() -> Any:  # noqa: ANN401
    """Google Calendar APIのサービスオブジェクトを取得して返却"""
    credentials, _ = load_credentials_from_file(
        CREDENTIAL_FILE,
        scopes=SCOPES,
    )

    return build(
        serviceName="calendar",
        version="v3",
        credentials=credentials,
        cache_discovery=False,
    )


def get_japanese_holidays() -> list[str]:
    """日本の祝日を取得して返却

    Returns:
        list[str]: 日本の祝日のリスト

    """
    service = get_calendar_service()

    now = datetime.datetime.now(tz=datetime.UTC).isoformat()

    events_result = (
        service.events()
        .list(
            calendarId="ja.japanese#holiday@group.v.calendar.google.com",
            timeMin=now,
            maxResults=10,
            singleEvents=True,
            orderBy="startTime",
        )
        .execute()
    )
    events = events_result.get("items", [])
    if not events:
        print("No upcoming events found.")
        return []

    # debug
    for event in events:
        print(
            event["start"].get("dateTime", event["start"].get("date")),
            event["summary"],
        )

    return [
        event["start"].get("dateTime", event["start"].get("date")) for event in events
    ]


def lambda_handler(_event: dict, _context: dict) -> None:
    """Entry Point"""
    holidays = get_japanese_holidays()
    today = datetime.datetime.now(tz=datetime.UTC).date()
    # degug
    # dotay = "2027-01-02"
    if str(today) in holidays:
        print("今日は祝日です。処理をスキップします")
    else:
        print("今日は平日です。処理を実行します")
