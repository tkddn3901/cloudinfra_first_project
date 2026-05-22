import logging
from apscheduler.schedulers.background import BackgroundScheduler
from collector import collect_and_save, judge_and_scale_demo

logger     = logging.getLogger(__name__)
_scheduler = BackgroundScheduler()


def start():
    # 매일 자정: 공공 API 수집 → DB 저장
    _scheduler.add_job(
        collect_and_save,
        trigger="cron",
        hour=0,
        minute=0,
        id="collect_and_save",
        replace_existing=True,
    )

    # 매 1분: 데모 테이블 기준 판단·스케일링 (tzon = minute % 12)
    _scheduler.add_job(
        judge_and_scale_demo,
        trigger="interval",
        minutes=1,
        id="judge_and_scale_demo",
        replace_existing=True,
    )

    _scheduler.start()
    logger.info("스케줄러 시작 — 수집: 매일 00:00 / 데모: 매 1분")


def stop():
    _scheduler.shutdown(wait=False)
    logger.info("스케줄러 중지")
