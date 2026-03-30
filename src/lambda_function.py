import os
import json
import logging
from datetime import datetime, timezone

import boto3
import pytz
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

JAPAN_HOLIDAY_CALENDAR = "japanese__ja@holiday.calendar.google.com"
JST = pytz.timezone("Asia/Tokyo")
SECRET_ARN_ENV = "GCP_SERVICE_ACCOUNT_SECRET_ARN"


def fetch_gcp_credentials():
    secret_arn = os.environ.get(SECRET_ARN_ENV)
    if not secret_arn:
        raise ValueError(f"Environment variable {SECRET_ARN_ENV} is not set")

    client = boto3.client("secretsmanager")
    resp = client.get_secret_value(SecretId=secret_arn)
    secret_str = resp.get("SecretString")
    if not secret_str:
        raise ValueError("SecretString is empty")

    payload = json.loads(secret_str)
    credentials = service_account.Credentials.from_service_account_info(payload)
    return credentials


def as_utc_rfc3339(dt):
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


def is_weekend(date_obj):
    return date_obj.weekday() in (5, 6)


def is_holiday(date_obj, credentials):
    start_jst = JST.localize(datetime(date_obj.year, date_obj.month, date_obj.day, 0, 0, 0))
    end_jst = JST.localize(datetime(date_obj.year, date_obj.month, date_obj.day, 23, 59, 59))

    service = build("calendar", "v3", credentials=credentials, cache_discovery=False)
    try:
        events = (
            service.events()
            .list(
                calendarId=JAPAN_HOLIDAY_CALENDAR,
                timeMin=as_utc_rfc3339(start_jst),
                timeMax=as_utc_rfc3339(end_jst),
                singleEvents=True,
                orderBy="startTime",
                maxResults=10,
            )
            .execute()
        )
    except HttpError as err:
        logger.error("GCP Calendar API call failed: %s", err)
        raise

    items = events.get("items", [])
    logger.info("Found %d holiday events for %s", len(items), date_obj.isoformat())
    if len(items) > 0:
        logger.info("Holiday event names: %s", [it.get("summary") for it in items])
    return len(items) > 0


def handler(event, context):
    now_jst = datetime.now(JST)
    today = now_jst.date()
    logger.info("Lambda invoked at JST %s", now_jst.isoformat())

    if is_weekend(today):
        logger.info("Weekend detected, skipping business job")
        return {"status": "skipped", "reason": "weekend", "date": today.isoformat()}

    creds = fetch_gcp_credentials()
    try:
        if is_holiday(today, creds):
            logger.info("Holiday detected, skipping business job")
            return {"status": "skipped", "reason": "holiday", "date": today.isoformat()}
    except Exception as err:
        logger.exception("Error during holiday check")
        return {"status": "error", "reason": "holiday_check_failed", "error": str(err)}

    # ここに本番業務ロジックを実装
    try:
        logger.info("Business day confirmed, running business logic")
        # TODO: 処理を実行
        return {"status": "ok", "date": today.isoformat(), "detail": "executed"}
    except Exception as err:
        logger.exception("Business job failed")
        raise
