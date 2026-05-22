#!/usr/bin/env python3
import os
import asyncio
import socket
from datetime import date, timedelta

import requests
from fastapi import FastAPI, HTTPException, Request, Query, Depends
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

load_dotenv()

_db_url = os.getenv("DATABASE_URL")
if not _db_url:
    raise RuntimeError("DATABASE_URL 환경변수 설정 필요")

# asyncpg 드라이버로 변환 (postgresql:// → postgresql+asyncpg://)
if _db_url.startswith("postgresql://"):
    _db_url = _db_url.replace("postgresql://", "postgresql+asyncpg://", 1)
DATABASE_URL = _db_url

MGMT_URL = os.getenv("MGMT_URL", "http://10.0.0.10:8000")

engine       = create_async_engine(
    DATABASE_URL,
    echo=False,
    connect_args={"timeout": 5},           # DB 연결 5초 타임아웃
)
SessionLocal = sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False)

app       = FastAPI(title="Bus Congestion API")
templates = Jinja2Templates(directory="templates")


# ── 의존성 ───────────────────────────────────────────────────
async def get_db() -> AsyncSession:
    async with SessionLocal() as session:
        yield session


# ── 유틸 ─────────────────────────────────────────────────────
def get_host_ip() -> str:
    try:
        return socket.gethostbyname(socket.gethostname())
    except Exception:
        return "unknown"


def get_stage(avg_cgst: float) -> tuple[str, str]:
    """(단계 레이블, Bootstrap 색상 클래스) 반환"""
    if avg_cgst <= 10:
        return "한적", "secondary"
    elif avg_cgst <= 60:
        return "원활", "success"
    else:
        return "혼잡", "danger"


async def fetch_asg_status(sgg_nm: str) -> dict:
    """MGMT 서버에서 ASG 현황(대수 + 인스턴스 IP) 조회"""
    try:
        data = await asyncio.to_thread(
            lambda: requests.get(f"{MGMT_URL}/status", timeout=5).json()
        )
        return data.get(sgg_nm, {}).get("asg", {})
    except Exception:
        return {}


async def get_region_data(sgg_nm: str, db: AsyncSession) -> dict:
    """HTML 렌더링에 필요한 전체 데이터 수집. DB/MGMT 실패 시 빈 값으로 대체."""
    opr_ymd   = (date.today() - timedelta(days=30)).strftime("%Y%m%d")
    avg_cgst  = None
    tzon_data = []

    try:
        avg_row = await db.execute(
            text("SELECT AVG(cgst) FROM route_congestion_level WHERE sgg_nm = :s AND opr_ymd = :d"),
            {"s": sgg_nm, "d": opr_ymd},
        )
        avg_val  = avg_row.scalar()
        avg_cgst = round(float(avg_val), 2) if avg_val is not None else None

        tzon_rows = await db.execute(
            text("""
                SELECT tzon, ROUND(AVG(cgst)::numeric, 2) AS avg_cgst
                FROM route_congestion_level
                WHERE sgg_nm = :s AND opr_ymd = :d
                GROUP BY tzon ORDER BY tzon
            """),
            {"s": sgg_nm, "d": opr_ymd},
        )
        tzon_data = [{"tzon": r[0], "avg_cgst": float(r[1])} for r in tzon_rows.fetchall()]
    except Exception as e:
        print(f"[WARN] DB 조회 실패 ({sgg_nm}): {e}")

    asg = await fetch_asg_status(sgg_nm)

    stage_label, stage_color = (
        get_stage(avg_cgst) if avg_cgst is not None else ("데이터 없음", "secondary")
    )

    return {
        "host_ip":     get_host_ip(),
        "sgg_nm":      sgg_nm,
        "opr_ymd":     opr_ymd,
        "avg_cgst":    avg_cgst,
        "stage":       stage_label,
        "stage_color": stage_color,
        "tzon_data":   tzon_data,
        "asg":         asg,
    }


# ── HTML 뷰 ──────────────────────────────────────────────────
@app.get("/gangnam", response_class=HTMLResponse)
async def view_gangnam(request: Request, db: AsyncSession = Depends(get_db)):
    ctx = await get_region_data("강남구", db)
    return templates.TemplateResponse("gangnam.html", {"request": request, **ctx})


@app.get("/eunpyeong", response_class=HTMLResponse)
async def view_eunpyeong(request: Request, db: AsyncSession = Depends(get_db)):
    ctx = await get_region_data("은평구", db)
    return templates.TemplateResponse("eunpyeong.html", {"request": request, **ctx})


# ── JSON API ─────────────────────────────────────────────────
class CongestionData(BaseModel):
    opr_ymd: str
    sgg_nm:  str
    emd_nm:  str
    tzon:    int
    cgst:    float

class CongestionResponse(BaseModel):
    success: bool
    count:   int
    data:    list[CongestionData]
    message: str = ""


@app.get("/congestion", response_model=CongestionResponse)
async def read_congestion(
    start:  str = Query(..., description="YYYY-MM-DD"),
    end:    str = Query(None),
    sgg_nm: str = Query(None),
    db: AsyncSession = Depends(get_db),
):
    try:
        s_date = date.fromisoformat(start)
        e_date = date.fromisoformat(end) if end else s_date
        if s_date > e_date:
            raise ValueError()
    except Exception:
        raise HTTPException(400, "start ≤ end 인 YYYY-MM-DD 형식 필요")

    sql = text("""
        SELECT opr_ymd, sgg_nm, emd_nm, tzon, cgst
        FROM route_congestion_level
        WHERE opr_ymd BETWEEN :s AND :e
          AND (:sgg_nm IS NULL OR sgg_nm = :sgg_nm)
        ORDER BY opr_ymd, sgg_nm, emd_nm, tzon
    """)
    rows = (await db.execute(sql, {"s": s_date, "e": e_date, "sgg_nm": sgg_nm})).fetchall()
    if not rows:
        return CongestionResponse(success=False, count=0, data=[], message="데이터 없음")

    data = [CongestionData(**dict(r._mapping)) for r in rows]
    return CongestionResponse(success=True, count=len(data), data=data,
                              message=f"{len(data)}건 조회")


@app.get("/health")
async def health():
    return {"status": "ok", "host_ip": get_host_ip()}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=True)
