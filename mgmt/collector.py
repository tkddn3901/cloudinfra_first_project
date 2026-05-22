import os
import logging
import requests
from datetime import date, datetime, timedelta
from dotenv import load_dotenv

from db import save_records, get_avg_cgst_by_tzon, get_demo_cgst
from aws_client import push_metric

load_dotenv()

logger = logging.getLogger(__name__)

SERVICE_KEY  = os.getenv("DATA_GO_SERVICE_KEY", "")
API_BASE_URL = "https://apis.data.go.kr/1613000/RouteCongestionLevel/getRouteCongestionLevel"

REGIONS = [
    {"ctpv_cd": "11", "sgg_cd": "11380", "sgg_nm": "은평구"},
    {"ctpv_cd": "11", "sgg_cd": "11680", "sgg_nm": "강남구"},
]

STAGE_THRESHOLDS = [(10, "한적"), (60, "원활"), (float("inf"), "혼잡")]


def get_stage(avg_cgst: float) -> str:
    for threshold, label in STAGE_THRESHOLDS:
        if avg_cgst <= threshold:
            return label
    return "혼잡"


def _fetch_region(opr_ymd: str, region: dict) -> list:
    """
    API는 노선×정류장 단위 raw 데이터(하루 ~15만 건)를 반환한다.
    전체를 가져오면 150번 이상 API 호출이 필요하므로,
    첫 1000건을 샘플로 가져와 (emd_nm, tzon)별 평균으로 집계 후 반환한다.
    """
    params = {
        "serviceKey": SERVICE_KEY,
        "pageNo":     1,
        "numOfRows":  1000,
        "opr_ymd":    opr_ymd,
        "ctpv_cd":    region["ctpv_cd"],
        "sgg_cd":     region["sgg_cd"],
        "dataType":   "JSON",
    }
    try:
        resp = requests.get(
            API_BASE_URL,
            params=params,
            headers={"User-Agent": "Mozilla/5.0"},
            timeout=10,
        )
        if resp.status_code == 500:
            logger.warning(f"{region['sgg_nm']}: 500 에러, 건너뜀")
            return []
        resp.raise_for_status()
        raw = (resp.json()
               .get("Response", {})
               .get("body", {})
               .get("items", {})
               .get("item", []))
        if isinstance(raw, dict):
            raw = [raw]
    except Exception as e:
        logger.error(f"{region['sgg_nm']} API 호출 실패: {e}")
        return []

    # (emd_nm, tzon)별 평균 cgst 집계
    from collections import defaultdict
    bucket = defaultdict(list)
    for it in raw:
        emd_nm = it.get("emd_nm", "")
        tzon   = int(it.get("tzon", 0))
        cgst   = float(it.get("cgst", 0.0))
        bucket[(emd_nm, tzon)].append(cgst)

    opr = raw[0]["opr_ymd"] if raw else opr_ymd
    return [
        {
            "opr_ymd": opr,
            "sgg_nm":  region["sgg_nm"],
            "emd_nm":  emd_nm,
            "tzon":    tzon,
            "cgst":    round(sum(vals) / len(vals), 2),
        }
        for (emd_nm, tzon), vals in bucket.items()
    ]


def collect_and_save() -> dict:
    """
    매일 자정 실행: 공공 API 수집 → PostgreSQL 저장
    30일 전 날짜 데이터를 지역별로 수집해 tzon 단위로 평균 집계 후 저장.
    """
    opr_ymd = (date.today() - timedelta(days=30)).strftime("%Y%m%d")
    logger.info(f"=== [자정 수집] 시작 (날짜: {opr_ymd}) ===")
    results = {}

    for region in REGIONS:
        sgg_nm = region["sgg_nm"]
        items  = _fetch_region(opr_ymd, region)
        saved  = save_records(items)
        results[sgg_nm] = {
            "opr_ymd": opr_ymd,
            "fetched": len(items),
            "saved":   saved,
        }
        logger.info(f"[자정 수집] {sgg_nm}: 수집={len(items)}, 저장={saved}")

    return results


def judge_and_scale() -> dict:
    """
    매시간 실행: DB에서 현재 tzon 혼잡도 조회 → CloudWatch push → ASG 조정.
    30일 전 같은 시간대 avg_cgst를 기준으로 오토스케일링 판단.
    """
    opr_ymd      = (date.today() - timedelta(days=30)).strftime("%Y%m%d")
    current_tzon = datetime.now().hour
    logger.info(f"=== [시간 판단] tzon={current_tzon} (날짜: {opr_ymd}) ===")
    results = {}

    for region in REGIONS:
        sgg_nm   = region["sgg_nm"]
        avg_cgst = get_avg_cgst_by_tzon(sgg_nm, opr_ymd, current_tzon)
        if avg_cgst is None:
            avg_cgst = 0.0

        push_metric(sgg_nm, avg_cgst)

        results[sgg_nm] = {
            "opr_ymd":  opr_ymd,
            "tzon":     current_tzon,
            "avg_cgst": avg_cgst,
            "stage":    get_stage(avg_cgst),
        }
        logger.info(f"[시간 판단] {sgg_nm}: tzon={current_tzon}, avg_cgst={avg_cgst}, stage={get_stage(avg_cgst)}")

    return results


def collect_and_push() -> dict:
    """수동 /collect 트리거: 수집+저장 후 즉시 판단·스케일링까지 한 번에 실행."""
    collect_result = collect_and_save()
    scale_result   = judge_and_scale()

    results = {}
    for sgg_nm in collect_result:
        results[sgg_nm] = {**collect_result[sgg_nm], **scale_result.get(sgg_nm, {})}
    return results


def judge_and_scale_demo() -> dict:
    """
    데모용: demo_congestion 테이블 기준으로
    현재 5분 버킷 tzon(0~11) 혼잡도 조회 → CloudWatch push → ASG 조정.
    """
    current_tzon = datetime.now().minute % 12  # 0~11, 1분마다 tzon 전진
    logger.info(f"=== [데모 판단] tzon={current_tzon} ===")
    results = {}

    for region in REGIONS:
        sgg_nm   = region["sgg_nm"]
        avg_cgst = get_demo_cgst(sgg_nm, current_tzon)
        if avg_cgst is None:
            avg_cgst = 0.0

        push_metric(sgg_nm, avg_cgst)

        results[sgg_nm] = {
            "tzon":     current_tzon,
            "avg_cgst": avg_cgst,
            "stage":    get_stage(avg_cgst),
        }
        logger.info(f"[데모 판단] {sgg_nm}: tzon={current_tzon}, avg_cgst={avg_cgst}, stage={get_stage(avg_cgst)}")

    return results
