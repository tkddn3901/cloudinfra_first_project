import os
from typing import Optional
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://scott:tiger@10.0.3.158/scott_db")
engine = create_engine(
    DATABASE_URL,
    echo=False,
    connect_args={"connect_timeout": 5},   # DB 연결 5초 타임아웃
)

_UPSERT = text("""
    INSERT INTO route_congestion_level (opr_ymd, sgg_nm, emd_nm, tzon, cgst)
    VALUES (:opr_ymd, :sgg_nm, :emd_nm, :tzon, :cgst)
    ON CONFLICT (opr_ymd, sgg_nm, emd_nm, tzon)
    DO UPDATE SET cgst = EXCLUDED.cgst
""")


def save_records(records: list) -> int:
    if not records:
        return 0
    count = 0
    with engine.begin() as conn:
        for rec in records:
            try:
                conn.execute(_UPSERT, {
                    "opr_ymd": rec.get("opr_ymd"),
                    "sgg_nm":  rec.get("sgg_nm"),
                    "emd_nm":  rec.get("emd_nm"),
                    "tzon":    int(rec.get("tzon", 0)),
                    "cgst":    float(rec.get("cgst", 0.0)),
                })
                count += 1
            except Exception as e:
                print(f"저장 에러 ({rec.get('sgg_nm')}): {e}")
    return count


def get_avg_cgst(sgg_nm: str, opr_ymd: str) -> Optional[float]:
    sql = text("""
        SELECT AVG(cgst) FROM route_congestion_level
        WHERE sgg_nm = :sgg_nm AND opr_ymd = :opr_ymd
    """)
    with engine.connect() as conn:
        val = conn.execute(sql, {"sgg_nm": sgg_nm, "opr_ymd": opr_ymd}).scalar()
        return round(float(val), 2) if val is not None else None


def get_avg_cgst_by_tzon(sgg_nm: str, opr_ymd: str, tzon: int) -> Optional[float]:
    """현재 시간대(tzon)의 평균 혼잡도 조회 — 오토스케일링 판단용."""
    sql = text("""
        SELECT AVG(cgst) FROM route_congestion_level
        WHERE sgg_nm = :sgg_nm AND opr_ymd = :opr_ymd AND tzon = :tzon
    """)
    with engine.connect() as conn:
        val = conn.execute(sql, {"sgg_nm": sgg_nm, "opr_ymd": opr_ymd, "tzon": tzon}).scalar()
        return round(float(val), 2) if val is not None else None


def get_latest_date(sgg_nm: str) -> Optional[str]:
    sql = text("""
        SELECT MAX(opr_ymd) FROM route_congestion_level
        WHERE sgg_nm = :sgg_nm
    """)
    with engine.connect() as conn:
        return conn.execute(sql, {"sgg_nm": sgg_nm}).scalar()


def get_history(sgg_nm: str) -> list:
    """가장 최근 수집 날짜의 시간대별 평균 혼잡도."""
    sql = text("""
        SELECT tzon, ROUND(AVG(cgst)::numeric, 2) AS avg_cgst
        FROM route_congestion_level
        WHERE sgg_nm = :sgg_nm
          AND opr_ymd = (
              SELECT MAX(opr_ymd) FROM route_congestion_level WHERE sgg_nm = :sgg_nm
          )
        GROUP BY tzon
        ORDER BY tzon
    """)
    with engine.connect() as conn:
        rows = conn.execute(sql, {"sgg_nm": sgg_nm}).fetchall()
        return [{"tzon": r[0], "avg_cgst": float(r[1])} for r in rows]


# ── 데모용 함수 ────────────────────────────────────────────

def get_demo_cgst(sgg_nm: str, tzon: int) -> Optional[float]:
    sql = text("SELECT cgst FROM demo_congestion WHERE sgg_nm = :sgg_nm AND tzon = :tzon")
    with engine.connect() as conn:
        val = conn.execute(sql, {"sgg_nm": sgg_nm, "tzon": tzon}).scalar()
        return float(val) if val is not None else None


def get_demo_all() -> list:
    sql = text("SELECT sgg_nm, tzon, cgst FROM demo_congestion ORDER BY sgg_nm, tzon")
    with engine.connect() as conn:
        rows = conn.execute(sql).fetchall()
        return [{"sgg_nm": r[0], "tzon": r[1], "cgst": float(r[2])} for r in rows]


def upsert_demo_cgst(sgg_nm: str, tzon: int, cgst: float):
    sql = text("""
        INSERT INTO demo_congestion (tzon, sgg_nm, cgst)
        VALUES (:tzon, :sgg_nm, :cgst)
        ON CONFLICT (tzon, sgg_nm) DO UPDATE SET cgst = EXCLUDED.cgst
    """)
    with engine.begin() as conn:
        conn.execute(sql, {"tzon": tzon, "sgg_nm": sgg_nm, "cgst": cgst})
