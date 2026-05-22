import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

import scheduler
from collector import collect_and_push, get_stage, judge_and_scale_demo
from db import get_history, get_demo_all, get_demo_cgst, upsert_demo_cgst
from aws_client import get_asg_status, get_desired_capacity

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

templates = Jinja2Templates(directory="templates")

REGIONS = ["강남구", "은평구"]
ALB_URL  = os.getenv("ALB_URL", "")


@asynccontextmanager
async def lifespan(app: FastAPI):
    scheduler.start()
    yield
    scheduler.stop()


app = FastAPI(title="버스 혼잡도 MGMT 서버", lifespan=lifespan)


@app.get("/", response_class=HTMLResponse)
def dashboard(request: Request):
    return templates.TemplateResponse(request, "index.html", {"alb_url": ALB_URL})


@app.post("/collect")
def manual_collect():
    results = collect_and_push()
    return {"status": "ok", "results": results}


@app.get("/status")
def get_status():
    """데모 테이블 기준 현재 tzon 혼잡도 + ASG 상태 조회"""
    current_tzon = datetime.now().minute % 12
    try:
        status = {}
        for sgg_nm in REGIONS:
            cgst     = get_demo_cgst(sgg_nm, current_tzon)
            asg_info = get_asg_status(sgg_nm)
            status[sgg_nm] = {
                "avg_cgst":  cgst,
                "stage":     get_stage(cgst) if cgst is not None else "데이터 없음",
                "tzon":      current_tzon,
                "asg":       asg_info,
            }
        return status
    except Exception as e:
        raise HTTPException(503, detail=f"조회 실패: {e}")


@app.get("/history/{sgg_nm}")
def history(sgg_nm: str):
    try:
        return {"sgg_nm": sgg_nm, "data": get_history(sgg_nm)}
    except Exception as e:
        raise HTTPException(503, detail=f"DB 연결 실패: {e}")


@app.get("/health")
def health():
    return {"status": "ok"}


# ── 데모 엔드포인트 ────────────────────────────────────────

DEMO_SCENARIO = [
    # tzon, 강남구 cgst, 은평구 cgst
    (0,   5.0,  72.0),   # 강남 한적(0대)  / 은평 혼잡(2대)
    (1,  35.0,  80.0),   # 강남 원활(1대)  / 은평 혼잡(2대)
    (2,  78.0,  40.0),   # 강남 혼잡(2대)  / 은평 원활(1대)
    (3,  85.0,   8.0),   # 강남 혼잡(2대)  / 은평 한적(0대)
    (4,  42.0,   5.0),   # 강남 원활(1대)  / 은평 한적(0대)
    (5,   6.0,  62.0),   # 강남 한적(0대)  / 은평 혼잡(2대)
    (6,  65.0,  30.0),   # 강남 혼잡(2대)  / 은평 원활(1대)
    (7,  72.0,   5.0),   # 강남 혼잡(2대)  / 은평 한적(0대)
    (8,  25.0,  68.0),   # 강남 원활(1대)  / 은평 혼잡(2대)
    (9,   5.0,  75.0),   # 강남 한적(0대)  / 은평 혼잡(2대)
    (10, 50.0,  15.0),   # 강남 원활(1대)  / 은평 원활(1대)
    (11,  8.0,   6.0),   # 강남 한적(0대)  / 은평 한적(0대)
]


class DemoEntry(BaseModel):
    sgg_nm: str
    tzon:   int
    cgst:   float


@app.post("/demo/judge")
def demo_judge():
    try:
        return {"status": "ok", "results": judge_and_scale_demo()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/demo/reset")
def demo_reset():
    try:
        for tzon, gangnam_cgst, eunpyeong_cgst in DEMO_SCENARIO:
            upsert_demo_cgst("강남구", tzon, gangnam_cgst)
            upsert_demo_cgst("은평구", tzon, eunpyeong_cgst)
        return {"status": "ok", "message": f"{len(DEMO_SCENARIO)}개 구간 초기화 완료", "scenario": get_demo_all()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.put("/demo/data")
def demo_update(entry: DemoEntry):
    try:
        upsert_demo_cgst(entry.sgg_nm, entry.tzon, entry.cgst)
        return {"status": "ok", "updated": entry.dict()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/demo/table")
def demo_table():
    try:
        return {"data": get_demo_all()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
