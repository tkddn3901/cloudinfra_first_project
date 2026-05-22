#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
from dotenv import load_dotenv
import requests
from datetime import date, timedelta
from sqlalchemy import create_engine, text

# .env 로드
load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL",
    "postgresql://scott:tiger@10.0.3.158/scott_db"
)
SERVICE_KEY = os.getenv("DATA_GO_SERVICE_KEY", "")
if not SERVICE_KEY:
    print("❌ .env에 DATA_GO_SERVICE_KEY를 설정하세요.")
    exit(1)

# SQLAlchemy 엔진 생성
engine = create_engine(DATABASE_URL, echo=False)

# 공공데이터 API 엔드포인트
API_BASE_URL = (
    "https://apis.data.go.kr/1613000/RouteCongestionLevel/"
    "getRouteCongestionLevel"
)

# 조회 대상 지역 리스트
SIDO_SGG_CODES = [
    {"ctpv_cd": "11", "sgg_cd": "11680", "sgg_nm": "은평구"},
    {"ctpv_cd": "11", "sgg_cd": "11305", "sgg_nm": "강남구"},
]

def fetch_bus_congestion(opr_ymd: str) -> list:
    """공공데이터포털에서 opr_ymd 기준 각 지역 데이터를 가져옵니다."""
    headers = {"User-Agent": "Mozilla/5.0"}
    all_items = []
    for region in SIDO_SGG_CODES:
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
            print(f"▶ {region['sgg_nm']} ({opr_ymd}) 조회…")
            resp = requests.get(API_BASE_URL, params=params,
                                headers=headers, timeout=10)
            if resp.status_code == 500:
                print("  ∙ 500 에러, 건너뜁니다.")
                continue
            resp.raise_for_status()
            data = resp.json()
            items = (data.get("response", {})
                         .get("body", {})
                         .get("items", {})
                         .get("item", []))
            if isinstance(items, dict):
                items = [items]
            # 지역명 필드 추가
            for it in items:
                it["sgg_nm"] = region["sgg_nm"]
            print(f"  ∙ 수신 건수: {len(items)}")
            all_items.extend(items)
        except Exception as e:
            print(f"  ✗ {region['sgg_nm']} 조회 실패: {e}")
    return all_items

def save_to_db(records: list) -> int:
    """records 리스트를 DB에 INSERT/UPDATE 처리합니다."""
    if not records:
        return 0

    sql = text("""
      INSERT INTO route_congestion_level
        (opr_ymd, sgg_nm, emd_nm, tzon, cgst)
      VALUES
        (:opr_ymd, :sgg_nm, :emd_nm, :tzon, :cgst)
      ON CONFLICT (opr_ymd, sgg_nm, emd_nm, tzon)
      DO UPDATE SET cgst = EXCLUDED.cgst
    """)
    count = 0
    with engine.begin() as conn:
        for rec in records:
            try:
                conn.execute(sql, {
                    "opr_ymd": rec.get("opr_ymd"),
                    "sgg_nm":  rec.get("sgg_nm"),
                    "emd_nm":  rec.get("emd_nm"),
                    "tzon":    int(rec.get("tzon", 0)),
                    "cgst":    float(rec.get("cgst", 0.0))
                })
                count += 1
            except Exception as e:
                print(f"  ✗ 저장 에러 ({rec.get('sgg_nm')}): {e}")
    return count

def main():
    """30일 전 데이터만 가져와 DB에 저장합니다."""
    target_date = (date.today() - timedelta(days=30)).strftime("%Y%m%d")
    print("="*40)
    print(f"🚌 버스 혼잡도 데이터 수집 (날짜: {target_date})")
    print("="*40)
    items = fetch_bus_congestion(target_date)
    saved = save_to_db(items)
    print("-"*40)
    print(f"✅ 총 {saved}건 저장/갱신 완료")
    print("="*40)

if __name__ == "__main__":
    main()